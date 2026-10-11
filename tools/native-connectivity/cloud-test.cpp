#include "CloudMessages.h"
#include "ConnectivityStatus.h"
#include "WiFi.h"
#include <cassert>
#include <iostream>
#include <new>
unsigned long fakeMillis = 100;
#define portENTER_CRITICAL(x) ((void)0)
#define portEXIT_CRITICAL(x) ((void)0)
constexpr int pdTRUE = 1;
struct Queue { unsigned sends = 0; CloudResult result{}; bool available = false; };
int xQueueSend(Queue* queue, const void*, unsigned) { ++queue->sends; return pdTRUE; }
int xQueueReceive(Queue* queue, CloudResult* result, unsigned) {
    if (!queue->available) return 0;
    *result = queue->result; queue->available = false; return pdTRUE;
}
const char* operationName(CloudOperation) { return "test"; }
struct FirebaseClientWrap { int error = 0; int getLastErrorCode() { return error; } } firebase;
struct Repo {
    bool success = true;
    int code = 0;
    bool call() { firebase.error = code; return success; }
};
struct FirestoreRepo : Repo {
    bool checkConfigVersion(DeviceDoc&) { return call(); }
    bool readSharingState(const String&, DeviceDoc&) { return call(); }
    bool getScreens(std::vector<ScreenConfig>&) { return call(); }
    void sharingSnapshot(DeviceDoc&) {}
    bool updateBrightness(uint8_t) { return call(); }
    bool getAsset(const String&, AssetData&, const String&) { return call(); }
} firestore;
struct RtdbRepo : Repo {
    bool updatePresence(bool) { return call(); }
    bool pushTelemetry(float,float,float,float) { return call(); }
    bool getPairState(PairState&) { return call(); }
    bool getConfigRevision(int&) { return call(); }
    bool sendToPair(PairSend&) { return call(); }
    bool getPairSnapshot(PairMeta&,PairSnapshot&) { return call(); }
    bool acknowledgePair(PairMeta&,bool) { return call(); }
} rtdb;
class CloudWorker {
public:
    struct CloudJob {
        CloudOperation operation{}; bool online = true, displayed = false;
        float temperature=0, humidity=0, pressure=0, gas=0;
        PairSend* pairSend = nullptr; PairMeta* pairMeta = nullptr;
        int revision=0; char assetId[96]{}, assetRevision[40]{};
    };
    FirebaseClientWrap* firebase = &::firebase;
    FirestoreRepo* firestore = &::firestore;
    RtdbRepo* rtdb = &::rtdb;
    bool started=true, paused=false, operationActive=false, watchdogTripped=false;
    uint32_t operationStartedMs=0, lastStuckLogMs=0;
    uint8_t watchdogTrips=0, latestBrightness=0;
    ConnectionHealth connectionHealth;
    bool jobPending[(size_t)CloudOperation::COUNT]{};
    Queue jobs, results;
    Queue* jobQueue=&jobs; Queue* resultQueue=&results;
    bool isBackoffActive() const { return false; }
    bool isBusy();
    bool enqueue(const CloudJob&);
    bool popResult(CloudResult&);
    void execute(const CloudJob&,CloudResult&);
    void serviceWatchdog();
    void recordServiceOutcome(CloudService,bool);
    ConnectivityStatus connectivityStatus(bool);
    void resetHealthConfirmation();
};
#include "cloud-runtime.inc"

