# Pairing and received display: implementation and verification

This is the executable record of the approved plan. Scope: one selected device
per user, one active pair per user, latest pending snapshot wins, held received
override, restart returns to the local playlist. No Functions or billing upgrade.
No production deployment or physical-device validation is implied by local tests.

### Partner app previews (2026-10-06 follow-up)

Live inspection found a correctly ACTIVE RTDB pair for devices
`tg_f4ec6bb0ef83`/`tg_a398a36269f7`. The owner's image screen
`screen_1788191873393` had `isShared:true`, pointing to the private `Lolypop`
asset, but neither an app preview nor a device-send mailbox existed. The editor
incorrectly promised both users could edit the same screen, while its write
only changed the owner's flag. Firestore/RTDB scoped rules had been deployed by
this inspection; their earlier audit state above is historical.

The app now presents a read-only **Shared with you** section on Home for the
selected paired device and on Pairing Management. Its separate RTDB catalog is
`/pairing/sharedScreens/{pairId}/{ownerUid}`. Each owner catalog is
`{sourceVersion,updatedAt,screens:{screenId:entry}}`, where an entry is
`{schemaVersion:1,deviceId,screenId,name,assetId,assetName,content}`;
content uses the existing bounded packed image/animation contract. It previews
the screen's default asset, with legacy single-asset/first-pool fallbacks. Source
Firestore assets/screens remain private; only their owner writes the catalog,
and only human active pair members read it. It grants no partner editing rights.
No privileged credentials are put into the app, and no Functions are required.

Screen save/delete/sharing changes, referenced asset edits/deletion and opening
the paired app synchronize the owner's catalog. Repeated identical configuration
versions cause no writes. Missing/deleted assets and disabled sharing remove the corresponding
preview. Transport failure preserves the previous catalog and surfaces an error;
Retry/opening the owner's updated app reconciles a Firestore write that committed
before an RTDB failure. This is explicitly two-stage synchronization, not an
atomic cross-database transaction. Synchronization serializes fresh source reads
through publication across repository instances. Source reads explicitly use
Firestore server data and check device `configVersion` before and after loading
screens/assets. RTDB requires a strictly increasing source version, also across
different app sessions. Empty catalogs retain their revision so an old publisher
cannot resurrect an unshared/deleted screen. A deletion retry reconciles even
when its earlier Firestore commit already removed the asset.
Unpair clears the catalog; ended-pair rules
also deny reads even to old apps that do not clear this new path. In-flight UI
callbacks from a previous pair cannot restore previews after unpair/re-pair.

Catalog updates never write device `incoming`, mailboxes or acknowledgments.
Saving a shared screen therefore adds an app preview; hold ACTION on the sender
ESP32 to send its **currently displayed cached content** to the partner panel.
The device's sent snapshot remains independent of later app preview changes.
Other screen types do not enter this image/animation catalog. The editor describes
these behaviors and stays open on a failed save rather than reporting success.

Follow-up acceptance: shared image and looping animation previews appear for the
partner; private screens and foreign accounts cannot be read; source edits,
deleted/default assets, sharing off, unpair/re-pair and failed sync behave as
above; old firmware event transport remains unchanged. Tests cover the Dart
catalog writer/decoder, a live widget, save failures, actual Dart REST operations
against emulator rules, and unauthorized/cross-owner/oversized writes.

### Restart diagnosed from hardware logs on 2026-10-06

The user reported a repeatable core-0 `LoadProhibited` immediately after the
initial configuration poll on `tg_a398a36269f7`. Its exact ELF was recovered from
the Arduino IDE cache (SHA256 beginning `4ae4fdb75`). Symbolication resolved the
backtrace to `ListDocumentsOptions::set()` -> `pageToken()` ->
`FirestoreRepo::getScreens()` -> `CloudWorker::execute()`.

