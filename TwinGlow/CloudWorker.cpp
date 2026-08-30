#include "CloudWorker.h"

#include <WiFi.h>
#include <new>

#include "Config.h"

namespace {
constexpr size_t kJobQueueLength = 6;
constexpr size_t kResultQueueLength = 6;
// 6144 was enough while the worker only ever read from Firestore and wrote to
// RTDB. BRIGHTNESS_WRITE added the first Firestore *patch* on this task, and
// that path overflowed the stack: measured on hardware 2026-08-30, a run of
// brightness button presses ended in
//   "Stack canary watchpoint triggered (twinglow-cloud)"
// and a reboot. The same patch shape (updateDeviceCapability) had always run on
// the Arduino loop task instead, which has far more room, so nothing caught it
// before. Sized with headroom rather than to the measured edge; the task is
// created during CONFIG_LOADING with ~68 KB free.
constexpr uint32_t kWorkerStackBytes = 12288;
constexpr UBaseType_t kWorkerStackWarningBytes = 2048;

bool deadlineIsInFuture(uint32_t deadline) {
    return deadline != 0 && (int32_t)(deadline - millis()) > 0;
}

const char* operationName(CloudOperation operation) {
    switch (operation) {
        case CloudOperation::PRESENCE: return "presence";
        case CloudOperation::TELEMETRY: return "telemetry";
        case CloudOperation::CONFIG_CHECK: return "config";
        case CloudOperation::REVISION_CHECK: return "revision";
        case CloudOperation::PAIR_EVENT: return "pair-event";
        case CloudOperation::ASSET_FETCH: return "asset";
        case CloudOperation::BRIGHTNESS_WRITE: return "brightness";
        default: return "unknown";
    }
}
} // namespace

CloudWorker::CloudWorker()
    : firebase(nullptr), firestore(nullptr), rtdb(nullptr),
      jobQueue(nullptr), resultQueue(nullptr), taskHandle(nullptr),
      started(false), paused(false), operationActive(false),
      backoffUntilMs(0), consecutiveTransportFailures(0),
      recoveryAttempts(0), latestBrightness(0),
      jobPending{false, false, false, false, false, false, false} {
}

bool CloudWorker::begin(FirebaseClientWrap* firebaseClient,
                        FirestoreRepo* firestoreRepository,
                        RtdbRepo* rtdbRepository) {
    if (started) return true;
    if (firebaseClient == nullptr) return false;

    firebase = firebaseClient;
    firestore = firestoreRepository;
    rtdb = rtdbRepository;
    jobQueue = xQueueCreate(kJobQueueLength, sizeof(CloudJob));
    resultQueue = xQueueCreate(kResultQueueLength, sizeof(CloudResult));
    if (jobQueue == nullptr || resultQueue == nullptr) {
        Serial.println(F("[CloudWorker] Queue allocation failed"));
        if (jobQueue != nullptr) vQueueDelete(jobQueue);
        if (resultQueue != nullptr) vQueueDelete(resultQueue);
        jobQueue = nullptr;
        resultQueue = nullptr;
        return false;
    }

    BaseType_t created = xTaskCreatePinnedToCore(
        taskEntry,
        "twinglow-cloud",
        kWorkerStackBytes,
        this,
        1,
        &taskHandle,
        0
    );
    if (created != pdPASS) {
        Serial.println(F("[CloudWorker] Task allocation failed"));
        vQueueDelete(jobQueue);
        vQueueDelete(resultQueue);
        jobQueue = nullptr;
        resultQueue = nullptr;
        taskHandle = nullptr;
        return false;
    }

    started = true;
    Serial.println(F("[CloudWorker] Periodic Firebase I/O running on core 0"));
    return true;
}

bool CloudWorker::isBackoffActive() const {
    return deadlineIsInFuture(backoffUntilMs);
}

void CloudWorker::pause() {
    portENTER_CRITICAL(&stateMux);
    paused = true;
    portEXIT_CRITICAL(&stateMux);
}

void CloudWorker::resume() {
    portENTER_CRITICAL(&stateMux);
    paused = false;
    portEXIT_CRITICAL(&stateMux);
}

bool CloudWorker::isBusy() {
    portENTER_CRITICAL(&stateMux);
    bool busy = operationActive;
    portEXIT_CRITICAL(&stateMux);
    return busy;
}

