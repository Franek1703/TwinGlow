# Investigating repeated AUTH_EXPIRE

The logs from `tg_f4ec6bb0ef83` show failures before association/IP, on
`5C:7B:5C:21:C3:5D`, with RSSI between -54 and -66 dBm and stable available
heap. Both b/g/n and b/g modulation fail. This rules out a successful recovery
by the modulation workaround; it does not identify the underlying cause.
Firebase has not started at this stage. The application's Wi-Fi credentials
come from `twinglow/wifi_ssid` and `twinglow/wifi_pass` in NVS, independently
of `DeviceCredentials.h`.

Espressif documents [AUTH_EXPIRE](https://docs.espressif.com/projects/esp-idf/en/v5.5.4/esp32/api-guides/wifi.html#wi-fi-reason-code)
as an authentication timeout **or** a reason received from the AP. Signal
strength measures reception from the AP; it does not establish that the AP
receives the ESP32. A wrong password is possible, but reason 2 alone does not
prove it. The older observation of GROUP_KEY_UPDATE_TIMEOUT followed by
AUTH_EXPIRE is recorded in `docs/pairing_implementation.md`.

## Standalone diagnostic

`WifiDiagnostic` reads the existing Wi-Fi credentials **read-only**, uses RAM
for the driver's configuration, and runs without the TwinGlow application,
Firebase, BLE, button or sensor tasks. It clears the LEDs once (default GPIO 2,
256 GRB LEDs), then leaves them dark. Adjust `DIAGNOSTIC_MATRIX_PIN` and
`DIAGNOSTIC_MATRIX_PIXELS` if wiring differs. Attached peripherals and their
electrical effects remain; this does not physically disconnect the matrix.

It reports the reset reason, SDK version, station MAC, matching APs' BSSID,
channel and auth mode, and whether the driver received the same credentials
as NVS. Passwords, their length and fingerprints are never printed. The
format check can detect missing/malformed data, not whether the password
actually matches the router.

Common `authMode` values in this SDK: 0 open, 2 WPA, 3 WPA2, 4 WPA/WPA2,
6 WPA3 and 7 WPA2/WPA3. Raw authentication reply `authAlgorithm` values
include 0 Open System and 3 SAE. Status/reason fields report the last captured
frame of each kind; earlier replies may have differed.

For up to four matching APs, each pinned BSSID/channel is tested with:

1. Normal TX limit, no packet observer.
2. Normal TX limit, management-frame observer.
3. Lower TX limit (API value 34, nominal 8.5 dBm), no observer.
4. Lower TX limit, observer.

Each trial has a fresh radio session and at most 25 seconds. The actual power
limit is read back. Lower power is a controlled experiment, not an automatic
production fix. An observer can affect timing, so compare its result with the
plain trial. Only authentication/association and deauthentication/disassociation
metadata for this station/AP are inspected, plus beacon counts for the selected
AP. Protected frame bodies are never parsed. Callbacks copy fixed counters;
printing happens outside the Wi-Fi task. A successful trial establishes local
Wi-Fi/IP connectivity, not internet access.

## Run on the affected board

Stop the existing monitor before upload. This temporarily replaces the normal
application. Use the **same `huge_app` partition scheme** as TwinGlow, without
erasing flash; the diagnostic does not clear or rewrite TwinGlow NVS. Assets
in the running application's RAM are lost on reboot. No upload is performed
by compilation or by `test.sh`.

```sh
bash tools/wifi-diagnostic/test.sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app --build-path /tmp/twinglow-wifi-diagnostic-build tools/wifi-diagnostic/WifiDiagnostic
arduino-cli upload --fqbn esp32:esp32:esp32:PartitionScheme=huge_app,UploadSpeed=115200 --port /dev/cu.usbserial-310 --input-dir /tmp/twinglow-wifi-diagnostic-build tools/wifi-diagnostic/WifiDiagnostic
arduino-cli monitor --port /dev/cu.usbserial-310 --config baudrate=115200,dtr=off,rts=off --timestamp
```

Press EN/reset **once after opening the monitor** to capture setup from the
start if setup was missed. The sketch initially waits 10 seconds to let the
monitor reconnect. Four trials for one AP take at most about two minutes. Capture through
`[Diag] DONE`. Afterwards compile/upload `TwinGlow` again with the same
partition scheme and the affected device's existing private credentials.

DTR/RTS affect [reset and boot pins](https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/boot-mode-selection.html#automatic-bootloader).
Disabling them makes this measurement less dependent on monitor reconnections.
The provided log shows consecutive attempts 2–14, so it does **not** demonstrate
a reset loop or establish DTR/RTS as the cause of AUTH_EXPIRE.

## Interpret the comparison

| Observation | What it establishes / next check |
| --- | --- |
| Plain normal-power trial obtains IP | The saved Wi-Fi data and board can connect with this SDK and reduced application load. Investigate application activity and LED/power load; success alone does not distinguish them. |
| Normal power fails, lower power repeatedly works | TX-power-dependent behavior. Check power supply, wiring and RF hardware; repeat to exclude intermittent AP behavior before changing production power. |
| Driver credential equality fails | A credential transfer/configuration problem, rather than a Firebase account problem. |
| Auth reply captured with nonzero status | The AP sent that authentication status. Interpret with its algorithm/sequence and router logs, particularly for WPA3 SAE; status and disconnect reason are different fields. |
| Deauth/disassoc captured with reason 2 | A frame from the selected AP address explicitly told this station that authentication expired. Check AP policy/logs. This alone does not identify why it did so. |
| Beacons received, no auth replies captured | The observer heard AP beacons but no authentication reply during the trial. Check ESP32 TX/power, AP filtering and interference. An absent captured packet does not prove the AP never transmitted one. |
| Same failure in the standalone test | Rendering/cloud logic is absent and cannot explain that particular trial. Repeat with the matrix electrically disconnected, a known good power supply and a 2.4 GHz hotspot to distinguish this router from a board/SDK problem. |

## Extended comparison

Compile with `TWINGLOW_EXTENDED_DIAGNOSTIC` and an include path for the public
`TwinGlow/FirebaseRootCA.h` to add a longer test (about ten minutes total):

```sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app --build-property "compiler.cpp.extra_flags=-DTWINGLOW_EXTENDED_DIAGNOSTIC -I\"$PWD/TwinGlow\"" --build-path /tmp/twinglow-wifi-extended-build tools/wifi-diagnostic/WifiDiagnostic
```

After the four original trials, this connects without pinning BSSID/channel
or changing the default TX limit, with the LEDs displaying the same capped
grey PWM as the empty-playlist status, at the brightness saved in NVS. It
does not create the Firebase application or credential/token objects.

After NTP synchronization, it reads and discards the public Firestore API
discovery schema over certificate-verified TLS using RX buffers of 4096 and
16384 bytes. No authentication is sent. It reports MFLN negotiation and received
byte counts/status lines, rather than printing HTTP bodies. Each response has
a 30-second overall budget and five-second idle budget. The SSL SDK's unsafe
error accessor is not used on a failed/freed session. This tests record-size
compatibility; a byte count alone does not validate a complete HTTP response.

It then holds Wi-Fi for eight minutes, with DNS and a bounded plain TCP connection
to the public Firestore endpoint every 20 seconds. The DNS API has the Arduino
core's own timeout; each TCP connection has a two-second timeout and is closed
immediately. This comparison recreates LED load and ordinary AP selection, but
does not reproduce the full application's heap pressure or TLS request mix.

## Physical result, 2026-10-12

The user authorized uploading the diagnostic and restoring TwinGlow. NVS
identified the attached board as `tg_f4ec6bb0ef83`. The user reported no router,
power, wiring or location changes since the failing logs. The test found one
matching AP, `5C:7B:5C:21:C3:5D`, channel 1, authMode 4 (WPA/WPA2), RSSI -51 dBm.
Driver SSID/password equality with NVS passed in every trial.

| Trial | Observer | Actual TX limit readback | Associated and got IP | Elapsed |
| --- | --- | --- | --- | --- |
| 1 | Off | 18 dBm | Yes | 3497 ms |
| 2 | On | 18 dBm | Yes | 3481 ms |
| 3 | Off | 7 dBm | Yes | 4007 ms |
| 4 | On | 7 dBm | Yes | 3532 ms |

Both observed trials captured Open System authentication replies (algorithm 0,
sequence 2, status 0) and association replies with status 0; no deauthentication
or disassociation was captured. All trials obtained `192.168.0.106` with gateway
`192.168.0.1`. This confirms usable saved credentials and working local Wi-Fi
in these conditions; lower TX power was unnecessary. It does not establish
internet access or long-term reliability. The low-power API value 34 read back
as 28 quarter-dBm units (7 dBm), so conclusions use the measured value.

Differences from the full firmware include a single AP scan before connecting,
pinned BSSID/channel, dark LEDs and absence of application tasks. These vary
together and do not identify which, if any, caused the original failure. The
initial Arduino MAC wrapper printed zeros before processing STA_START; packet
filtering used the checked `esp_wifi_get_mac()` address. The diagnostic now logs
that address directly. The flasher identified MAC `88:57:21:b3:09:fc`.

Uploading at 921600 baud initially failed after starting the stub, before flash
writes. Uploading at 115200 baud succeeded with verified hashes. This identifies
a programming-speed issue, not a demonstrated explanation for AUTH_EXPIRE.

After restoring the full TwinGlow image with verified flash hashes, the device
reached RUNNING, read remote configuration 91, downloaded two assets and sent a
successful heartbeat. The observed sequence was:

1. 12:25:07: asset TCP receive timeout (-3).
2. 12:25:25, 12:26:19, 12:27:29 and 12:30:00: repeated cloud transport failures;
   diagnostics still reported association, IP and RSSI around -49 to -52 dBm.
   The worker explicitly deferred Wi-Fi cycling each time.
3. 12:31:02: reason 7 (`NOT_ASSOCED`), followed by repeated `AUTH_EXPIRE` retries.
4. 12:34:05: the first worker request to cycle Wi-Fi, **after** the link was lost.

Thus cloud-request-driven radio cycling did not initiate this measured outage.
The short diagnostic successes did not establish long-term radio reliability.
Espressif's reason-code table describes reason 7 as received from the AP for a
station. This identifies an association rejection, not its ultimate cause.
The baseline capture is in `.private/diagnostics/twinglow-baseline-20261012.log`.

In the extended diagnostic, the first three trials failed (normal-limit trials
1/2 and lower-limit trial 3). The observed normal-limit trial heard 221 beacons
and no authentication replies; no AP deauthentication frame was captured.
Trial 4 then connected at the lower limit. These changing outcomes do not
isolate TX power as the cause: normal-limit trials had passed in the first run,
and a lower-limit trial also failed in the second.

The subsequent unpinned connection with grey LEDs succeeded. Public TLS reads
returned HTTP 200 and approximately 323697/323696 bytes with 4096/16384-byte
RX buffers respectively, both reporting no MFLN negotiation. This did not
reproduce a receive-buffer failure on that endpoint; it does not rule one out
for the application's authenticated asset endpoint or lower available heap.
The eight-minute hold completed at 12:55:24 with no disconnects and all DNS/TCP
probes succeeding. Available heap was about 195 KB with a 110580-byte largest
block, substantially more than the full application. The limit after restarting
the radio for this hold was not explicitly read back in that diagnostic image;
do not assume that it establishes long-term reliability at 18 dBm.
Its capture is `.private/diagnostics/wifi-extended-20261012.log`.

## Full application with an explicit TX limit

The production manager now supports an **optional**
`WIFI_MAX_TX_POWER_QUARTER_DBM` (8..84 SDK units). Undefined preserves the SDK
default. The limit is applied before authentication and after association,
and its readback is logged. A failed configuration backs off; failure to apply
after association is logged without discarding that working association.
Native tests cover configuration failure/recovery and reapplication after
radio/association changes. A low limit can reduce coverage; AUTH_EXPIRE alone
does not justify it.

For a controlled full-application build at a 7 dBm limit:

```sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app --build-property 'compiler.cpp.extra_flags=-DWIFI_MAX_TX_POWER_QUARTER_DBM=28' --build-path /tmp/twinglow-wifi-low-power-build TwinGlow
```

This keeps the same application, TLS buffers and private credentials. It does
not change WPA security or NVS. An explicitly chosen limit can also be defined
in `Config.h` for future builds; the tracked example leaves it commented out.
To restore the SDK default, remove both the extra build flag and any definition
in `Config.h`.

The full application was restored with this explicit limit on 2026-10-12.
The capture runs from 13:02:02 to 13:15:03 (13 minutes), with association/IP at
13:02:04 and a logged post-association limit of 7.00 dBm. All 11 assets downloaded,
the playlist committed, and 38 successful heartbeats and 15 successful config
polls were recorded. There were no Wi-Fi disconnect events, AUTH_EXPIRE events
or TCP receive timeouts. The user switched to image/animation and confirmed
correct display; those branches also appear in the capture.

The current device's `Config.h` now explicitly selects 28 quarter-dBm units,
so ordinary subsequent builds retain this profile. The example stays opt-in.
This is a successful workaround in one measured full-application run, not proof
of a defective radio or power supply: earlier short trials succeeded at both
limits, and one lower-limit trial failed. Router state and elapsed time were
not independently controlled. Longer operation remains necessary to assess
whether the workaround consistently prevents the original outage.
Capture: `.private/diagnostics/twinglow-low-power-20261012.log`.

The diagnostic raw capture is kept locally in
`.private/diagnostics/wifi-diagnostic-20261012.log` (gitignored, no passwords).
Native parser tests and ESP32 compilation also passed; these checks alone do
not establish radio behavior.