FirebaseClient's default `DocumentMask` copy left its internal buffer pointer
referencing a destroyed temporary. The library patch now supplies owning copy
operations. Separately, missing Firestore `nextPageToken` values were converted
by ArduinoJson to the string `"null"`, causing an invalid second-page request
even for a new device's empty playlist. The pagination parser now ends the list
on absent/null tokens and rejects malformed token types.

The SDK regression reproduces the original lifetime bug under AddressSanitizer
and tests the patched classes; native firmware tests cover pagination edge
cases. Rebuild with `tools/firebaseclient-patch/apply.sh` applied, then upload
without erasing NVS. Hardware confirmation must show an empty playlist loads
without a reboot, and a playlist with more than four screens loads all pages.

The follow-up ESP32 `huge_app` build passed (2,009,848 bytes of program storage,
71,188 bytes of globals). An independent `gpt-6.1-sol` reviewer found no actionable
issues and independently reran both regression suites. The connected ESP32 was
identified as `tg_a398a36269f7`, and the original panic was observed directly.
The corrected binary was uploaded with flash verification and the existing
partition layout, preserving the NVS region. Its ELF SHA256 starts `ed01574841`.
The USB port disappeared before post-upload monitoring could start, so runtime
stability and physical multipage loading remain unconfirmed. The working-tree
`DeviceCredentials.h` was then switched to the first device `tg_f4ec6bb0ef83` at
the user's request; the already-uploaded second-device binary retains its own
credentials.

## Evidence and original failures

Baseline commit: `f9a6c415f82ecec83be7afaff5efef3cea064cf5`.
Existing user changes to `firebase-debug.log` and `.claude/` were preserved.
There were no applicable AGENTS.md files. Baseline Flutter: 231 passing tests,
49 analyzer findings. Firmware required the ESP32 `huge_app` partition even
before this change; the default 1.3 MB application partition was too small.

Confirmed in baseline code, independently of documentation:

- `NvsStore` generates a persistent device ID. BLE supplies the user's UID.
  `FirestoreRepo::claimDevice` writes a user's device membership. LegacyToken
  authenticated the device using a project-wide secret, without device claims.
- `FirebaseRepositoryImpl` used Firestore user/pair/invitation documents. The
  invitation UI in `PairingManagementView` was hidden behind `if (false)` and
  confirmed a send before awaiting it. Pair creation lacked the `state` required
  by the then-deployed pair rules.
- `setScreenShared` wrote `deviceId/screenId` pointers; firmware
  `getSharedScreen` expected asset fields. Local image/animation pools are the
  authoritative selection in `ScreenPlaylist::getCurrentAssetId`.
- `ButtonActions::handleSendToPair` wrote `/pairs/{pairId}/events`. There was no
  firmware receiver that changed the display. The installed FirebaseClient
  `ValueConverter` quotes `const char*` JSON; `object_t` is required. Event time
  used uptime rather than server time.
- `handleConfigLoading` could clear a working cache to retry a failed list;
  `ScreenPlaylist::setScreens` reset selection. Firmware downloaded preview
  fields and all screens in one response. The library request formatter also
  truncated paths/queries exceeding its approximately 300-byte buffer.
- Read-only live service inspection during planning found RTDB root read/write
  open, Firestore device data open, restricted user profiles, no invitation
  match, and pair rules inconsistent with app writes. Billing was disabled and
  Functions API unavailable. These are observations at audit time, not claims
  about rules currently deployed. The new files under `firebase/` are local.

## Chosen architecture and rationale

RTDB is the sole authority for pairing, delivery, and acknowledgments. Firestore
continues to hold private local screen configuration and assets. App and device
use one shared versioned contract. Acceptance and unpairing use atomic RTDB
multi-location updates with rules verifying the entire resulting state.

An immutable snapshot captures the selected **cached content being displayed**.
Source edits/deletion after capture do not alter the received content; a new send
captures a new version. An animation sends the whole looping asset, restarting
at frame zero, rather than its current frame. This avoids partner access to
Firestore assets, dangling pointers, and extra asset lookups. The mailbox itself
is overwritten on newer sends; it is not an immutable historical archive.

