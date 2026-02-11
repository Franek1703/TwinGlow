#include "FirebaseClientWrap.h"

FirebaseClientWrap::FirebaseClientWrap()
    : firestore(nullptr), rtdb(nullptr), auth(nullptr), initialized(false) {
}

FirebaseClientWrap::~FirebaseClientWrap() {
#if defined(ENABLE_LEGACY_TOKEN)
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
        return true;
    }

#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
    sslClient.setInsecure();
    aClient.setClient(sslClient);
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
    }

#if defined(ENABLE_LEGACY_TOKEN) && (defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE))
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
    return true;
}

bool FirebaseClientWrap::initializeAuth() {
#if defined(ENABLE_LEGACY_TOKEN)
    auth = new FirebaseAuthType(FIREBASE_DATABASE_SECRET);
    if (auth != nullptr) {
        return true;
    }
    Serial.println(F("[Firebase] LegacyToken alloc failed"));
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
