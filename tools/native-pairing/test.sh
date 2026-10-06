#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
json_root="${ARDUINOJSON_ROOT:-$HOME/Documents/Arduino/libraries/ArduinoJson/src}"
output="${TMPDIR:-/tmp}/twinglow-native-pairing"
c++ -std=c++17 -fsanitize=address,undefined -g -Itools/native-pairing -ITwinGlow -I"$json_root" -include tools/native-pairing/Config.h tools/native-pairing/test.cpp TwinGlow/AssetCache.cpp TwinGlow/PairSnapshot.cpp TwinGlow/PairingController.cpp TwinGlow/RenderAsset.cpp TwinGlow/ScreenPlaylist.cpp TwinGlow/PlaylistUpdate.cpp -o "$output"
"$output"
task_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/twinglow-firestore-test.XXXXXX")"
trap 'rm -rf "$task_test_dir"' EXIT
python3 - "$task_test_dir/firestore-get-asset.inc" <<'PY'
import sys
from pathlib import Path
source = Path('TwinGlow/FirestoreRepo.cpp').read_text()
sections = []
for start, end in [
    ('static bool firestoreFieldToInt(', 'bool FirestoreRepo::getDeviceDoc('),
    ('static void appendFirestorePixelArray(', 'bool FirestoreRepo::getAsset(const String& assetId'),
    ('bool FirestoreRepo::getAsset(const String& assetId', 'bool FirestoreRepo::checkConfigVersion(DeviceDoc& out) {\n    return getDeviceDoc(out);'),
]:
    begin = source.index(start)
    sections.append(source[begin:source.index(end, begin)])
Path(sys.argv[1]).write_text('\n'.join(sections))
PY
c++ -std=c++17 -fsanitize=address,undefined -g -Itools/native-pairing -ITwinGlow -I"$json_root" -I"$task_test_dir" -include tools/native-pairing/Config.h tools/native-pairing/firestore-test.cpp TwinGlow/AssetCache.cpp -o "$task_test_dir/test"
"$task_test_dir/test"
