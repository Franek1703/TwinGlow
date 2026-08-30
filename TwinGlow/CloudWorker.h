#ifndef CLOUD_WORKER_H
#define CLOUD_WORKER_H

#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>

#include "FirebaseClientWrap.h"
#include "FirestoreRepo.h"
#include "RtdbRepo.h"

enum class CloudOperation : uint8_t {
    PRESENCE = 0,
    TELEMETRY = 1,
    CONFIG_CHECK = 2,
    REVISION_CHECK = 3,
    PAIR_EVENT = 4,
    ASSET_FETCH = 5,
    COUNT = 6
};

// Queue payloads contain only trivially copyable data. DeviceDoc owns Arduino
// Strings, so successful config reads cross the queue as a heap pointer and
// are deleted by the main loop after processing.
struct CloudResult {
    CloudOperation operation;
    bool attempted;
    bool success;
    int errorCode;
    DeviceDoc* deviceDoc;
    AssetData* assetData;
    int revision;
    char resourceId[96];
};

/**
 * Runs periodic Firebase I/O on the other ESP32 core.
 *
 * FirebaseClient calls are synchronous when backed by WiFiClientSecure, even
 * when the library method is labelled async: the TCP/TLS connect itself still
 * blocks. Keeping those calls here prevents a failed handshake from stopping
 * rendering and button scanning in Arduino loop().
 */
class CloudWorker {
public:
    CloudWorker();

    bool begin(FirebaseClientWrap* firebase, FirestoreRepo* firestore, RtdbRepo* rtdb);
    bool isStarted() const { return started; }

    bool requestPresence(bool online);
    bool requestTelemetry(float temperature, float humidity, float pressure, float gas);
    bool requestConfigCheck();
    bool requestRevisionCheck();
    bool requestPairEvent(const String& pairId, const String& screenId, const String& assetId);
    bool requestAsset(const String& assetId);

    // Non-blocking result retrieval; call repeatedly from loop().
    bool popResult(CloudResult& result);

    void pause();
    void resume();
    bool isBusy();
    bool isBackoffActive() const;
    uint8_t getConsecutiveFailures() const { return consecutiveTransportFailures; }

private:
    struct CloudJob {
        CloudOperation operation;
        bool online;
        float temperature;
        float humidity;
        float pressure;
        float gas;
        char pairId[96];
        char screenId[96];
        char assetId[96];
    };

    FirebaseClientWrap* firebase;
    FirestoreRepo* firestore;
    RtdbRepo* rtdb;
    QueueHandle_t jobQueue;
    QueueHandle_t resultQueue;
    TaskHandle_t taskHandle;

    volatile bool started;
    volatile bool paused;
    volatile bool operationActive;
    volatile uint32_t backoffUntilMs;
    volatile uint8_t consecutiveTransportFailures;
    uint8_t recoveryAttempts;
    portMUX_TYPE stateMux = portMUX_INITIALIZER_UNLOCKED;

    // request* and popResult are both called by the Arduino loop task, so these
    // flags do not need a cross-core lock. They coalesce identical jobs while
    // one is queued or running.
    bool jobPending[(size_t)CloudOperation::COUNT];

    bool enqueue(const CloudJob& job);
    void run();
    void execute(const CloudJob& job, CloudResult& result);
    void recordOutcome(bool success, int errorCode, const char* operationName);
    unsigned long calculateBackoffMs() const;
    static void taskEntry(void* context);
};

#endif // CLOUD_WORKER_H
