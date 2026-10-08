#include "FirebaseClientWrap.h"
#include <WiFi.h>
#include "FirebaseRootCA.h"

FirebaseClientWrap::FirebaseClientWrap()
    : firestore(nullptr), rtdb(nullptr), auth(nullptr), initialized(false) {
}

FirebaseClientWrap::~FirebaseClientWrap() {
#if defined(ENABLE_USER_AUTH)
    if (auth != nullptr) {
        delete static_cast<FirebaseAuthType*>(auth);
        auth = nullptr;
    }
#endif
#if defined(ENABLE_DATABASE)
    if (rtdb != nullptr) {
        delete static_cast<FirebaseRTDBType*>(rtdb);
        rtdb = nullptr;
    }
#endif
#if defined(ENABLE_FIRESTORE)
    if (firestore != nullptr) {
        delete static_cast<FirebaseFirestoreType*>(firestore);
        firestore = nullptr;
    }
#endif
}

bool FirebaseClientWrap::begin() {
    if (initialized) {
        app.loop();
        return app.ready();
    }

#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
    configureTransport();
#endif

    if (!initializeAuth()) {
        Serial.println(F("[Firebase] Auth initialization failed"));
        return false;
    }

    if (!initializeFirestore()) {
        Serial.println(F("[Firebase] Firestore initialization failed"));
    }

    if (!initializeRTDB()) {
        Serial.println(F("[Firebase] RTDB initialization failed"));
        // Continue anyway - Firestore might still work
    } else {
        Serial.println(F("[Firebase] RTDB initialized successfully"));
    }

#if defined(ENABLE_USER_AUTH) && (defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE))
    if (auth != nullptr) {
        user_auth_data& authData = static_cast<FirebaseAuthType*>(auth)->get();
        initializeApp(aClient, app, authData, 5000UL);
    }
#endif

#if defined(ENABLE_DATABASE)
    if (rtdb != nullptr) {
        app.getApp(*static_cast<FirebaseRTDBType*>(rtdb));
    }
#endif
#if defined(ENABLE_FIRESTORE)
    if (firestore != nullptr) {
        app.getApp(*static_cast<FirebaseFirestoreType*>(firestore));
    }
#endif

    initialized = true;
    Serial.println(F("[Firebase] Initialized successfully"));
    return app.ready();
}

void FirebaseClientWrap::configureTransport() {
#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
    // BearSSL with explicitly sized buffers, in place of mbedTLS. mbedTLS
    // sizes its receive buffer from the TLS maximum of 16KB and held roughly
    // 36KB in total, which did not merely cost free heap - it owned the
    // largest contiguous block. Releasing the session moved largestBlock from
    // 9,716 to 34,804 bytes, and every asset fetch ran in what was left of it,
    // so FirebaseClient's response String - which it grows in 2KB steps with
    // no reservation - stopped growing partway and handed the parser truncated
    // JSON. That is the IncompleteInput/InvalidInput failures, and it is why
    // the same document arrived at three different lengths.
    //
    // RX has to hold one whole TLS record, so it is the size to raise first if
    // handshakes start failing against Google's frontend.
    sslClient.setClient(&basicClient);
    sslClient.setCACert(TWINGLOW_ROOT_CA);
    sslClient.setBufferSizes(FIREBASE_TLS_RX_BUFFER_BYTES, FIREBASE_TLS_TX_BUFFER_BYTES);
    // One knob here where WiFiClientSecure had a separate connect timeout;
    // the sync I/O budget is the sensible value for both.
    sslClient.setTimeout(FIREBASE_SYNC_IO_TIMEOUT_SEC);
    sslClient.setHandshakeTimeout(FIREBASE_TLS_HANDSHAKE_TIMEOUT_SEC);
    aClient.setClient(sslClient);
    aClient.setSyncSendTimeout(FIREBASE_SYNC_IO_TIMEOUT_SEC);
    aClient.setSyncReadTimeout(FIREBASE_SYNC_IO_TIMEOUT_SEC);
#endif
}

void FirebaseClientWrap::resetTransport() {
#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
    // ESP_SSLClient::stop() returns early when a failed handshake has cleared
    // its secure flag, leaving the underlying socket open. When still secure,
    // stop() may flush the broken session. Close TCP first in both cases so
    // recovery cannot reuse or wait on that half-spoken connection.
    basicClient.stop();
    aClient.stopAsync(true);
    sslClient.stop();
    configureTransport();
    Serial.println(F("[Firebase] TCP/TLS transport reset"));
#endif
}

int FirebaseClientWrap::getLastErrorCode() const {
#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
    return aClient.lastError().code();
#else
    return 0;
#endif
}

void FirebaseClientWrap::logTransportDiagnostics(const char* context) {
#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
    char tlsMessage[128] = {0};
    // ESP_SSLClient 3.1.3 leaves its engine alias dangling after freeing a
    // failed session. Its error accessor dereferences that alias unconditionally.
    int tlsCode = sslClient.isSecure()
        ? sslClient.getLastSSLError(tlsMessage, sizeof(tlsMessage)) : 0;

    Serial.print(F("[Firebase] Transport diagnostics ("));
    Serial.print(context != nullptr ? context : "unknown");
    Serial.print(F("): wifiStatus="));
    Serial.print((int)WiFi.status());
    Serial.print(F(" rssi="));
    Serial.print(WiFi.RSSI());
    Serial.print(F(" ip="));
    Serial.print(WiFi.localIP());
    Serial.print(F(" gateway="));
    Serial.print(WiFi.gatewayIP());
    Serial.print(F(" dns="));
    Serial.print(WiFi.dnsIP());
    Serial.print(F(" heap=")); Serial.print(ESP.getFreeHeap());
    Serial.print(F(" largestBlock=")); Serial.print(ESP.getMaxAllocHeap());
    Serial.print(F(" tlsCode="));
    Serial.print(tlsCode);
    Serial.print(F(" tlsMsg="));
    Serial.println(tlsMessage[0] != '\0' ? tlsMessage : "(none)");
#else
    (void)context;
#endif
}

bool FirebaseClientWrap::initializeAuth() {
#if defined(ENABLE_USER_AUTH)
    if(String(FIREBASE_DEVICE_EMAIL).isEmpty() || String(FIREBASE_DEVICE_PASSWORD).isEmpty()) {
        Serial.println(F("[Firebase] Device not enrolled: install DeviceCredentials.h"));return false;
    }
    auth = new FirebaseAuthType(FIREBASE_API_KEY,FIREBASE_DEVICE_EMAIL,FIREBASE_DEVICE_PASSWORD);
    if (auth != nullptr) {
        return true;
    }
    Serial.println(F("[Firebase] UserAuth alloc failed"));
    return false;
#else
    return true;
#endif
}

bool FirebaseClientWrap::initializeFirestore() {
#if defined(ENABLE_FIRESTORE)
    firestore = new FirebaseFirestoreType();
    if (firestore != nullptr) {
        return true;
    }
    return false;
#else
    return false;
#endif
}

bool FirebaseClientWrap::initializeRTDB() {
#if defined(ENABLE_DATABASE)
    rtdb = new FirebaseRTDBType(FIREBASE_DATABASE_URL);
    if (rtdb != nullptr) {
        return true;
    }
    return false;
#else
    return false;
#endif
}
