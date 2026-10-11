# Connectivity regression tests

Run from the repository root:

```sh
bash tools/native-connectivity/test.sh
bash tools/native-pairing/test.sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app TwinGlow
```

Requires a C++17 compiler with AddressSanitizer/UndefinedBehaviorSanitizer and
ArduinoJson in `~/Documents/Arduino/libraries/ArduinoJson/src` (or set
`ARDUINOJSON_ROOT`). The new suite exercises the production Wi-Fi manager and
matrix driver, and extracts the production cloud/FSM methods into controlled
test harnesses. No Firebase credentials or live cloud requests are needed.

Coverage: indefinite boot/runtime Wi-Fi retries, reconnect confirmation,
intentional BLE/reset paths, independent Firestore/RTDB health, auth/HTTP and
transport failures, stale confirmation and millis rollover, stuck-call ownership,
all five matrix orientations, raw-buffer restoration at low brightness,
disabled indicators during BLE and fully blank sleep, and transition-only refresh.

Hardware checks after installing the firmware:

1. Load an image/animation and a received override, disconnect the access point,
   and check that playback/buttons continue with one red top-right pixel. Leave
   disconnected past 10 retries and 12 minutes; the device must keep retrying.
2. Keep Wi-Fi associated but interrupt upstream access. Check orange on cloud
   request failure or after 60 seconds without a successful cloud request.
3. Restore access. Orange remains until both RTDB and Firestore are confirmed;
   then the original corner content reappears without restarting an animation.
4. Check blank sleep stays fully dark and dim sleep shows the indicator at the
   selected brightness. Hold ACTION for 10 seconds during a boot with invalid
   saved credentials; the next boot must enter normal BLE provisioning.

These native tests and compilation do not establish RF/hardware reliability.
Content remains in RAM; power loss or a manual reset clears it.
