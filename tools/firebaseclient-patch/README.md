# FirebaseClient patches

TwinGlow needs fixes for response-buffer memory use, long request lines, and
document-mask copying in the [FirebaseClient][lib] library. This directory
carries the patches so an Arduino IDE library update cannot undo them silently.

```sh
tools/firebaseclient-patch/apply.sh          # patch the installed library
tools/firebaseclient-patch/apply.sh --check  # report status, change nothing
```

`apply.sh` is idempotent: running it on an already-patched library reports that
and exits 0.

## The problem

`FirestoreRepo::getAsset()` reads asset documents that reach ~10 KB — a 16×16
animation stores every lit pixel of every frame as an 8-character run, and the
Firestore REST wrapper adds ~2.9 KB on top.

A stock FirebaseClient buffers each response body **twice**. `AsyncClient.h`
accumulates the body into `response.val[payload]`, then hands it to the result
with `aResult.setPayload(*payload)` — a full `String` copy — and throws the
original away on the very next line:

```cpp
sData->aResult.setPayload(*payload);   // allocates a second ~10KB block
if (sData->auth_used)
    sData->response.auth_data_available = true;
else
{
    clear(*payload);                   // ...and frees the first one here
    ...
}
```

So a 10 KB document needs **20 KB of contiguous heap**, and it needs it as a
second block while the first is still held. Two further details make it worse:

- The library's own mitigation, `ResponseHandler::reserveString()`, is compiled
  out unless `BOARD_HAS_PSRAM` is set. On a plain ESP32 it does nothing.
- `AsyncResult::clear()` uses `String::remove()` (`StringUtil.h:117`), which
  keeps the buffer. The **previous** response's block is therefore still
  allocated when the next fetch starts, and `setPayload` tries to `realloc` it.

When that second allocation fails, Arduino's `String::copy()` calls
`invalidate()` — it empties itself and reports nothing. The request completes
with a **zero-length payload and error code 0**, which is indistinguishable from
a document that does not exist:

```
[Firestore] getAsset response length: 0
[Firestore] getAsset empty response: id=asset_1788197152961 (document may not exist or network timeout)
[Firestore] AsyncClient status - code: 0, message:
```

Measured on a 5-screen playlist: the largest free block starts at ~36 KB and is
down to **12,788** by the sixth asset. A ~10.2 KB animation fails there. Freeing
the entire asset cache first does **not** fix it — that recovers 17 KB of total
heap but the largest block only reaches ~14 KB, because the freed blocks are
scattered between long-lived allocations and do not coalesce.

## The fix

Move the buffer instead of copying it. `String`'s move assignment reuses the
destination's existing buffer when it is large enough, and otherwise frees it
before taking the source's — so the move path **allocates nothing at all**, and
it releases the previous response's retained block as a side effect.

Peak drops from `2 × body` to `1 × body`. A 10.2 KB document then fits in the
~14 KB that even the fragmented runtime heap has.

The end state is byte-for-byte what the original produced: `aResult` owns the
body, `response.val[payload]` is empty. The copy was being discarded one line
later regardless.

### Three hunks

1. **`AsyncResult.h`** — define `FIREBASECLIENT_PAYLOAD_MOVE_PATCH` so firmware
   can detect an unpatched library at compile time.
2. **`AsyncResult.h`** — add `movePayload(String &)` beside `setPayload()`. It
   mirrors it exactly (`data_log.push_back`, `setRefPayload`) but moves.
3. **`AsyncClient.h`** — call `movePayload()` on the non-auth branch and drop the
   now-redundant `clear(*payload)`.

### Why the auth branch is left alone

`FirebaseApp.h:643` parses the token out of `response.val[payload]` *after*
`readResponse()` returns, so `auth_used` must keep its copy. Auth responses are
small, so there is nothing to gain there. The patch reshapes the `if` to make
that split explicit.

Other consumers of `response.val[payload]` — the upload download-URL extraction
and the header-collision workaround (`AsyncClient.h`, inside `readPayload()`) —
run *before* the handoff, and SSE is excluded by the enclosing
`!flags.sse` condition.

## Detection

`TwinGlow/FirestoreRepo.h` raises an `#error` when the macro is absent, so a
build against a freshly-updated library fails immediately instead of shipping
firmware that breaks at runtime:

```
error: #error "FirebaseClient is missing required TwinGlow patches.
Run tools/firebaseclient-patch/apply.sh and rebuild."
```

It is an `#error` and not a `#warning` on purpose: the sketch builds with
`--warnings none`, which suppresses `#warning` outright — verified, the warning
form was invisible in a normal build and only appeared under
`--warnings default`. Recovery is one command, so failing loudly costs less than
an unnoticed unpatched build.

## Upstream

Worth reporting: the double-buffering costs every non-PSRAM board 2× peak on
every response, and the failure mode is silent. A `reserveString()` that is not
gated behind `BOARD_HAS_PSRAM` would also help, since `Content-Length` is
already parsed into `payloadLen`.

[lib]: https://github.com/mobizt/FirebaseClient

## Request line patch required by pairing

The installed FirebaseClient 2.2.13 also formats the path and query through a
300-byte buffer in `RequestHandler::addRequestHeader`. Field masks and pagination
tokens can exceed it, truncating ` HTTP/1.1\r\n` and producing HTTP 400 errors.
The request-line hunk appends the strings directly and defines
`FIREBASECLIENT_REQUEST_LINE_PATCH`. `FirestoreRepo.h` requires this patch.
The installer checks each hunk independently, so it upgrades a previously
payload-patched installation and refuses incompatible upstream source.

Screens are fetched four at a time with a field mask that excludes preview
pixels. Assets use a mask for both packed and legacy encodings. Pagination still
follows `nextPageToken` until complete; failure preserves the live playlist.

## Document-mask lifetime patch (ESP32 restart fix)

FirebaseClient 2.2.13's `DocumentMask` inherits a pointer to its own string array
from `BaseObjects`. Its implicit copy operations copy that pointer as well as
the array. `ListDocumentsOptions::mask(DocumentMask(...))` therefore leaves its
stored mask pointing into a destroyed temporary after the statement finishes.
Calling `pageToken()` afterward rebuilds the query and dereferences the dangling
pointer through `msk.c_str()`. On the reported ESP32 build this becomes a null
read in `ListDocumentsOptions::set()` and a `LoadProhibited` restart.

The patch adds a copy constructor and assignment operator to `DocumentMask`.
They copy the field buffers while retaining the destination's own base pointer.
`FIREBASECLIENT_DOCUMENT_MASK_COPY_PATCH` is required by `FirestoreRepo.h` so an
unpatched Arduino library cannot silently reproduce this crash.

A second fix in `FirestorePagination.h` handles missing/null `nextPageToken`
values explicitly. ArduinoJson's `as<String>()` serializes them as the literal
text `"null"`, incorrectly requesting another page even for an empty collection.
Malformed non-string tokens fail the load, preserving the working playlist.

Run the regression tests with:

```sh
python3 tools/firebaseclient-patch/test.py --reproduce-original
bash tools/native-pairing/test.sh
```

The first test extracts the installed SDK's actual base, mask and list-options
classes, supplies host-side Arduino formatting stubs, and runs ASan/UBSan. It
reproduces the original dangling reference and checks copying, assignment,
temporary masks, page-token updates and requests without masks after the fix.
The native firmware tests cover missing, null, empty, valid and malformed page
tokens. These checks do not replace flashing and observing the physical ESP32.
