#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
json_root="${ARDUINOJSON_ROOT:-$HOME/Documents/Arduino/libraries/ArduinoJson/src}"
output="${TMPDIR:-/tmp}/twinglow-native-pairing"
c++ -std=c++17 -fsanitize=address,undefined -g -Itools/native-pairing -ITwinGlow -I"$json_root" -include tools/native-pairing/Config.h tools/native-pairing/test.cpp TwinGlow/AssetCache.cpp TwinGlow/PairSnapshot.cpp TwinGlow/PairingController.cpp TwinGlow/RenderAsset.cpp TwinGlow/ScreenPlaylist.cpp TwinGlow/PlaylistUpdate.cpp -o "$output"
"$output"