CloudResult perform(CloudWorker& worker, CloudOperation operation) {
    CloudWorker::CloudJob job{}; job.operation = operation;
    CloudResult result{}; worker.execute(job,result);
    delete result.deviceDoc; delete result.assetData; delete result.pairState;
    delete result.pairSnapshot; delete result.screens;
    return result;
}
int main() {
    const auto online=ConnectivityStatus::Online, orange=ConnectivityStatus::FirebaseUnavailable, red=ConnectivityStatus::WifiOffline;
    CloudWorker worker;
    WiFi.link=WL_CONNECTED;
    assert(worker.connectivityStatus(false)==red && worker.connectivityStatus(true)==orange);
    worker.connectionHealth.setAuthReady(true);
    assert(perform(worker,CloudOperation::CONFIG_CHECK).success);
    assert(worker.connectivityStatus(true)==online);
    for (int code : {-1,401,403,408,429,500,503}) {
        firestore.success=false; firestore.code=code;
        assert(!perform(worker,CloudOperation::ASSET_FETCH).success);
        assert(worker.connectivityStatus(true)==orange && worker.connectivityStatus(false)==red);
        assert(perform(worker,CloudOperation::PRESENCE).success);
        assert(worker.connectivityStatus(true)==orange); // RTDB cannot heal Firestore.
        firestore.success=true; firestore.code=0;
        assert(perform(worker,CloudOperation::CONFIG_CHECK).success);
        assert(worker.connectivityStatus(true)==online);
    }
    for (int code : {0,400,404}) {
        firestore.success=false; firestore.code=code;
        perform(worker,CloudOperation::ASSET_FETCH);
        assert(worker.connectivityStatus(true)==online);
    }
    // No repository call: do not attribute a stale previous auth error.
    firebase.error=403; worker.firestore=nullptr;
    assert(perform(worker,CloudOperation::SCREENS_FETCH).errorCode==0);
    assert(worker.connectivityStatus(true)==online);
    worker.firestore=&firestore; firestore.success=true; firestore.code=0;
    rtdb.success=false; rtdb.code=403;
    perform(worker,CloudOperation::CONFIG_CHECK);
    assert(worker.connectivityStatus(true)==orange);
    perform(worker,CloudOperation::BRIGHTNESS_WRITE);
    assert(worker.connectivityStatus(true)==orange); // Firestore cannot heal RTDB.
    rtdb.success=true; rtdb.code=0;
    perform(worker,CloudOperation::PRESENCE);
    assert(worker.connectivityStatus(true)==online);
    fakeMillis+=60000;
    assert(worker.connectivityStatus(true)==orange);
    perform(worker,CloudOperation::PRESENCE);
    assert(worker.connectivityStatus(true)==online);
    worker.connectionHealth.setAuthReady(false);
    assert(worker.connectivityStatus(true)==orange);
    worker.connectionHealth.setAuthReady(true);
    worker.resetHealthConfirmation();
    perform(worker,CloudOperation::PRESENCE);
    assert(worker.connectivityStatus(true)==orange);
    perform(worker,CloudOperation::CONFIG_CHECK);
    assert(worker.connectivityStatus(true)==online);

    CloudWorker::CloudJob job{}; job.operation=CloudOperation::ASSET_FETCH;
    assert(worker.enqueue(job) && worker.jobs.sends==1);
    worker.operationActive=true; worker.operationStartedMs=fakeMillis;
    fakeMillis+=30000;
    worker.serviceWatchdog();
    assert(worker.connectivityStatus(true)==orange);
    for (unsigned i=0; i<100; ++i) { fakeMillis+=3000; worker.serviceWatchdog(); }
    assert(ESP.restarts==0 && worker.operationActive && worker.watchdogTrips==1);
    assert(worker.jobPending[(size_t)CloudOperation::ASSET_FETCH]);
    assert(!worker.enqueue(job) && worker.jobs.sends==1);
    // A following job can already be running before the loop observes idle.
    worker.operationStartedMs=fakeMillis;
    worker.serviceWatchdog();
    assert(!worker.watchdogTripped && worker.operationActive);
    assert(worker.jobPending[(size_t)CloudOperation::ASSET_FETCH]);
    // The owning call returns normally; only consuming its result clears flags.
    worker.operationActive=false; worker.serviceWatchdog();
    assert(!worker.watchdogTripped && worker.jobPending[(size_t)CloudOperation::ASSET_FETCH]);
    worker.results.result.operation=job.operation; worker.results.available=true;
    CloudResult returned{}; assert(worker.popResult(returned));
    assert(!worker.jobPending[(size_t)CloudOperation::ASSET_FETCH]);
    assert(worker.enqueue(job) && worker.jobs.sends==2);

    // Staleness arithmetic stays correct across the ESP32 millis() wrap.
    ConnectionHealth wrapped;
    wrapped.setAuthReady(true);
    wrapped.record(CloudService::Rtdb,true,0,UINT32_MAX-10000);
    wrapped.record(CloudService::Firestore,true,0,UINT32_MAX-10000);
    assert(wrapped.status(true,20000)==online);
    assert(wrapped.status(true,60000)==orange);
    std::cout << "Cloud tests passed: isolated services, auth/HTTP/transport, staleness, watchdog ownership\n";
}
