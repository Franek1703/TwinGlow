/*
 * FirebaseClient Library Type Definitions
 * 
 * INSTRUCTIONS:
 * 1. Open your FirebaseClient.h library header file
 * 2. Find the class names for:
 *    - Firestore operations class
 *    - Realtime Database operations class  
 *    - Authentication class
 * 3. Update the typedefs below to match your library version
 * 4. Common class names to try:
 *    - Firestore / FirebaseFirestore / FirebaseApp::Firestore
 *    - RealtimeDatabase / RTDB / FirebaseRTDB / FirebaseApp::RTDB
 *    - FirebaseAuth / Auth
 */

#ifndef FIREBASE_TYPES_H
#define FIREBASE_TYPES_H

#include <FirebaseClient.h>

// TODO: Update these to match your FirebaseClient library class names
// Check FirebaseClient.h in your Arduino libraries folder

// Uncomment and adjust ONE of these based on your library:
// typedef Firestore FirebaseFirestoreType;
// typedef FirebaseFirestore FirebaseFirestoreType;
// typedef FirebaseApp::Firestore FirebaseFirestoreType;

// Uncomment and adjust ONE of these:
// typedef RealtimeDatabase FirebaseRTDBType;
// typedef RTDB FirebaseRTDBType;
// typedef FirebaseRTDB FirebaseRTDBType;
// typedef FirebaseApp::RTDB FirebaseRTDBType;

// Uncomment and adjust ONE of these:
// typedef FirebaseAuth FirebaseAuthType;
// typedef Auth FirebaseAuthType;

// For now, use forward declarations until you find the correct names
class FirebaseFirestoreType;
class FirebaseRTDBType;
class FirebaseAuthType;

#endif // FIREBASE_TYPES_H
