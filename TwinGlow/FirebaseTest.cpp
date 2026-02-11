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

        Serial.println(F("[FirebaseTest] RTDB SET..."));
        Serial.print(F("[FirebaseTest]   path=\""));
        Serial.print(testPath);
        Serial.print(F("\" value=\""));
        Serial.print(testValue);
        Serial.println(F("\""));
        bool setOk = rtdb->set(*aClient, testPath, testValue);
        int setErr = aClient->lastError().code();
        if (setOk) {
            Serial.println(F("[FirebaseTest] RTDB SET OK"));
        } else {
            Serial.println(F("[FirebaseTest] RTDB SET FAILED"));
        }
        Serial.print(F("[FirebaseTest]   SET lastError code="));
        Serial.print(setErr);
        if (setErr != 0) {
            Serial.print(F(" msg=\""));
            Serial.print(aClient->lastError().message());
            Serial.print(F("\""));
        }
        Serial.println();

        Serial.println(F("[FirebaseTest] RTDB GET..."));
        Serial.print(F("[FirebaseTest]   path=\""));
        Serial.println(testPath);
        String got = rtdb->get<String>(*aClient, testPath);
        int getErr = aClient->lastError().code();
        Serial.print(F("[FirebaseTest] RTDB GET result: \""));
        Serial.print(got);
        Serial.println(F("\""));
        Serial.print(F("[FirebaseTest]   GET result length="));
        Serial.print(got.length());
        Serial.print(F(" lastError code="));
        Serial.print(getErr);
        if (getErr != 0) {
            Serial.print(F(" msg=\""));
            Serial.print(aClient->lastError().message());
            Serial.print(F("\""));
        }
        Serial.println();
        if (got == testValue) {
            Serial.println(F("[FirebaseTest] RTDB test PASS"));
        } else {
            Serial.println(F("[FirebaseTest] RTDB test FAIL (value mismatch)"));
        }
    } else {
        Serial.println(F("[FirebaseTest] RTDB or AsyncClient null, skip RTDB test"));
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

        Serial.println(F("[FirebaseTest] Firestore GET..."));
        Serial.print(F("[FirebaseTest]   documentPath=\""));
        Serial.print(documentPath);
        Serial.println(F("\""));
        String response = documents->get(*aClient, parent, documentPath, options);
        int fsErr = aClient->lastError().code();
        Serial.print(F("[FirebaseTest] Firestore GET response length: "));
        Serial.println(response.length());
        if (response.length() > 0 && response.length() < 200) {
            Serial.print(F("[FirebaseTest] Body: "));
            Serial.println(response);
        } else if (response.length() >= 200) {
            Serial.print(F("[FirebaseTest] Body (first 200 chars): "));
            Serial.println(response.substring(0, 200));
        }
        Serial.print(F("[FirebaseTest]   Firestore lastError code="));
        Serial.print(fsErr);
        if (fsErr != 0) {
            Serial.print(F(" msg=\""));
            Serial.print(aClient->lastError().message());
            Serial.print(F("\""));
        }
        Serial.println();
        if (fsErr == 0) {
            Serial.println(F("[FirebaseTest] Firestore test done (doc may not exist yet)"));
        }
    } else {
        Serial.println(F("[FirebaseTest] Firestore or AsyncClient null, skip Firestore test"));
    }
#endif

    Serial.println(F("========== Firebase Test End ==========\n"));
}

#endif // ENABLE_DATABASE || ENABLE_FIRESTORE
