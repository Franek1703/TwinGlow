#ifndef PAIRING_CONFIG_H
#define PAIRING_CONFIG_H
#include "Config.h"
// Applies to old private Config.h copies too. Never use a project-wide secret.
#undef ENABLE_LEGACY_TOKEN
#define ENABLE_USER_AUTH
#if __has_include("DeviceCredentials.h")
#include "DeviceCredentials.h"
#endif
#ifndef FIREBASE_DEVICE_EMAIL
#define FIREBASE_DEVICE_EMAIL ""
#define FIREBASE_DEVICE_PASSWORD ""
#endif
#define PAIR_POLL_MS 5000
#define PAIR_SEND_TTL_MS 60000
#define PAIR_EVENT_MAX_AGE_MS 86400000ULL
#define PAIR_MAX_JSON_BYTES 12288
#endif