Firmware polls the small `/config/{deviceId}` document every five seconds on the
existing CloudWorker. It fetches the mailbox only for a changed, unhandled event.
Compared with an always-open SSE stream, this reuses the existing transport/task,
adds no second TLS connection or streaming parser, and keeps RAM and maintenance
cost low. Compared with Firestore event polling, this avoids repeated billed
Firestore event reads and snapshots eliminate another download. Expected latency
is the poll interval plus queued work/network time, not a guaranteed five-second
SLA. Two continuously connected devices make roughly 24 small control reads per
minute; RTDB bills bandwidth including protocol overhead. Packed payloads are
bounded and mailboxes store one event per direction rather than growing history.

An administrator enrolls each device with a unique Firebase Email/Password Auth
account, custom claim `twinGlowDeviceId`, and matching administrator-managed
owner/auth UID bindings in both databases. Hardware credentials are private,
separate from public Firebase project settings. Firmware uses validated TLS with
Google Trust Services roots; auth refresh and cloud I/O have one worker owner.
This replaces the privileged legacy database credential without requiring a
server billing upgrade. Registry enrollment is separate from accepting a pair
in the app; the BLE UID alone cannot prove ownership.

## Contract v1

Firestore `/deviceAccess/{deviceId}` and RTDB `/deviceAccess/{deviceId}`:
`{authUid, ownerUid, enabled}`. Only administrators write these bindings. Device
auth must match both its claim and registry auth UID; human auth must match the
owner. Device IDs are stable NVS IDs, not inferred from an email address.

RTDB paths:

| Path | Contents and purpose |
| --- | --- |
| `/pairing/directory/{uid}` | Normalized Auth email; self-write, exact email query limited to one result. Signed-in recipient must have opened the updated app. |
| `/pairing/invites/{id}` | `schemaVersion:1`, `fromUid`, `toUid`, `fromDeviceId`, normalized `fromEmail/toEmail`, `status`, server `createdAt/updatedAt`, and `pairId` only upon acceptance. |
| `/pairing/pending/{fromUid}/{toUid}` | One pending invite ID per directed user combination; retry cannot create another. |
| `/pairing/users/{uid}` | Active pair ID, set for both users in acceptance. |
| `/pairing/pairs/{id}` | `schemaVersion:1`, `userA/B`, `deviceA/B`, `userAEmail/userBEmail`, `inviteId`, `state:ACTIVE`, server `createdAt`; terminal `ENDED` adds server `endedAt`. |
| `/config/{deviceId}/pair` | `{pairId, partnerDeviceId}`, set for both devices atomically. |
| `/config/{recipient}/incoming` | Complete event metadata, written atomically with the sender's mailbox. |
| `/pairing/mailboxes/{pairId}/{sender}` | `{meta, content}`, one latest snapshot per sender. |
| `/pairing/acks/{pairId}/{receiver}` | `{eventId, sequence, status:displayed\|rejected, at:serverTimestamp}`. |
| `/config/{deviceId}/configVersion` | Owner-written configuration doorbell; Firestore version remains authoritative for local playlist updates. |

Metadata: `schemaVersion:1`, random 128-bit `eventId`, persistent monotonic
integer `sequence`, `pairId`, `senderDeviceId`, `recipientDeviceId`, `screenId`,
`assetId`, and server `sentAt` in epoch milliseconds. IDs are 1–95 characters,
excluding RTDB path punctuation. Sequences are positive integers within JavaScript
safe integer range. Screen/asset IDs are provenance, not content access pointers.

`content` is either:

```json
{"type":"IMAGE","encoding":"SPARSE_PACKED_V1","pixelsPacked":"00ff0000"}
```

or:

```json
{"type":"ANIMATION","encoding":"DELTA_SPARSE_PACKED_V1","basePixelsPacked":"00ff0000","frameDeltasPacked":["000000001100ff00"],"frameDurationsMs":[100,250],"frameCount":2,"loop":true}
```