bool CloudWorker::enqueue(const CloudJob& job) {
    if (!started || paused || isBackoffActive()) return false;

    size_t index = (size_t)job.operation;
    if (index >= (size_t)CloudOperation::COUNT) return false;
    if (jobPending[index]) return true;

    jobPending[index] = true;
    if (xQueueSend(jobQueue, &job, 0) != pdTRUE) {
        jobPending[index] = false;
        Serial.print(F("[CloudWorker] Queue full, dropping "));
        Serial.println(operationName(job.operation));
        return false;
    }
    return true;
}

bool CloudWorker::requestPresence(bool online) {
    CloudJob job{};
    job.operation = CloudOperation::PRESENCE;
    job.online = online;
    return enqueue(job);
}

bool CloudWorker::requestTelemetry(float temperature, float humidity,
                                   float pressure, float gas) {
    CloudJob job{};
    job.operation = CloudOperation::TELEMETRY;
    job.temperature = temperature;
    job.humidity = humidity;
    job.pressure = pressure;
    job.gas = gas;
    return enqueue(job);
}

bool CloudWorker::requestConfigCheck() {
    CloudJob job{};
    job.operation = CloudOperation::CONFIG_CHECK;
    return enqueue(job);
}

bool CloudWorker::requestRevisionCheck() {
    CloudJob job{};
    job.operation = CloudOperation::REVISION_CHECK;
    return enqueue(job);
}

bool CloudWorker::requestPairEvent(const String& pairId, const String& screenId,
                                   const String& assetId) {
    CloudJob job{};
    job.operation = CloudOperation::PAIR_EVENT;
    strlcpy(job.pairId, pairId.c_str(), sizeof(job.pairId));
    strlcpy(job.screenId, screenId.c_str(), sizeof(job.screenId));
    strlcpy(job.assetId, assetId.c_str(), sizeof(job.assetId));
    return enqueue(job);
}

bool CloudWorker::requestBrightnessWrite(uint8_t brightness) {
    // Recorded before the enqueue, so a coalesced request still updates the
    // value the worker will send.
    latestBrightness = brightness;
    CloudJob job{};
    job.operation = CloudOperation::BRIGHTNESS_WRITE;
    return enqueue(job);
}

bool CloudWorker::requestAsset(const String& assetId) {
    CloudJob job{};
    job.operation = CloudOperation::ASSET_FETCH;
    strlcpy(job.assetId, assetId.c_str(), sizeof(job.assetId));
    return enqueue(job);
}

bool CloudWorker::popResult(CloudResult& result) {
    if (!started || xQueueReceive(resultQueue, &result, 0) != pdTRUE) return false;
    size_t index = (size_t)result.operation;
    if (index < (size_t)CloudOperation::COUNT) jobPending[index] = false;
    return true;
}

void CloudWorker::taskEntry(void* context) {
    static_cast<CloudWorker*>(context)->run();
}

void CloudWorker::run() {
    for (;;) {
        CloudJob job{};
        if (xQueueReceive(jobQueue, &job, portMAX_DELAY) != pdTRUE) continue;

        CloudResult result{};
        result.operation = job.operation;
        result.deviceDoc = nullptr;
        result.assetData = nullptr;
        if (job.operation == CloudOperation::ASSET_FETCH) {
            strlcpy(result.resourceId, job.assetId, sizeof(result.resourceId));
        }

        // A queued job can reach the worker after a previous job started a
        // cooldown, or while CONFIG_LOADING has paused network work.
        bool cooldownActive = isBackoffActive();
        portENTER_CRITICAL(&stateMux);
        bool canAttempt = !paused && !cooldownActive;
        if (canAttempt) operationActive = true;
        portEXIT_CRITICAL(&stateMux);

        if (!canAttempt) {
            result.attempted = false;
        } else {
            execute(job, result);
            recordOutcome(result.success, result.errorCode, operationName(job.operation));
            // A stack overflow here is a reboot with a register dump and no
            // hint at which operation caused it. Report the margin while it can
            // still be printed, so the next hungry call site is visible before
            // it trips the canary.
            UBaseType_t stackFreeBytes = uxTaskGetStackHighWaterMark(nullptr);
            if (stackFreeBytes < kWorkerStackWarningBytes) {
                Serial.print(F("[CloudWorker] Low stack after "));
                Serial.print(operationName(job.operation));
                Serial.print(F(": "));
                Serial.print((unsigned)stackFreeBytes);
                Serial.println(F(" bytes free"));
            }
            portENTER_CRITICAL(&stateMux);
            operationActive = false;
            portEXIT_CRITICAL(&stateMux);
        }

        if (xQueueSend(resultQueue, &result, portMAX_DELAY) != pdTRUE) {
            if (result.deviceDoc != nullptr) delete result.deviceDoc;
            if (result.assetData != nullptr) delete result.assetData;
        }
    }
}

