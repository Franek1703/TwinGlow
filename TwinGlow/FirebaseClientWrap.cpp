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
        Serial.println(F("[Firebase] Already initialized"));
        return true;
    }

    Serial.println(F("[Firebase] Initializing..."));

#if defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE)
    // Skip server cert verification so TLS connect succeeds (use setCACert in production)
    sslClient.setInsecure();
    Serial.println(F("[Firebase] setClient(sslClient)"));
    aClient.setClient(sslClient);
#endif

    Serial.println(F("[Firebase] initializeAuth()..."));
    if (!initializeAuth()) {
        Serial.println(F("[Firebase] Auth initialization failed"));
        return false;
    }
    Serial.println(F("[Firebase] Auth OK"));

    Serial.println(F("[Firebase] initializeFirestore()..."));
    if (!initializeFirestore()) {
        Serial.println(F("[Firebase] Firestore initialization failed"));
    } else {
        Serial.println(F("[Firebase] Firestore instance OK"));
    }

    Serial.println(F("[Firebase] initializeRTDB()..."));
    if (!initializeRTDB()) {
        Serial.println(F("[Firebase] RTDB initialization failed"));
    } else {
        Serial.println(F("[Firebase] RTDB instance OK"));
    }

#if defined(ENABLE_LEGACY_TOKEN) && (defined(ENABLE_DATABASE) || defined(ENABLE_FIRESTORE))
    if (auth != nullptr) {
        Serial.println(F("[Firebase] initializeApp(aClient, app, authData, 5000)..."));
        user_auth_data& authData = static_cast<FirebaseAuthType*>(auth)->get();
        initializeApp(aClient, app, authData, 5000UL);
        Serial.println(F("[Firebase] initializeApp done"));
    } else {
        Serial.println(F("[Firebase] auth is null, skip initializeApp"));
    }
#endif

    Serial.println(F("[Firebase] Binding RTDB/Firestore to app (getApp)..."));
#if defined(ENABLE_DATABASE)
    if (rtdb != nullptr) {
        app.getApp(*static_cast<FirebaseRTDBType*>(rtdb));
        Serial.println(F("[Firebase] app.getApp(rtdb) done"));
    }
#endif
#if defined(ENABLE_FIRESTORE)
    if (firestore != nullptr) {
        app.getApp(*static_cast<FirebaseFirestoreType*>(firestore));
        Serial.println(F("[Firebase] app.getApp(firestore) done"));
    }
#endif

    initialized = true;
    Serial.println(F("[Firebase] Initialized successfully"));
    return true;
}

bool FirebaseClientWrap::initializeAuth() {
#if defined(ENABLE_LEGACY_TOKEN)
    Serial.println(F("[Firebase] Creating LegacyToken auth..."));
    auth = new FirebaseAuthType(FIREBASE_DATABASE_SECRET);
    if (auth != nullptr) {
        Serial.println(F("[Firebase] LegacyToken created"));
        return true;
    }
    Serial.println(F("[Firebase] LegacyToken alloc failed"));
    return false;
#else
    Serial.println(F("[Firebase] ENABLE_LEGACY_TOKEN not defined"));
    return true;
#endif
}

bool FirebaseClientWrap::initializeFirestore() {
#if defined(ENABLE_FIRESTORE)
    Serial.println(F("[Firebase] Allocating Firestore instance..."));
    firestore = new FirebaseFirestoreType();
    if (firestore != nullptr) {
        Serial.println(F("[Firebase] Firestore instance created"));
        return true;
    }
    Serial.println(F("[Firebase] Firestore alloc failed"));
    return false;
#else
    return false;
#endif
}

bool FirebaseClientWrap::initializeRTDB() {
#if defined(ENABLE_DATABASE)
    Serial.print(F("[Firebase] Allocating RTDB instance url="));
    Serial.println(FIREBASE_DATABASE_URL);
    rtdb = new FirebaseRTDBType(FIREBASE_DATABASE_URL);
    if (rtdb != nullptr) {
        Serial.println(F("[Firebase] RTDB instance created"));
        return true;
    }
    Serial.println(F("[Firebase] RTDB alloc failed"));
    return false;
#else
    return false;
#endif
}
