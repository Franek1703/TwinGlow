#pragma once
#include "FirestoreModels.h"
#include <ArduinoJson.h>

// Decode the same Firestore v2 document used by Flutter. Local order/settings
// stay on the reference and are never overwritten by shared configuration.
inline bool resolveSharedFields(JsonObjectConst fields, ScreenConfig& screen) {
    if (fields["schemaVersion"]["integerValue"].as<int>() != 2 || !fields["state"]["stringValue"].is<const char*>()) return false;
    screen.type = fields["type"]["stringValue"].as<String>();
    screen.type.toUpperCase();
    if (screen.type != "IMAGE" && screen.type != "ANIMATION") return false;
    screen.defaultAssetId = fields["defaultAssetId"]["stringValue"].as<String>();
    screen.assetId = screen.defaultAssetId;
    screen.availableAssetIds.clear();
    auto values=fields["availableAssetIds"]["arrayValue"]["values"].as<JsonArrayConst>();
    if (values.size()==0 || values.size()>10) return false;
    bool found=false;
    for (auto value:values) {
        if (!value["stringValue"].is<const char*>()) return false;
        String id=value["stringValue"].as<String>();
        if (id.isEmpty() || id.length()>95) return false;
        for(const auto& prior:screen.availableAssetIds)if(prior==id)return false;
        if(id==screen.defaultAssetId)found=true;
        screen.availableAssetIds.push_back(std::move(id));
    }
    if(!found)return false;
    screen.currentAssetIndex=0;
    screen.allowManualSwitch=fields["allowManualSwitch"]["booleanValue"].as<bool>();
    screen.isShared=true;
    return true;
}
