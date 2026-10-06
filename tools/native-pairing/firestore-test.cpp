#include "FirestoreModels.h"
#include <cassert>
#include <deque>
#include <iostream>

// The network is scripted; getAsset() below is extracted verbatim from the
// production source by test.sh, including metadata and legacy decoding.
struct DocumentMask { String fields; explicit DocumentMask(const String& s):fields(s){} };
struct GetDocumentOptions { DocumentMask mask; explicit GetDocumentOptions(DocumentMask m):mask(m){} };
namespace Firestore { struct Parent { Parent(const String&, const String&){} }; }
struct FakeError { int value=0; int code() const {return value;} };
struct AsyncClientClass { FakeError error; FakeError& lastError(){return error;} };
struct Response { const char* body; int code=0; };
struct FirebaseFirestoreType {
    std::deque<Response> responses;
    std::vector<String> masks;
    String get(AsyncClientClass& client, Firestore::Parent&, const String& path, const GetDocumentOptions& options) {
        assert(path=="assets/asset"); assert(!responses.empty());
        masks.push_back(options.mask.fields);
        auto next=responses.front(); responses.pop_front(); client.error.value=next.code;
        return String(next.body);
    }
};
struct FirebaseClientWrap {
    FirebaseFirestoreType docs; AsyncClientClass client; unsigned resets=0;
    void* getFirestore(){return &docs;}
    AsyncClientClass* getAsyncClient(){return &client;}
    void resetTransport(){++resets;}
};
class FirestoreRepo {
    FirebaseClientWrap* wrap; String projectId="test";
    String getAssetPath(const String& id){return String("assets/")+id;}
public:
    explicit FirestoreRepo(FirebaseClientWrap* w):wrap(w){}
    bool getAsset(const String&, AssetData&, const String& knownRevision=String());
};
#include "firestore-get-asset.inc"

int main() {
    const char* metadata=R"({"fields":{"type":{"stringValue":"IMAGE"}},"updateTime":"2026-10-06T14:00:00.000001Z"})";
    const char* content=R"({"fields":{"type":{"stringValue":"IMAGE"},"encoding":{"stringValue":"SPARSE_PACKED_V1"},"pixelsPacked":{"stringValue":"00ff0000"}},"updateTime":"2026-10-06T14:00:00.000001Z"})";
    FirebaseClientWrap transport; FirestoreRepo repo(&transport); AssetData result;
    transport.docs.responses.push_back({content});
    assert(repo.getAsset("asset",result) && !result.unchanged);
    assert(result.content.pixels[0].color==0xff0000);
    assert(result.content.sourceRevision=="2026-10-06T14:00:00.000001Z");
    assert(transport.docs.masks.size()==1 && transport.docs.masks[0]!="type");
    transport.docs.masks.clear();
    transport.docs.responses.push_back({metadata});
    assert(repo.getAsset("asset",result,"2026-10-06T14:00:00.000001Z") && result.unchanged);
    assert(transport.docs.masks.size()==1 && transport.docs.masks[0]=="type");
    assert(!result.content.isValid()); // Never forward empty content as a replacement.
    transport.docs.masks.clear();
    transport.docs.responses.push_back({metadata}); transport.docs.responses.push_back({content});
    assert(repo.getAsset("asset",result,"older-revision") && !result.unchanged);
    assert(transport.docs.masks.size()==2 && result.content.pixels[0].color==0xff0000);
    for(int error:{401,403,404,-1}) {
        transport.docs.responses.push_back({"{}",error});
        auto resets=transport.resets;
        assert(!repo.getAsset("asset",result,"known-revision") && !result.unchanged);
        assert(transport.resets==resets+1);
    }
    for(const char* invalid:{"", "{", "{}", "{\"fields\":{},\"updateTime\":42}"}) {
        transport.docs.responses.push_back({invalid});
        assert(!repo.getAsset("asset",result,"known-revision") && !result.unchanged);
    }
    transport.docs.responses.push_back({metadata}); transport.docs.responses.push_back({"{"});
    assert(!repo.getAsset("asset",result,"older-revision"));
    // Old map-based image documents continue to decode.
    transport.docs.responses.push_back({R"({"fields":{"type":{"stringValue":"IMAGE"},"encoding":{"stringValue":"SPARSE_I16_RGB888"},"pixels":{"arrayValue":{"values":[{"mapValue":{"fields":{"index":{"integerValue":"255"},"color":{"integerValue":"16777215"}}}}]}}},"updateTime":"2026-10-06T14:00:00.000002Z"})"});
    assert(repo.getAsset("asset",result) && result.content.pixels[0].index==255 && result.content.pixels[0].color==0xffffff);
    assert(transport.docs.responses.empty());
    std::cout<<"Native Firestore tests passed: masked revision checks, changed/uncached content, authorization/deletion/transport/parse failures, response lifetime, legacy image\n";
}