Packed groups are `IIRRGGBB`: index 0–255 plus RGB888. Images allow up to 256
pixels (2,048 characters), including a blank image. Animation limits match the
app: 2–16 frames, 50–5,000 ms per frame, one cumulative delta per later frame,
8,192 packed characters total, 2,048 per frame, looping. At least one visible
animation pixel is required by the decoder/app. Rules also reject extra fields,
invalid shapes, non-integer numbers, oversized runs and forged metadata.
The serialized publication/envelope limit is 12,288 bytes.

Only the enrolled selected sender device can publish, and only while its pair
is ACTIVE. Participants and enrolled selected devices can read active mailboxes;
only the receiver can acknowledge the event currently in its incoming slot.
Firestore assets stay readable by their owner, that owner's enrolled devices,
or authenticated clients for defaults. Pairing does not grant partner asset
access. Local membership ownership cannot be forged by BLE UID or human writes.

## Behavior and failure policy

- App displays live incoming/outgoing invitations, enrollable-device selection,
  Accept, Reject, Cancel, expiry/dismissal, and Unpair. Successful send confirmation
  waits for the server-completed operation. Errors preserve usable state.
- Invitations expire after seven days; the server enforces expiry. Concurrent
  acceptance can establish only one pair. Acceptance retries verify the committed
  pair, invite, and selected device. Switching device on a pending invitation
  requires cancelling the earlier invitation.
- Mark a local IMAGE/ANIMATION screen shareable, select its asset with short
  ACTION if manual pool switching is enabled, and hold ACTION to capture/send.
  Clock, sensor and game/unknown screens remain local and do not send. Legacy
  ANIMATION records holding a still image send that displayed image. A received
  override cannot be forwarded by holding ACTION.
- The latest queued send replaces the prior queued snapshot. An already-running
  publication can complete first, followed by the newer one. RAM-only outgoing
  snapshots retry transient transport, 408, 429 and 5xx failures for 60 seconds;
  other server failures stop the send. Restart drops an unpublished RAM send.
- Publication writes mailbox and recipient metadata atomically. On uncertain
  write response the firmware reads its existing metadata before retrying; the
  same ID is treated as committed without changing its server timestamp.
- Receiver validates pair, sender, recipient, event ID and sequence against the
  latest observed control slot. Superseded results do not replace the display.
  A newer send replaces an older override. Failed downloads/JSON/memory reads
  retry while preserving the display and local cache. Complete but invalid
  content is marked rejected; unseen events older than 24 hours are rejected.
  Clock far in the future defers handling until its server time is plausible.
- NVS stores the handled pair+sequence before activation. Duplicate polls,
  reconnection, and normal restart cannot replay handled events. Restart returns
  to the local playlist; an unhandled fresh mailbox can be received after boot.
  Full NVS erase changes the device ID and requires administrative re-enrollment
  and explicit re-pairing; preserve NVS during firmware updates.
- `displayed` acknowledgment is queued only after the first renderer `show()`.
  There is no separate receipt acknowledgment. It means the firmware painted the
  frame, not that physical LEDs have been independently observed. A power failure
  between the NVS checkpoint and first paint can consume an event without an
  acknowledgment; this is not an exactly-once delivery guarantee.
- Override is held until short ACTION, PREV/NEXT, a newer valid send, or observed
  unpair. ACTION dismisses without advancing the saved pool selection; PREV/NEXT
  dismisses and navigates the local playlist. Automatic rotation pauses during
  the override. Brightness buttons still change the owner's saved brightness.
- Blank sleep defers incoming content and does not mark it handled; sends while
  blanked are disabled. Dim sleep can show received content at sleep brightness.
  Wake restarts animation at frame zero. Configuration syncing runs while asleep.
