#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
task_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/twinglow-connectivity-test.XXXXXX")"
trap 'rm -rf "$task_test_dir"' EXIT
json_root="${ARDUINOJSON_ROOT:-$HOME/Documents/Arduino/libraries/ArduinoJson/src}"
flags=(-std=c++17 -fsanitize=address,undefined -g -Itools/native-connectivity -Itools/native-pairing -ITwinGlow -I"$json_root" -I"$task_test_dir" -include tools/native-connectivity/Config.h)
c++ "${flags[@]}" tools/native-connectivity/wifi-test.cpp TwinGlow/WifiManager.cpp -o "$task_test_dir/wifi"
"$task_test_dir/wifi"
c++ "${flags[@]}" tools/native-connectivity/wifi-recovery-test.cpp TwinGlow/WifiManager.cpp -o "$task_test_dir/wifi-recovery"
"$task_test_dir/wifi-recovery"
c++ "${flags[@]}" -DWIFI_MAX_TX_POWER_QUARTER_DBM=28 tools/native-connectivity/wifi-power-test.cpp TwinGlow/WifiManager.cpp -o "$task_test_dir/wifi-power"
"$task_test_dir/wifi-power"
for orientation in 0 1 2 3 4; do
    c++ "${flags[@]}" -DPANEL_ORIENTATION="$orientation" tools/native-connectivity/matrix-test.cpp TwinGlow/MatrixDriver.cpp -o "$task_test_dir/matrix"
    "$task_test_dir/matrix"
done
python3 - "$task_test_dir/cloud-runtime.inc" <<'PY'
import sys
from pathlib import Path
source = Path('TwinGlow/CloudWorker.cpp').read_text()
sections = []
for start, end in [
    ('bool CloudWorker::isBusy()', 'bool CloudWorker::requestPresence('),
    ('void CloudWorker::serviceWatchdog()', 'bool CloudWorker::consumeWifiCycleRequest()'),
    ('bool CloudWorker::popResult(', 'void CloudWorker::taskEntry('),
    ('void CloudWorker::execute(', 'void CloudWorker::recordOutcome('),
]:
    begin = source.index(start)
    sections.append(source[begin:source.index(end, begin)])
Path(sys.argv[1]).write_text('\n'.join(sections))
PY
c++ "${flags[@]}" tools/native-connectivity/cloud-test.cpp -o "$task_test_dir/cloud"
"$task_test_dir/cloud"
python3 - "$task_test_dir/main-runtime.inc" <<'PY'
import sys
from pathlib import Path
source = Path('TwinGlow/TwinGlow.ino').read_text()
sections = []
for start, end in [
    ('void handleBootFactoryReset() {', 'void handleProvisioningBle() {'),
    ('void handleWifiConnecting() {', '// Applies a timezone'),
]:
    begin = source.index(start)
    sections.append(source[begin:source.index(end, begin)])
Path(sys.argv[1]).write_text('\n'.join(sections))
PY
c++ "${flags[@]}" tools/native-connectivity/runtime-test.cpp TwinGlow/WifiManager.cpp -o "$task_test_dir/runtime"
"$task_test_dir/runtime"
