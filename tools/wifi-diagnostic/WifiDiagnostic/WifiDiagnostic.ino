// Standalone investigation of the saved TwinGlow Wi-Fi network. No Firebase,
// BLE, buttons, sensor or application tasks. NVS is opened read-only.
#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <Adafruit_NeoPixel.h>
#include <esp_wifi.h>
#include <esp_system.h>
#include <esp_arduino_version.h>
#include "ManagementFrame.h"
#ifdef TWINGLOW_EXTENDED_DIAGNOSTIC
#include <ESP_SSLClient.h>
#include "FirebaseRootCA.h"
#include <time.h>
#endif

#ifndef DIAGNOSTIC_MATRIX_PIN
#define DIAGNOSTIC_MATRIX_PIN 2
#endif
#ifndef DIAGNOSTIC_MATRIX_PIXELS
#define DIAGNOSTIC_MATRIX_PIXELS 256
#endif

using wifi_diagnostic::Kind;
struct AccessPoint { uint8_t bssid[6]; int32_t channel; };
struct Observation {
    uint32_t beacons = 0, auth = 0, assocReplies = 0, deauth = 0, disassoc = 0, protectedFrames = 0;
    uint16_t authAlgorithm = 0, authSequence = 0, authStatus = 0, assocStatus = 0, apReason = 0;
    uint32_t disconnects = 0;
    uint8_t driverReason = 0;
    int8_t rssi = 0;
    bool associated = false, gotIp = false;
};
static portMUX_TYPE observationMux = portMUX_INITIALIZER_UNLOCKED;
static Observation observation;
static uint8_t stationMac[6], selectedAp[6];
static String savedSsid, savedPassword;
static bool observing = false;

static Observation snapshot() {
    portENTER_CRITICAL(&observationMux);
    Observation copy = observation;
    portEXIT_CRITICAL(&observationMux);
    return copy;
}

static void onEvent(WiFiEvent_t event, WiFiEventInfo_t info) {
    portENTER_CRITICAL(&observationMux);
    if (observing) {
        if (event == ARDUINO_EVENT_WIFI_STA_CONNECTED) observation.associated = true;
        if (event == ARDUINO_EVENT_WIFI_STA_GOT_IP) observation.gotIp = true;
        if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
            ++observation.disconnects;
            observation.driverReason = info.wifi_sta_disconnected.reason;
            observation.rssi = info.wifi_sta_disconnected.rssi;
        }
    }
    portEXIT_CRITICAL(&observationMux);
}

static void onFrame(void* buffer, wifi_promiscuous_pkt_type_t type) {
    if (type != WIFI_PKT_MGMT || !buffer) return;
    const auto* packet = static_cast<const wifi_promiscuous_pkt_t*>(buffer);
    if (packet->rx_ctrl.rx_state != 0 || packet->rx_ctrl.sig_len < 4) return;
    // Parsing and counters only; no printing, allocation or Wi-Fi API calls
    // on the driver's task. The selected addresses also live under this lock.
    portENTER_CRITICAL(&observationMux);
    if (observing) {
        const auto reply = wifi_diagnostic::inspect(packet->payload, packet->rx_ctrl.sig_len - 4,
                                                    stationMac, selectedAp);
        switch (reply.kind) {
            case Kind::Beacon: ++observation.beacons; break;
            case Kind::Auth:
                ++observation.auth;
                observation.authAlgorithm = reply.algorithm;
                observation.authSequence = reply.sequence;
                observation.authStatus = reply.code;
                break;
            case Kind::Association:
                ++observation.assocReplies; observation.assocStatus = reply.code; break;
            case Kind::Deauth: ++observation.deauth; observation.apReason = reply.code; break;
            case Kind::Disassoc: ++observation.disassoc; observation.apReason = reply.code; break;
            case Kind::Protected: ++observation.protectedFrames; break;
            default: break;
        }
    }
    portEXIT_CRITICAL(&observationMux);
}

static bool check(esp_err_t error, const char* operation) {
    if (error == ESP_OK) return true;
    Serial.printf("[Diag] %s failed: %s (%d)\n", operation, esp_err_to_name(error), int(error));
    return false;
}

