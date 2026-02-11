/*
 * FirebaseClient Library Type Definitions (mobizt/FirebaseClient)
 *
 * Requires Config.h to be included first (defines ENABLE_DATABASE, ENABLE_FIRESTORE, ENABLE_LEGACY_TOKEN).
 * Library uses namespace firebase_ns.
 */

#ifndef FIREBASE_TYPES_H
#define FIREBASE_TYPES_H

#include "Config.h"
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

#if defined(ENABLE_LEGACY_TOKEN)
/* LegacyToken is in namespace firebase_ns (core/Auth/Token/LegacyToken.h) */
typedef firebase_ns::LegacyToken FirebaseAuthType;
#else
class FirebaseAuthType;
#endif

#endif // FIREBASE_TYPES_H