- Config reloads and downloads run on CloudWorker. Screen lists are paged four
  at a time, excluding preview pixels. Staged caches share unchanged live objects;
  replacement assets remain private until all enabled references parse. A
  failure discards staging, leaves the version unconsumed and retries on the
  fallback poll. Successful commit preserves selected screen and pool asset by
  ID and then prunes unreferenced cache entries. The override has independent
  asset lifetime and renderer, so local sync cannot overwrite it.
- Unpair atomically ends the pair and clears both users' bindings, incoming
  slots, mailboxes and acknowledgments. Server access stops immediately. A
  connected device dismisses upon its next successful control read; an offline
  device cannot observe revocation until reconnecting. Local screens/assets
  and `isShared` flags survive.

## Implementation order and review requirements

The approved dependency order was: shared contract and authorization; app atomic
pairing operations and visible awaited UI; firmware scoped auth; snapshot capture
and latest-send queue; control polling, decoding, held display and acknowledgment;
transactional cache/playlist synchronization; regression/contract/rules tests;
full static analysis and firmware build; independent review; confirmed-finding
fixes, repeat relevant checks and re-review substantial fixes.

Key implementation files: `pairing_service.dart` (transport-injectable production
operations), `firebase_pairing_store.dart` (SDK adapter), PairingCubit/view,
`PairSnapshot`, `PairingController`, `PairTransport`, `CloudWorker`, ButtonActions,
`PlaylistUpdate`, AssetCache, ScreenPlaylist, and FirestoreRepo/RtdbRepo.
`firebase/generate-rules.mjs` is the maintainable rules source; commit its generated
`database.rules.json` too. Re-run generation before tests/deployment.

The mandatory reviewer is a separate `gpt-6.1-sol` subagent, launched with
`fork_turns="none"` after author verification. It receives this approved plan,
acceptance criteria, baseline/diff scope, test results and hardware/deployment
limitations. It must read changes and surrounding code independently and trace
identity/claiming → invitations → acceptance → selected snapshot → publication →
reception → display → ack → unpair. Findings need severity, location, reproduction
scenario, authorization/data-contract/regression analysis and missing tests.
Confirmed defects are fixed; substantial fixes are sent back for recheck.

## Enrollment and migration/deployment procedure

No administrative script writes by default. These instructions are remaining
operator work; no production enrollment, migration or rules deployment was done.

1. Back up Firestore and RTDB. Stop old firmware/app writes for cutover. Inspect
   existing memberships manually and verify the real owner for each stable
   device ID; public historical documents are not trustworthy owner evidence.
2. Enable Firebase Email/Password Auth. Use administrator Application Default
   Credentials in a private environment; never give service credentials to the
   app or firmware. From `firebase/`, install locked dependencies with `npm ci`.
3. Enroll each known device, initially with dry-run:

   ```sh
   node enroll-device.mjs --project PROJECT --database-url RTDB_URL --device DEVICE_ID --owner USER_UID
   ```

   Inspect the output, then add `--apply --credential-output /private/path/DeviceCredentials.h`.
   The file is created with mode 0600 and never overwritten or printed. Install
   it as `TwinGlow/DeviceCredentials.h` for **only that device**; it is gitignored.
   The script checks owner/registry consistency and refuses a human Auth account
   as an existing device identity. Interrupted registry updates can be rerun.
4. Copy `Config.h.example` and public `FirebaseSecrets.h.example` as needed;
   set the Firebase API key, project ID and RTDB URL. Legacy DB secrets are no
   longer used by runtime auth. Match the actual GPIO wiring.
5. Apply both reproducible FirebaseClient patches:

   ```sh
   bash tools/firebaseclient-patch/apply.sh
   arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app TwinGlow
   ```

   Upload to each enrolled device without erasing its NVS device ID. Then finish
   Wi-Fi/user BLE setup through the app. Registry ownership must match that UID;
   claiming is rejected otherwise. Verify own Firestore device and membership.