static bool startStation() {
    // Driver configuration stays in RAM, including credentials and TX power.
    WiFi.persistent(false);
    if (!WiFi.mode(WIFI_STA) || !WiFi.setAutoReconnect(false) || !WiFi.setSleep(false)) {
        Serial.println("[Diag] Station initialization failed");
        return false;
    }
    WiFi.setScanMethod(WIFI_ALL_CHANNEL_SCAN);
    WiFi.setSortMethod(WIFI_CONNECT_AP_BY_SIGNAL);
    return check(esp_wifi_set_protocol(WIFI_IF_STA, WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G | WIFI_PROTOCOL_11N), "protocol") &&
           check(esp_wifi_set_bandwidth(WIFI_IF_STA, WIFI_BW_HT20), "bandwidth");
}

static bool validPasswordShape(const String& password) {
    if (password.isEmpty()) return true;
    const size_t length = password.length();
    if (strlen(password.c_str()) != length) return false;
    if (length >= 8 && length <= 63) return true;
    if (length != 64) return false;
    for (size_t i = 0; i < length; ++i) {
        const char c = password[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return false;
    }
    return true;
}

#ifdef TWINGLOW_EXTENDED_DIAGNOSTIC
static void testPublicTls(int rxSize) {
    WiFiClient socket;
    ESP_SSLClient tls;
    tls.setClient(&socket);
    tls.setCACert(TWINGLOW_ROOT_CA);
    tls.setBufferSizes(rxSize, 1024);
    tls.setTimeout(5);
    tls.setHandshakeTimeout(8);
    tls.setX509Time(time(nullptr));
    // A large public Google API schema: no API keys, login or device data.
    const unsigned long started = millis();
    if (!tls.connect("firestore.googleapis.com", 443)) {
        Serial.printf("[Diag] TLS rx=%d connect=0 elapsedMs=%lu wifi=%d\n", rxSize,
                      millis() - started, WiFi.isConnected());
        socket.stop(); tls.stop();
        return;
    }
    const bool mfln = tls.getMFLNStatus(); // Engine is valid after successful connect.
    tls.print("GET /$discovery/rest?version=v1 HTTP/1.1\r\nHost: firestore.googleapis.com\r\n"
              "Accept-Encoding: identity\r\nConnection: close\r\n\r\n");
    size_t bytes = 0;
    uint8_t buffer[512];
    unsigned long lastData = millis();
    String firstLine;
    bool haveFirstLine = false;
    while (millis() - started < 30000 && millis() - lastData < 5000) {
        const int available = tls.available();
        if (available > 0) {
            const int read = tls.read(buffer, min(available, int(sizeof(buffer))));
            if (read > 0) {
                bytes += read; lastData = millis();
                for (int i = 0; i < read && !haveFirstLine; ++i) {
                    if (buffer[i] == '\n') haveFirstLine = true;
                    else if (buffer[i] != '\r' && firstLine.length() < 80) firstLine += char(buffer[i]);
                }
            }
        } else if (!tls.connected()) break;
        delay(1);
    }
    Serial.printf("[Diag] TLS rx=%d connect=1 mfln=%d bytes=%u status=%s elapsedMs=%lu wifi=%d\n",
                  rxSize, mfln, unsigned(bytes), firstLine.c_str(), millis() - started, WiFi.isConnected());
    // Do not call the error accessor on a freed/dangling engine in this SDK.
    socket.stop(); tls.stop();
}

static void runExtendedTrial(Adafruit_NeoPixel& pixels, uint8_t brightness) {
    portENTER_CRITICAL(&observationMux);
    observing = false;
    portEXIT_CRITICAL(&observationMux);
    if (!WiFi.mode(WIFI_OFF)) { Serial.println("[Diag] Extended radio stop failed"); return; }
    delay(600);
    if (!startStation()) return;
    // Match the empty-playlist grey status: capped PWM 8, saved brightness.
    // This recreates LED load without creating Firebase application objects.
    pixels.setBrightness(brightness ? brightness : 1);
    pixels.fill(pixels.Color(8, 8, 8)); pixels.show();
    portENTER_CRITICAL(&observationMux);
    observation = Observation{};
    observing = true;
    portEXIT_CRITICAL(&observationMux);
    Serial.printf("[Diag] EXTENDED begin: no BSSID/channel pin, default TX limit, grey LEDs brightness=%u\n", brightness);
    unsigned long started = millis();
    WiFi.begin(savedSsid.c_str(), savedPassword.isEmpty() ? nullptr : savedPassword.c_str());
    while (!WiFi.isConnected() && millis() - started < 25000) delay(5);
    if (!WiFi.isConnected()) {
        const auto result = snapshot();
        Serial.printf("[Diag] EXTENDED initial connection failed: associated=%d reason=%u rssi=%d\n",
                      result.associated, unsigned(result.driverReason), int(result.rssi));
        return;
    }
    Serial.printf("[Diag] EXTENDED connected: IP=%s RSSI=%d\n", WiFi.localIP().toString().c_str(), int(WiFi.RSSI()));
    configTime(0, 0, "pool.ntp.org", "time.google.com");
    started = millis();
    while (time(nullptr) < 1790000000 && millis() - started < 10000) delay(10);
    if (time(nullptr) >= 1790000000) {
        testPublicTls(4096);
        testPublicTls(16384);
    } else Serial.println("[Diag] NTP unavailable; certificate-verified public TLS comparison skipped");
    // Longer than the ~6.5-minute loss measured in the full application.
    const unsigned long holdStarted = millis();
    unsigned long lastProbe = holdStarted - 20000;
    while (WiFi.isConnected() && millis() - holdStarted < 480000) {
        if (millis() - lastProbe >= 20000) {
            lastProbe = millis();
            IPAddress resolved;
            const bool dns = WiFi.hostByName("firestore.googleapis.com", resolved) == 1;
            WiFiClient probe;
            const bool tcp = dns && probe.connect(resolved, 443, 2000) == 1;
            probe.stop();
            Serial.printf("[Diag] HOLD elapsedMs=%lu wifi=%d RSSI=%d dns=%d tcp443=%d heap=%u maxBlock=%u\n",
                          millis() - holdStarted, WiFi.isConnected(), int(WiFi.RSSI()), dns, tcp,
                          ESP.getFreeHeap(), ESP.getMaxAllocHeap());
        }
        delay(5);
    }
    const auto result = snapshot();
    Serial.printf("[Diag] EXTENDED result: elapsedMs=%lu wifi=%d disconnects=%lu reason=%u rssi=%d\n",
                  millis() - holdStarted, WiFi.isConnected(), (unsigned long)result.disconnects,
                  unsigned(result.driverReason), int(result.rssi));
    portENTER_CRITICAL(&observationMux);
    observing = false;
    portEXIT_CRITICAL(&observationMux);
}
#endif

static void runTrial(const AccessPoint& ap, int8_t txPower, bool capture, int trial) {
    portENTER_CRITICAL(&observationMux);
    observing = false;
    portEXIT_CRITICAL(&observationMux);
    // Match production's fresh radio sessions. Preserve TwinGlow's NVS data.
    if (!WiFi.mode(WIFI_OFF)) { Serial.println("[Diag] Radio stop failed"); return; }
    delay(600);
    if (!startStation() || !check(esp_wifi_set_max_tx_power(txPower), "TX power")) return;
    int8_t actualPower = 0;
    if (!check(esp_wifi_get_max_tx_power(&actualPower), "TX power readback")) return;
    Serial.printf("[Diag] Trial=%d capture=%d txLimit=%.2fdBm AP=%02X:%02X:%02X:%02X:%02X:%02X channel=%ld\n",
                  trial, capture, actualPower / 4.0, ap.bssid[0], ap.bssid[1], ap.bssid[2],
                  ap.bssid[3], ap.bssid[4], ap.bssid[5], long(ap.channel));
    // One plain trial per power level controls for the observer's overhead.
    if (capture) {
        wifi_promiscuous_filter_t filter = {};
        filter.filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT;
        if (!check(esp_wifi_set_promiscuous_filter(&filter), "capture filter") ||
            !check(esp_wifi_set_promiscuous_rx_cb(onFrame), "capture callback") ||
            !check(esp_wifi_set_promiscuous(true), "capture start")) return;
    }
    portENTER_CRITICAL(&observationMux);
    observation = Observation{};
    memcpy(selectedAp, ap.bssid, 6);
    observing = true;
    portEXIT_CRITICAL(&observationMux);
    const unsigned long started = millis();
    const auto status = WiFi.begin(savedSsid.c_str(), savedPassword.isEmpty() ? nullptr : savedPassword.c_str(),
                                   ap.channel, ap.bssid);
    // Equality only: never print the password, its length or a fingerprint.
    wifi_config_t config = {};
    if (check(esp_wifi_get_config(WIFI_IF_STA, &config), "station config readback")) {
        const size_t ssidLen = savedSsid.length(), passLen = savedPassword.length();
        const bool sameSsid = memcmp(config.sta.ssid, savedSsid.c_str(), ssidLen) == 0 &&
            (ssidLen == sizeof(config.sta.ssid) || config.sta.ssid[ssidLen] == 0);
        const bool samePassword = memcmp(config.sta.password, savedPassword.c_str(), passLen) == 0 &&
            (passLen == sizeof(config.sta.password) || config.sta.password[passLen] == 0);
        Serial.printf("[Diag] beginStatus=%d driverSsidMatchesNvs=%d driverPasswordMatchesNvs=%d\n",
                      int(status), sameSsid, samePassword);
    }
    memset(&config, 0, sizeof(config));
    uint32_t loggedDisconnects = 0;
    bool loggedAssociation = false;
    while (status != WL_CONNECT_FAILED && millis() - started < 25000) {
        const auto now = snapshot();
        if (now.disconnects != loggedDisconnects) {
            loggedDisconnects = now.disconnects;
            Serial.printf("[Diag] +%lums disconnects=%lu reason=%u (%s) rssi=%ddBm\n",
                          millis() - started, (unsigned long)now.disconnects, unsigned(now.driverReason),
                          WiFi.disconnectReasonName((wifi_err_reason_t)now.driverReason), int(now.rssi));
        }
        if (now.associated && !loggedAssociation) {
            loggedAssociation = true;
            Serial.printf("[Diag] +%lums associated\n", millis() - started);
        }
        if (WiFi.isConnected()) break;
        delay(5);
    }
    portENTER_CRITICAL(&observationMux);
    observing = false;
    portEXIT_CRITICAL(&observationMux);
    if (capture) check(esp_wifi_set_promiscuous(false), "capture stop");
    const auto result = snapshot();
    Serial.printf("[Diag] RESULT trial=%d associated=%d gotIp=%d connectedNow=%d elapsedMs=%lu\n",
                  trial, result.associated, result.gotIp, WiFi.isConnected(), millis() - started);
    if (WiFi.isConnected()) Serial.printf("[Diag] IP=%s gateway=%s (internet not tested)\n",
                                         WiFi.localIP().toString().c_str(), WiFi.gatewayIP().toString().c_str());
    if (capture) {
        Serial.printf("[Diag] RX beacons=%lu authReplies=%lu authAlgorithm=%u authSequence=%u authStatus=%u\n",
                      (unsigned long)result.beacons, (unsigned long)result.auth, result.authAlgorithm,
                      result.authSequence, result.authStatus);
        Serial.printf("[Diag] RX assocReplies=%lu assocStatus=%u deauth=%lu disassoc=%lu apReason=%u protected=%lu\n",
                      (unsigned long)result.assocReplies, result.assocStatus, (unsigned long)result.deauth,
                      (unsigned long)result.disassoc, result.apReason, (unsigned long)result.protectedFrames);
    }
}

void setup() {
    Serial.begin(115200);
    // Allow time to reopen a monitor after the uploader's automatic reset.
    delay(10000);
    Serial.printf("\n[Diag] TwinGlow Wi-Fi diagnostic; resetReason=%d chip=%s rev=%u Arduino=%s IDF=%s\n",
                  int(esp_reset_reason()), ESP.getChipModel(), unsigned(ESP.getChipRevision()),
                  ESP_ARDUINO_VERSION_STR, ESP.getSdkVersion());
    // LEDs retain their previous colour across MCU resets. Actually clear them
    // once, so this test removes their dynamic current load, not just rendering.
    Adafruit_NeoPixel pixels(DIAGNOSTIC_MATRIX_PIXELS, DIAGNOSTIC_MATRIX_PIN, NEO_GRB + NEO_KHZ800);
    pixels.begin(); pixels.clear(); pixels.show();
    Serial.println("[Diag] Matrix cleared; no cloud, BLE, buttons or sensor tasks");
    Preferences nvs;
    if (!nvs.begin("twinglow", true)) { Serial.println("[Diag] Cannot open TwinGlow NVS read-only"); return; }
    const String device = nvs.getString("device_id", "unknown");
    savedSsid = nvs.getString("wifi_ssid", "");
    savedPassword = nvs.getString("wifi_pass", "");
#ifdef TWINGLOW_EXTENDED_DIAGNOSTIC
    const uint8_t savedBrightness = nvs.getUChar("brightness", 128);
#endif
    nvs.end();
    Serial.printf("[Diag] Device=%s SSID=%s passwordPresent=%d passwordFormatValid=%d\n",
                  device.c_str(), savedSsid.c_str(), !savedPassword.isEmpty(), validPasswordShape(savedPassword));
    if (savedSsid.isEmpty() || savedSsid.length() > 32 || strlen(savedSsid.c_str()) != savedSsid.length() ||
        !validPasswordShape(savedPassword)) { Serial.println("[Diag] Invalid/missing saved Wi-Fi data; no changes made"); return; }
    WiFi.onEvent(onEvent);
    if (!startStation() || !check(esp_wifi_get_mac(WIFI_IF_STA, stationMac), "station MAC")) return;
    // The Arduino interface may not have processed STA_START yet; report the
    // checked driver's address rather than an early all-zero wrapper result.
    Serial.printf("[Diag] Station MAC=%02X:%02X:%02X:%02X:%02X:%02X\n", stationMac[0],
                  stationMac[1], stationMac[2], stationMac[3], stationMac[4], stationMac[5]);
    int8_t normalPower = 0;
    if (!check(esp_wifi_get_max_tx_power(&normalPower), "default TX power")) return;
    // Scan once before trials; no repeated scan alongside esp_wifi_connect().
    const int networks = WiFi.scanNetworks(false, true);
    AccessPoint candidates[4];
    int count = 0;
    for (int i = 0; i < networks; ++i) {
        if (WiFi.SSID(i) != savedSsid) continue;
        Serial.printf("[Diag] AP=%s channel=%ld RSSI=%ld authMode=%d\n", WiFi.BSSIDstr(i).c_str(),
                      long(WiFi.channel(i)), long(WiFi.RSSI(i)), int(WiFi.encryptionType(i)));
        if (count < 4) {
            memcpy(candidates[count].bssid, WiFi.BSSID(i), 6);
            candidates[count++].channel = WiFi.channel(i);
        }
    }
    WiFi.scanDelete();
    if (!count) { Serial.printf("[Diag] No matching AP found; scanResult=%d\n", networks); return; }
    Serial.printf("[Diag] Testing %d AP(s); lower TX power is an experiment, not a repair\n", count);
    int trial = 0;
    for (int i = 0; i < count; ++i) {
        runTrial(candidates[i], normalPower, false, ++trial);
        runTrial(candidates[i], normalPower, true, ++trial);
        runTrial(candidates[i], 34, false, ++trial); // 8.5 dBm API limit, see readback.
        runTrial(candidates[i], 34, true, ++trial);
    }
#ifdef TWINGLOW_EXTENDED_DIAGNOSTIC
    runExtendedTrial(pixels, savedBrightness);
#endif
    WiFi.mode(WIFI_OFF);
    Serial.println("[Diag] DONE; NVS preserved. Reinstall TwinGlow to restore normal playback.");
}
void loop() { delay(100); }
