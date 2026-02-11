#ifndef FIREBASE_CLIENT_WRAP_H
#define FIREBASE_CLIENT_WRAP_H

#include <FirebaseClient.h>
#include "FirebaseTypes.h"
#include "Config.h"
#include <Arduino.h>

/**
 * Firebase client wrapper
 * Handles initialization and authentication
 */
class FirebaseClientWrap {
public:
    FirebaseClientWrap();
    ~FirebaseClientWrap();
    
    bool begin();
    bool isInitialized() const { return initialized; }
    
    FirebaseApp* getApp() { return &app; }
    FirebaseApp& getAppRef() { return app; }
    
    // Get Firestore instance (returns nullptr if types not configured)
    void* getFirestore() { return firestore; }
    
    // Get RTDB instance (returns nullptr if types not configured)
    void* getRtdb() { return rtdb; }
    
    // Get Auth instance
    void* getAuth() { return auth; }
    
    // Get database secret and URL for RTDB
    const char* getDatabaseSecret() const { return FIREBASE_DATABASE_SECRET; }
    const char* getDatabaseUrl() const { return FIREBASE_DATABASE_URL; }
    
private:
    FirebaseApp app;
    void* firestore; // Firestore instance
    void* rtdb;      // RTDB instance
    void* auth;      // Auth instance
    
    bool initialized;
    
    bool initializeAuth();
    bool initializeFirestore();
    bool initializeRTDB();
};

#endif // FIREBASE_CLIENT_WRAP_H
