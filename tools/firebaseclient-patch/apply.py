#!/usr/bin/env python3
"""Apply TwinGlow's payload-move patch to an installed FirebaseClient.

See README.md for what this changes and why. Anchored string replacement is used
rather than a line-numbered diff so the patch survives unrelated drift in the
library, and refuses loudly when the code it targets has actually changed.
"""

import sys
from pathlib import Path

GUARD = "FIREBASECLIENT_PAYLOAD_MOVE_PATCH"

# (relative path, anchor that must appear exactly once, replacement)
HUNKS = [
    (
        "src/core/AsyncResult/AsyncResult.h",
        """#ifndef CORE_ASYNC_RESULT_ASYNC_RESULT_H
#define CORE_ASYNC_RESULT_ASYNC_RESULT_H
""",
        """#ifndef CORE_ASYNC_RESULT_ASYNC_RESULT_H
#define CORE_ASYNC_RESULT_ASYNC_RESULT_H

// TwinGlow local patch: AsyncResult::movePayload() plus its call site in
// AsyncClient.h. See tools/firebaseclient-patch/ in the TwinGlow repo for the
// diff, the reasoning and how to reapply after a library update. Firmware that
// depends on it checks for this macro.
#define FIREBASECLIENT_PAYLOAD_MOVE_PATCH 1
""",
    ),
    (
        "src/core/AsyncResult/AsyncResult.h",
        """    void setPayload(const String &data)
    {
        if (data.length())
        {
            data_log.push_back(-2, "");
            val[ares_ns::data_payload] = data;
        }
#if defined(ENABLE_DATABASE)
        setRefPayload(&rtdbResult, &val[ares_ns::data_payload]);
#endif
    }
""",
        """    void setPayload(const String &data)
    {
        if (data.length())
        {
            data_log.push_back(-2, "");
            val[ares_ns::data_payload] = data;
        }
#if defined(ENABLE_DATABASE)
        setRefPayload(&rtdbResult, &val[ares_ns::data_payload]);
#endif
    }

    // As setPayload(), but takes the caller's buffer over instead of duplicating
    // it. Copying leaves the body allocated twice for the length of the copy, so
    // a document needs two contiguous blocks of its own size at once. On a board
    // without PSRAM a large one fails that second allocation, and Arduino's
    // String reports a failed copy by emptying itself - the request then
    // completes with a zero-length payload and no error code, which reads like a
    // document that does not exist.
    //
    // String's move assignment reuses this object's existing buffer when it is
    // large enough and otherwise frees it before taking the source's, so this
    // path allocates nothing at all. That also releases the previous response's
    // retained buffer, which setPayload() would instead try to realloc.
    //
    // Only correct where the caller drops its own reference straight afterwards.
    void movePayload(String &data)
    {
        if (data.length())
        {
            data_log.push_back(-2, "");
            val[ares_ns::data_payload] = std::move(data);
        }
#if defined(ENABLE_DATABASE)
        setRefPayload(&rtdbResult, &val[ares_ns::data_payload]);
#endif
    }
""",
    ),
    (
        "src/core/AsyncClient/AsyncClient.h",
        """            if (!sData->response.flags.sse && payload->length())
            {
                sData->aResult.setPayload(*payload);
                if (sData->auth_used)
                    sData->response.auth_data_available = true;
                else
                {
                    clear(*payload);
                    sData->response.flags.payload_available = true;
                    sman.returnResult(sData, true);
                }
            }
""",
        """            if (!sData->response.flags.sse && payload->length())
            {
                if (sData->auth_used)
                {
                    // FirebaseApp parses the token out of response.val[payload]
                    // after this returns, so the auth path has to keep its own
                    // copy. Auth responses are small.
                    sData->aResult.setPayload(*payload);
                    sData->response.auth_data_available = true;
                }
                else
                {
                    // TwinGlow local patch: hand the buffer over rather than
                    // copying it. The copy was discarded by clear(*payload) on
                    // the very next line anyway, so the end state is identical -
                    // aResult owns the body, response.val[payload] is empty -
                    // but the peak is one copy instead of two. A ~10KB Firestore
                    // document otherwise needs ~20KB contiguous, which a
                    // fragmented ESP32 heap without PSRAM cannot supply, and the
                    // failure surfaces as an empty payload with no error code.
                    sData->aResult.movePayload(*payload);
                    sData->response.flags.payload_available = true;
                    sman.returnResult(sData, true);
                }
            }
""",
    ),
]

