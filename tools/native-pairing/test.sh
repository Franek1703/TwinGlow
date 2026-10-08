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
python3 - "$task_test_dir/firebase-reset-transport.inc" <<'PY'
import sys
from pathlib import Path
source = Path('TwinGlow/FirebaseClientWrap.cpp').read_text()
start = source.index('void FirebaseClientWrap::resetTransport()')
end = source.index('int FirebaseClientWrap::getLastErrorCode()', start)
Path(sys.argv[1]).write_text(source[start:end])
PY
c++ -std=c++17 -fsanitize=address,undefined -g -Itools/native-pairing -I"$task_test_dir" tools/native-pairing/transport-test.cpp -o "$task_test_dir/transport"
"$task_test_dir/transport"
python3 - "$task_test_dir" <<'PY'
import sys
from pathlib import Path
output = Path(sys.argv[1])
source = Path('TwinGlow/TwinGlow.ino').read_text()
start = source.index('void applyDeviceSettings(const DeviceDoc& doc) {')
end = source.index('\nvoid handleTimeSync()', start)
(output / 'sleep-runtime.inc').write_text(source[start:end])
source = Path('TwinGlow/ButtonActions.cpp').read_text()
start = source.index('void ButtonActions::handleBrightnessChange(bool increase) {')
end = source.index('\nvoid ButtonActions::handleSendToPair()', start)
(output / 'brightness-button.inc').write_text(source[start:end])
PY
c++ -std=c++17 -fsanitize=address,undefined -g -Itools/native-pairing -ITwinGlow -I"$task_test_dir" tools/native-pairing/sleep-test.cpp TwinGlow/SleepSchedule.cpp -o "$task_test_dir/sleep"
"$task_test_dir/sleep"