6. Inspect legacy pair retirement with the migration script; after backup and
   cutover add `--apply`:

   ```sh
   node migrate-pairing.mjs --project PROJECT --database-url RTDB_URL
   ```

   It marks legacy Firestore pairs ENDED and removes old RTDB `/pairs`, including
   historical events. It does not copy events, delete assets, or edit local
   screen documents. Old shared pointers are ignored. Users explicitly re-pair.
   Private assets containing only legacy `userId` ownership must also migrate:
   prepare an administrator-verified JSON object `{"ASSET_ID":"OWNER_UID"}` and
   pass `--asset-owner-manifest /private/verified-assets.json` to the same script.
   It validates existing users, refuses owner/default conflicts, sets canonical
   `ownerUid/isDefault:false`, and preserves pixel fields and IDs. The app queries
   canonical ownership only; the legacy query is incompatible with private rules.
   Legacy device memberships are retained but filtered through the owner registry
   before metadata, presence or screen reads, so they cannot block enrolled ones.
   If a historical screen contains only a partner pointer and no local asset
   pool, select a locally owned/default asset in the app before sharing it.
7. From `firebase/`, generate rules, run `npm test`, then deploy in the intended
   project only after operator approval:

   ```sh
   node generate-rules.mjs
   firebase deploy --project PROJECT --only firestore:rules,database
   ```

   This directory's `firebase.json` owns the new rules. The Flutter Firebase
   project configuration file does not deploy them. Confirm the actual target
   RTDB instance/project and compare deployed rules with the checked-in files.
   Revoke the old database secret after old clients have retired; a legacy
   privileged secret can bypass client rules. Validate unauthenticated/device
   scope failures against the deployed service before calling cutover complete.
8. Sign both users into the updated app, open Pairing Management to publish
   their directory profiles, and perform the hardware procedure below.

## Acceptance criteria and two-device verification

Use two real ESP32 panels A/B, enrolled to separate users, fresh app builds,
serial logs, known stable IDs, and confirmed deployed rules. Record firmware,
FirebaseClient/core versions, heap/largest-block/worker-stack diagnostics,
timestamps, event IDs/sequences and observed display content.

1. Both users see only owned devices. Alice selects A and invites Bob by email.
   Confirm no premature success while network is blocked. Bob sees incoming
   invite live, chooses B and accepts; both apps/devices see the same pair. Repeat
   with Bob inviting Alice, plus Reject, Cancel, expired invite and concurrent
   acceptance of two invitations. No partial/orphan pair may be established.
2. Put distinctive red/green images in a manually selectable A screen pool;
   mark shareable, select the non-default image, hold ACTION. B must display that
   selected image, retain it across local rotation/config refresh, and acknowledge
   only after first paint. Capture RTDB metadata/snapshot and compare pixels.
   Repeat B→A; unshared, CLOCK, SENSOR and game/unknown screens must not publish.
3. Send a two-frame animation in both directions with visible pixel removal,
   different durations and looping. Receiver starts at frame zero, applies
   cumulative deltas and loops. Also test a 16-frame/8,192-character animation,
   a blank first frame, an unchanged delta, full-color image and blank image.
   Observe physical colors/orientation, playback timing, heap and stack margin.
4. Edit/delete the sender asset after capture and while recipient is offline.
   Original snapshot must still display on reconnect if fresh. Another send of
   an edited cached asset must capture what the sender currently shows.
5. Send rapidly three times, disconnect while publishing, and restore Wi-Fi
   before/after 60 seconds. Latest pending wins; expired RAM sends disappear;
   uncertain successful writes do not change event ID/server timestamp. Receiver
   eventually shows the latest publication rather than a stale download result.
6. Reconnect and reboot receiver after display and dismissal: handled events
   do not replay. Reboot before first receipt: a fresh unhandled event can show
   after boot. Restart sender with unsent RAM event: it is dropped. Test unseen
   events over 24 hours and clock skew; no stale replay.
7. Block receiver downloads mid-response; inject an invalid complete payload in
   an isolated test database with admin access. Working display/cache remain on
   transport failures; valid-metadata malformed content gets rejected. Low RAM
   must not blank content, reset selection or silently consume a config version.
