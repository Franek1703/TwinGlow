#ifndef FIREBASE_TEST_H
#define FIREBASE_TEST_H

class FirebaseClientWrap;

/**
 * One-shot test: RTDB set/get and Firestore get using FirebaseClientWrap.
 * Call once after Firebase is connected. Prints results to Serial.
 */
void runFirebaseTest(FirebaseClientWrap& wrap);

#endif // FIREBASE_TEST_H