HUNKS.append((
    "src/firestore/DataOptions.h",
    '    explicit DocumentMask(const String &fieldPaths = "") { setFieldPaths(fieldPaths); }',
    '''    explicit DocumentMask(const String &fieldPaths = "") { setFieldPaths(fieldPaths); }

#define FIREBASECLIENT_DOCUMENT_MASK_COPY_PATCH 1
    // BaseObjects holds a pointer into BaseO2's own buffers. Default copying
    // aliases the source buffers, which may belong to a temporary mask.
    DocumentMask(const DocumentMask &other) : BaseO2() { *this = other; }
    DocumentMask &operator=(const DocumentMask &other)
    {
        if (this != &other)
        {
            buf[0] = other.buf[0];
            buf[1] = other.buf[1];
        }
        return *this;
    }'''
))

HUNKS.append((
    "src/core/AsyncClient/RequestHandler.h",
    r'''        sut.printTo(val[reqns::header], 300, "%s%s%s HTTP/1.1\r\n", path.length() == 0 || (path.length() && path[0] != '/') ? "/" : "", path.c_str(), extras.c_str());''',
    '''#define FIREBASECLIENT_REQUEST_LINE_PATCH 1
        // Append without the stock 300-byte format buffer: masks and page tokens can exceed it.
        if (path.length() == 0 || path[0] != '/') val[reqns::header] += "/";
        val[reqns::header] += path;
        val[reqns::header] += extras;
        val[reqns::header] += " HTTP/1.1\\r\\n";'''
))

DEFAULT_DIRS = [
    Path.home() / "Documents/Arduino/libraries/FirebaseClient",
    Path.home() / "Arduino/libraries/FirebaseClient",
]


def read_source(path):
    """Read without newline translation - FirebaseClient ships CRLF, and a
    round-trip through universal newlines would rewrite every line in the file
    alongside the three lines this patch actually changes."""
    with open(path, "r", encoding="utf-8", newline="") as fh:
        return fh.read()


def write_source(path, text):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)


def to_eol(text, crlf):
    """Retarget a patch fragment (written with \\n) at the file's own endings."""
    return text.replace("\n", "\r\n") if crlf else text


def find_library(explicit):
    if explicit:
        return Path(explicit).expanduser()
    for candidate in DEFAULT_DIRS:
        if candidate.is_dir():
            return candidate
    return None


def main(argv):
    check_only = "--check" in argv
    args = [a for a in argv if not a.startswith("--")]
    lib = find_library(args[0] if args else None)

    if lib is None or not lib.is_dir():
        print("error: FirebaseClient not found. Pass its path:", file=sys.stderr)
        print("  apply.sh /path/to/libraries/FirebaseClient", file=sys.stderr)
        return 2

    print(f"library: {lib}")

    for rel, _, _ in HUNKS:
        if not (lib / rel).is_file():
            print(f"error: missing {rel} - is this a FirebaseClient install?", file=sys.stderr)
            return 2

    # Verify every anchor before writing anything, so a library version this
    # patch does not understand leaves the install untouched rather than
    # half-modified.
    texts = {}
    crlf = {}
    for rel, anchor, _ in HUNKS:
        if rel not in texts:
            texts[rel] = read_source(lib / rel)
            crlf[rel] = "\r\n" in texts[rel]
        if texts[rel].count(to_eol(_, crlf[rel])) == 1:
            continue
        found = texts[rel].count(to_eol(anchor, crlf[rel]))
        if found != 1:
            print(
                f"error: anchor for {rel} matched {found} times, expected 1.\n"
                "The library has changed; re-derive the patch against this version "
                "(see README.md).",
                file=sys.stderr,
            )
            return 3

    if check_only:
        complete=all(to_eol(replacement,crlf[rel]) in texts[rel] for rel,anchor,replacement in HUNKS)
        print("patched" if complete else "NOT fully patched - run apply.sh")
        return 0 if complete else 1

    for rel, anchor, replacement in HUNKS:
        if to_eol(replacement,crlf[rel]) in texts[rel]:
            continue
        texts[rel] = texts[rel].replace(
            to_eol(anchor, crlf[rel]), to_eol(replacement, crlf[rel]), 1
        )

    for rel, text in texts.items():
        write_source(lib / rel, text)
        print(f"patched: {rel}")

    print("\ndone - rebuild the sketch to pick it up")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
