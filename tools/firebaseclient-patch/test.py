#!/usr/bin/env python3
"""Exercise the installed SDK's actual mask/options classes under ASan/UBSan.

Only Arduino formatting/transport dependencies are replaced. The base classes,
DocumentMask, and ListDocumentsOptions are extracted unchanged from the SDK.
--reproduce-original additionally proves that removing our copy fix reproduces
the dangling mask observed in the ESP32 backtrace.
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("patch", HERE / "apply.py")
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)
library = patch.find_library(os.environ.get("FIREBASECLIENT_ROOT"))
if library is None:
    raise SystemExit("FirebaseClient missing; set FIREBASECLIENT_ROOT")


def extract(source, name):
    start = source.index("class " + name + " :")
    end = source.index("\n};", start) + 3
    return source[start:end]


STUBS = r'''
#include <cassert>
#include <cstring>
#include <string>
#include <sstream>
class String {
    std::string value;
public:
    String() = default;
    String(const char* s):value(s?s:""){}
    String(const std::string& s):value(s){}
    String(int n):value(std::to_string(n)){}
    size_t length()const{return value.size();}
    const char* c_str()const{return value.c_str();}
    String& operator+=(const String& s){value+=s.value;return *this;}
    friend String operator+(const String& a,const String& b){return String(a.value+b.value);}
};
class Print {public:size_t print(const char*){return 0;}};
class Printable {public:virtual size_t printTo(Print&)const=0;};
// Arduino String::remove() in the SDK's teardown is immaterial to the lifetime
// checks here; the real buffer members still destruct normally under ASan.
class BufWriter {public:void clear(String*,size_t){}};
class ObjectWriter {
public:
    void clear(String& s){s=String();}
    String getBoolStr(bool v){return v?"true":"false";}
};
class JSONUtil {
public:
    String toString(const String& s){return s;}
    void addTokens(String& out,const String& key,const String& tokens,bool){out=key+":"+tokens;}
};
class URLUtil {
public:
    void addParam(String& out,const String& key,const String& value,bool& has){
        out+=has?"&":"?";out+=key;out+="=";out+=value;has=true;
    }
    void addParamsTokens(String& out,const String& key,const String& tokens,bool& has){
        std::istringstream input(tokens.c_str());std::string token;
        while(std::getline(input,token,',')){
            out+=has?"&":"?";out+=key;out+=String(token);has=true;
        }
    }
};
'''

TEST = r'''
static void contains(const char* actual,const char* expected){assert(actual&&strstr(actual,expected));}
int main(){
    ListDocumentsOptions options;
    options.pageSize(4).mask(DocumentMask("type,availableAssetIds"));
    // The source temporary is gone. Rebuilding the query used to dereference
    // the destroyed mask, precisely as getScreens does for subsequent pages.
    options.pageToken("page-two");
    contains(options.c_str(),"pageToken=page-two");
    contains(options.c_str(),"mask.fieldPaths=availableAssetIds");
    options.orderBy("order").showMissing(false);
    contains(options.c_str(),"mask.fieldPaths=type");
    DocumentMask assigned;
    {DocumentMask source("alpha,beta");assigned=source;}
    contains(assigned.c_str(),"alpha,beta");
    DocumentMask copied(assigned);
    assigned.setFieldPaths("changed");
    contains(copied.c_str(),"alpha,beta");
    copied=copied;
    contains(copied.c_str(),"alpha,beta");
    ListDocumentsOptions unmasked;
    unmasked.pageSize(4).pageToken("next");
    contains(unmasked.c_str(),"pageSize=4");
    assert(!strstr(unmasked.c_str(),"mask.fieldPaths"));
}
'''

objects = (library / "src/core/Utils/ObjectWriter.h").read_text()
options = (library / "src/firestore/DataOptions.h").read_text()
base = "\n".join(extract(objects, name) for name in ("BaseObjects", "BaseO2", "BaseO6"))
mask = extract(options, "DocumentMask")
listing = extract(options, "ListDocumentsOptions")
if "FIREBASECLIENT_DOCUMENT_MASK_COPY_PATCH" not in mask:
    raise SystemExit("Run tools/firebaseclient-patch/apply.sh before testing")

with tempfile.TemporaryDirectory(prefix="twinglow-mask-test-") as tmp:
    def run(mask_source, label):
        source = Path(tmp) / (label + ".cpp")
        binary = Path(tmp) / label
        source.write_text(STUBS + base + mask_source + listing + TEST)
        subprocess.run([os.environ.get("CXX", "c++"), "-std=c++17", "-g", "-O1",
                        "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
                        str(source), "-o", str(binary)], check=True)
        return subprocess.run([str(binary)], capture_output=True, text=True)

    if "--reproduce-original" in sys.argv:
        _, anchor, replacement = next(h for h in patch.HUNKS if h[0] == "src/firestore/DataOptions.h")
        original = mask.replace(replacement, anchor)
        assert original != mask
        broken = run(original, "original")
        assert broken.returncode != 0 and "AddressSanitizer" in broken.stderr, broken.stderr
        print("Original SDK: reproduced dangling mask with AddressSanitizer")
    fixed = run(mask, "patched")
    if fixed.returncode:
        raise SystemExit(fixed.stderr)
    print("Patched SDK: temporary mask, copy/assignment, pagination and no-mask checks passed")
