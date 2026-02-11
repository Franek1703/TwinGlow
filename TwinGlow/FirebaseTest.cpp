#include "FirebaseTest.h"
#include "FirebaseClientWrap.h"
#include "Config.h"
#include "FirebaseTypes.h"
#include <Arduino.h>

#if !defined(ENABLE_DATABASE) && !defined(ENABLE_FIRESTORE)
void runFirebaseTest(FirebaseClientWrap&) {
    Serial.println(F("[FirebaseTest] ENABLE_DATABASE/ENABLE_FIRESTORE not defined, skip"));
}
#else

void runFirebaseTest(FirebaseClientWrap& wrap) {
    Serial.println(F("\n========== Firebase Test =========="));

#if defined(ENABLE_DATABASE)
    if (wrap.getRtdb() != nullptr && wrap.getAsyncClient() != nullptr) {
        auto* rtdb = static_cast<FirebaseRTDBType*>(wrap.getRtdb());
        AsyncClientClass* aClient = wrap.getAsyncClient();

        const char* testPath = "/test/twinglow_hello";
        const char* testValue = "world";

        bool setOk = rtdb->set(*aClient, testPath, testValue);
        if (!setOk && aClient->lastError().code() != 0) {
            Serial.print(F("[FirebaseTest] RTDB SET error: "));
            Serial.println(aClient->lastError().message());
        }

        String got = rtdb->get<String>(*aClient, testPath);
        if (got == testValue) {
            Serial.println(F("[FirebaseTest] RTDB test PASS"));
        } else {
            Serial.println(F("[FirebaseTest] RTDB test FAIL"));
            if (aClient->lastError().code() != 0) {
                Serial.print(F("[FirebaseTest] GET error: "));
                Serial.println(aClient->lastError().message());
            }
        }
    }
#endif

#if defined(ENABLE_FIRESTORE)
    if (wrap.getFirestore() != nullptr && wrap.getAsyncClient() != nullptr) {
        auto* documents = static_cast<FirebaseFirestoreType*>(wrap.getFirestore());
        AsyncClientClass* aClient = wrap.getAsyncClient();

        Firestore::Parent parent(FIREBASE_PROJECT_ID, "");
        DocumentMask mask;
        GetDocumentOptions options(mask);
        String documentPath = "test/twinglow_test_doc";

        (void)documents->get(*aClient, parent, documentPath, options);
        if (aClient->lastError().code() == 0) {
            Serial.println(F("[FirebaseTest] Firestore test OK"));
        } else {
            Serial.print(F("[FirebaseTest] Firestore error: "));
            Serial.println(aClient->lastError().message());
        }
    }
#endif

    Serial.println(F("========== Firebase Test End ==========\n"));
}

#endif // ENABLE_DATABASE || ENABLE_FIRESTORE