void CloudWorker::execute(const CloudJob& job, CloudResult& result) {
    result.attempted = true;
    result.success = false;
    result.errorCode = 0;

    if (!WiFi.isConnected()) {
        result.errorCode = FIREBASE_ERROR_TCP_CONNECTION;
        return;
    }

    switch (job.operation) {
        case CloudOperation::PRESENCE:
            result.success = rtdb != nullptr && rtdb->updatePresence(job.online);
            break;

        case CloudOperation::TELEMETRY:
            result.success = rtdb != nullptr &&
                rtdb->pushTelemetry(job.temperature, job.humidity, job.pressure, job.gas);
            break;

        case CloudOperation::CONFIG_CHECK: {
            DeviceDoc* doc = new (std::nothrow) DeviceDoc();
            if (doc != nullptr && firestore != nullptr && firestore->checkConfigVersion(*doc)) {
                result.deviceDoc = doc;
                result.success = true;
            } else {
                delete doc;
            }
            break;
        }

        case CloudOperation::REVISION_CHECK:
            result.success = rtdb != nullptr && rtdb->getConfigRevision(result.revision);
            break;

        case CloudOperation::PAIR_EVENT:
            result.success = rtdb != nullptr &&
                rtdb->sendToPair(job.pairId, job.screenId, job.assetId);
            break;

        case CloudOperation::BRIGHTNESS_WRITE: {
            // Read here rather than from the job, so a burst of button presses
            // sends the value the panel settled on instead of the first one.
            uint8_t value = latestBrightness;
            result.brightness = value;
            result.success = firestore != nullptr && firestore->updateBrightness(value);
            break;
        }

        case CloudOperation::ASSET_FETCH: {
            AssetData* asset = new (std::nothrow) AssetData();
            if (asset != nullptr && firestore != nullptr &&
                firestore->getAsset(job.assetId, *asset)) {
                result.assetData = asset;
                result.success = true;
            } else {
                delete asset;
            }
            break;
        }

        default:
            break;
    }

    if (!result.success && firebase != nullptr) {
        result.errorCode = firebase->getLastErrorCode();
    }
}

void CloudWorker::recordOutcome(bool success, int errorCode, const char* name) {
    if (success) {
        if (consecutiveTransportFailures > 0 || recoveryAttempts > 0) {
            Serial.print(F("[CloudWorker] Connection recovered on "));
            Serial.println(name);
        }
        consecutiveTransportFailures = 0;
        recoveryAttempts = 0;
        backoffUntilMs = 0;
        return;
    }

    // HTTP errors are Firebase rules/auth/application failures. A zero error is
    // normally parsing or missing data. Neither is repaired by cycling Wi-Fi.
    if (errorCode >= 0) return;

    consecutiveTransportFailures++;
    Serial.print(F("[CloudWorker] Transport failure "));
    Serial.print(consecutiveTransportFailures);
    Serial.print('/');
    Serial.print(FIREBASE_FAILURES_BEFORE_RECOVERY);
    Serial.print(F(" during "));
    Serial.println(name);

    if (consecutiveTransportFailures < FIREBASE_FAILURES_BEFORE_RECOVERY) return;

    if (firebase != nullptr) {
        firebase->logTransportDiagnostics(name);
        firebase->resetTransport();
    }

    // WL_CONNECTED only means the ESP32 is associated with the access point;
    // it can remain true after the route/DNS/NAT path has died. Force a fresh
    // station session after repeated TCP failures.
    Serial.println(F("[CloudWorker] Cycling Wi-Fi after repeated TCP failures"));
    WiFi.disconnect(false, false);
    vTaskDelay(pdMS_TO_TICKS(100));
    WiFi.reconnect();

    recoveryAttempts++;
    unsigned long backoffMs = calculateBackoffMs();
    backoffUntilMs = millis() + backoffMs;
    consecutiveTransportFailures = 0;

    Serial.print(F("[CloudWorker] Cloud I/O paused for "));
    Serial.print(backoffMs / 1000);
    Serial.println(F("s; local playback remains active"));
}

unsigned long CloudWorker::calculateBackoffMs() const {
    uint8_t shift = recoveryAttempts > 0 ? recoveryAttempts - 1 : 0;
    if (shift > 4) shift = 4;
    unsigned long delayMs = FIREBASE_RECOVERY_BACKOFF_INITIAL_MS << shift;
    if (delayMs > FIREBASE_RECOVERY_BACKOFF_MAX_MS) {
        delayMs = FIREBASE_RECOVERY_BACKOFF_MAX_MS;
    }
    return delayMs;
}
