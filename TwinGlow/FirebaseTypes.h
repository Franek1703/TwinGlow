/*
 * FirebaseClient Library Type Definitions (mobizt/FirebaseClient)
 *
 * Requires Config.h to be included first (defines ENABLE_DATABASE, ENABLE_FIRESTORE, ENABLE_USER_AUTH).
 * Library uses namespace firebase_ns.
 */

#ifndef FIREBASE_TYPES_H
#define FIREBASE_TYPES_H

#include "PairingConfig.h"
#include <FirebaseClient.h>

#if defined(ENABLE_DATABASE)
/* RealtimeDatabase is in global scope (database/RealtimeDatabase.h) */
typedef RealtimeDatabase FirebaseRTDBType;
#else
class FirebaseRTDBType;
#endif

#if defined(ENABLE_FIRESTORE)
/* Firestore::Documents is in namespace Firestore (firestore/Documents.h) */
typedef Firestore::Documents FirebaseFirestoreType;
#else
class FirebaseFirestoreType;
#endif

#if defined(ENABLE_USER_AUTH)
/* UserAuth refreshes an individually scoped Firebase ID token. */
typedef firebase_ns::UserAuth FirebaseAuthType;
#else
class FirebaseAuthType;
#endif

#endif // FIREBASE_TYPES_H
