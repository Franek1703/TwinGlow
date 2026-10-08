#pragma once

#include <ArduinoJson.h>

// An absent/null token marks the last page. as<String>() serializes JSON null
// to the literal "null", which would incorrectly request another page.
inline bool readFirestorePageToken(JsonVariantConst value, String& token) {
    if (value.isNull()) {
        token = "";
        return true;
    }
    if (!value.is<const char*>()) return false;
    token = value.as<const char*>();
    return true;
}
