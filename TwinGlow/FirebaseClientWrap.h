#ifndef FIREBASE_CLIENT_WRAP_H
#define FIREBASE_CLIENT_WRAP_H

#include "Config.h"
#include <FirebaseClient.h>
#include "FirebaseTypes.h"
#include <Arduino.h>

#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
#include <WiFiClientSecure.h>
#endif

/**
 * Firebase client wrapper (mobizt FirebaseClient)
 * Handles auth (LegacyToken), RTDB, Firestore, and AsyncClient for ESP32.
 */
class FirebaseClientWrap {
public:
    FirebaseClientWrap();
    ~FirebaseClientWrap();

    bool begin();
    bool isInitialized() const { return initialized; }

    FirebaseApp* getApp() { return &app; }
    FirebaseApp& getAppRef() { return app; }

    // Get Firestore instance (returns nullptr if not configured)
    void* getFirestore() { return firestore; }

    // Get RTDB instance (returns nullptr if not configured)
    void* getRtdb() { return rtdb; }

    // Get Auth instance
    void* getAuth() { return auth; }

#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
    // AsyncClient for RTDB/Firestore operations (required by FirebaseClient API)
    AsyncClientClass* getAsyncClient() { return &aClient; }
#endif

    const char* getDatabaseSecret() const { return FIREBASE_DATABASE_SECRET; }
    const char* getDatabaseUrl() const { return FIREBASE_DATABASE_URL; }

private:
    FirebaseApp app;
    void* firestore;
    void* rtdb;
    void* auth;
    bool initialized;

#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
    WiFiClientSecure sslClient;
    AsyncClientClass aClient;
#endif

    bool initializeAuth();
    bool initializeFirestore();
    bool initializeRTDB();
};

#endif // FIREBASE_CLIENT_WRAP_H