8. Change local playlist while an override shows, including order/default pool
   edits and removal of its previously selected local screen. Override remains.
   Dismiss with ACTION and navigate with PREV/NEXT; verify preserved local IDs
   when still present. Failure during staged download preserves the old playlist;
   success commits and prunes only now-unreferenced local assets.
9. Blank sleep delays receipt/checkpoint/ack until wake; dim sleep shows at dim
   brightness. Wake restarts animation. Brightness controls preserve saved
   owner brightness and sleep brightness policy. Holding ACTION cannot forward
   a received override and cannot publish while the panel is blanked.
10. Unpair from each side. Both apps become unpaired, connected receiver returns
    to local content, server mailboxes/acks/bindings disappear. Former partner,
    unrelated device/user and unauthenticated clients must fail reads/writes.
    Existing local assets/screens remain. Pair again and verify new ID isolation.
11. Run a 24-hour soak: send both ways periodically, edit configuration, drop
    Wi-Fi, cross sleep windows and token expiry (>1 hour). Track heap/largest
    block, stack, reboots, latency and failed/retried operations. No progressive
    memory loss, stuck auth refresh, starvation, replay or crash is acceptable.

## Local verification

Commands and test scope:

```sh
cd twin_glow
flutter test
flutter analyze
cd ../firebase
npm test
cd ..
bash tools/native-pairing/test.sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app --build-path /private/tmp/twinglow-pairing-build TwinGlow
```

`npm test` runs the sanitizer-enabled native production-code test first, uses
its serialized publication in security tests, then runs the actual Dart
PairingService through a REST transport against Auth/RTDB emulators. Normal
Flutter runs skip that one test unless emulator environment variables exist.
Golden fixtures are shared by the Flutter asset writer and native decoder.
The native test substitutes Arduino timing, matrix hardware, NVS persistence
and cloud transport; it exercises real cache, codec, renderer, controller,
playlist and staging code. It does not emulate radio, TLS or real flash.

Final local checks (2026-10-02):

| Check | Result |
| --- | --- |
| Full Flutter tests | 237 passed; 1 emulator-only test skipped in this command |
| Flutter analysis | Ran successfully; exit status 1 for 46 existing informational findings, no errors/warnings or new pairing findings (baseline 49) |
| Firebase/Auth/Firestore/RTDB emulators | 14 rules, production-query and ownership-migration tests passed |
| Production Dart service against emulators | 1 integration test passed, including the production owner-filter helper |
| Native production-code suite | Passed with AddressSanitizer and UndefinedBehaviorSanitizer |
| ESP32 firmware | Built with core 3.3.11 / huge_app; 2,009,912 application bytes, 71,188 global RAM bytes including the final delimiter compatibility adjustment |
| Dependency compatibility patch | Both required installed FirebaseClient hunks checked successfully |
| Administrative scripts / diff checks | JavaScript syntax checks and git diff --check passed |
| Physical panels / production deployment | Not performed |

Independent reviewer: **gpt-6.1-sol**, separate context (`fork_turns=none`). It
reported two P1 findings (rules-incompatible legacy asset collection query;
auth readiness/transport work under an ESP32 critical section) and one P2 finding
(stale/disabled/reassigned memberships blocking valid devices and asset screen
traversal). All were confirmed and fixed. The reviewer independently rechecked
canonical queries, explicit legacy-owner migration, shared enrollment filtering,
and auth readiness outside the mux, closed all three findings, and reported no
further concrete defects. It also reran the native sanitizer suite independently.
Physical TLS, token refresh, heap/stack margin, display timing/colors and soak
remain validation gaps, not covered by a successful compilation.

A final compatibility adjustment reads the last separator in the atomic NVS
pair/sequence record, so allowed pair IDs containing a colon retain deduplication.
It does not change the stored representation. The independent reviewer also
confirmed this adjustment is compatible and reported no new issue.
No identified pair of ESP32s was available for testing; local tests/builds are
not proof of two physical devices operating end to end.
