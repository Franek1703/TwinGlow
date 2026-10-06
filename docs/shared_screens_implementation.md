# Shared screens v2 — approved plan and verification

Both paired users edit one complete IMAGE/ANIMATION screen. Each phone's ordinary Screen Playlist contains an independently ordered/enabled reference. Both ESP32s resolve the full screen. Canonical content remains in existing /assets; no asset subcollections or device-content copies.

Approved contract:
- /sharedScreens/{id}: schemaVersion 2, name, uppercase type, availableAssetIds, defaultAssetId, allowManualSwitch, config, contentVersion, pairId, createdBy, STAGING/ACTIVE/REVOKED state, screenRefs (the two device IDs to local reference IDs).
- /devices/{device}/screens/{id}: sharedScreenId, order, enabled, durationMs only. Private legacy screens keep their schema.
- /assets/{id}: existing ownerUid/isDefault/content and image/animation codecs, optional revision, sharingPairId, sharedScreenIds, sharingMutationScreenId. Partner content edits cannot change ownership/defaults/ACLs. Editing a reused asset changes all references. Immutable default templates receive editable private copies in /assets.
- /sharingPairs/{pair}: registry-checked userA/B, deviceA/B, self-only acceptedA/B, PENDING/ACTIVE/CLOSING/REVOKED state, contentVersion, mutationKind/mutationId. Each updated app signs its own consent only after verifying the current RTDB pair. Version increments prove a real SCREEN or ASSET mutation in the same commit.
- /playlistState/{device}: nextOrder, pairId, optional lastSharedScreenId. Transactional monotonic order allocation; narrow partner append creates only the accepted reference. It cannot read private screens or change remote order/settings/device configuration.

RTDB remains the invitation/pairing/snapshot-delivery authority; Firestore bilateral consent authorizes shared content. No Functions, billing upgrade, broad private access, hardware auth changes, or NVS erase.

Implementation:
1. Contract, rules and authorization tests, consent/counters and idempotent staging.
2. Ordinary Flutter playlist resolves refs, observes local/shared versions, shows all pooled assets and both-owner editing. Saves preserve errors; concurrent content edits compare versions.
3. Existing CloudWorker polls sharing state/version at the 60-second config interval independently of local configVersion. Reload required assets on changes; share unchanged cache entries, download individually, validate versions before committing a complete staging playlist. Failures preserve display/cache and leave version unconsumed. Preserve current screen/asset when present.
4. Normal NEXT/PREV/rotation/sleep apply; adding does not interrupt current display; durationMs <= 0 holds. IMAGE/ANIMATION supported; CLOCK/SENSOR/GAME remain local.
5. Retire separate RTDB default-preview UI/publication. Existing ACTION sends remain cached immutable snapshots, whole animations, server timestamps, event IDs/persistent sequence, dedup/reconnect/restart handling, held overrides, and display ACK only after renderer show().

Publication migrates all five source image IDs, preserves source ref identity/order/settings, appends one peer reference and commits ACL/version/ref writes atomically. Deterministic IDs allow retry, and revoked screens use a fresh deterministic generation. Source fingerprint detects concurrent changes. Original private assets are not deleted.

Stopping sharing restores creator's private screen and removes partner ref. Partner-contributed assets receive exact retained copies owned by the creator, validated by narrow rules; ordinary sharing does not copy assets. Remote local order/settings stay unchanged. Unpair freezes publication, retires active and staged screens, revokes Firestore consent, then performs RTDB cleanup, with repeatable phases. Offline devices see revocation on reconnect. Full offline album playback after reboot is not promised (RAM cache).

Acceptance:
- All five images visible in one shared screen on both phones' ordinary playlists; either edits name/default/pool/content; independent order/enabled.
- Two content-free refs, original canonical assets readable by both enrolled devices, inaccessible to unrelated identities.
- Whole animations in both directions (existing 2–16-frame codec), other types rejected; ACTION snapshot behavior preserved.
- Tests: consent/forgery, narrow append, conflicts, interrupted/idempotent migration, asset reuse/delete, unpair/access denial, dedup/reconnect/restart, download/cache failures and revision gating.
- Flutter tests/analysis, Firebase emulator rules and production Dart RTDB integration, native ASan/UBSan + SDK patch tests, ESP32 huge_app build.
- After author verification: independent model gpt-6.1-sol, fork_turns none, receives plan/diff/tests/limits, reads complete flow and surrounding code, reports severity/location/reproduction. Confirmed issues fixed/retested, substantial fixes re-reviewed.

Rollout/hardware procedure:
1. Back up deployed Firestore rules; deploy reviewed rules to twinglow-bab2e; read back and compare. Distinguish local/deployed. Existing RTDB delivery rules remain.
2. Install updated apps on both phones with existing accounts; open both once for self-consent. Verify automatic migration of full five-item pool, two refs and no ordinary asset duplication.
3. Flash both ESP32s with their own existing private DeviceCredentials.h and huge_app, preserving NVS and device IDs.
4. Wait for successful shared/config/asset logs; select with NEXT/PREV (held clock does not advance automatically), cycle all five images with ACTION; observe LEDs/colors/orientation.
5. Reorder/disable on one phone only; edit from either, close apps, verify both devices update after polling + downloads.
6. Add multi-frame animation; check every frame/duration/loop, sleep and bidirectional long-ACTION sends/display ACKs.
7. Break Wi-Fi mid-update; verify working cache, reconnect, restart and snapshot dedup.
8. Stop/unpair from each side in separate runs; verify creator retention, partner ref removal/access denial and physical display exit.

No two-device hardware operation is claimed. USB discovery currently shows no ESP32. Builds/emulators do not prove physical display.

Unpair first freezes the Firestore grant as `CLOSING`. Publication, finalization and content edits stop immediately; authorized human cleanup can restore private content and retire both ACTIVE and STAGING records. Retrying resumes cleanup before terminal REVOKED and RTDB unpair. Devices treat CLOSING as inactive. Migration derives content and its guard from one fresh source snapshot. Exceptional private template/retention copies use SHA-256 IDs bounded below 95 characters; ordinary sharing never copies assets.

Verification completed 2026-10-06:
- Firebase emulator: 29 rules tests pass, plus production Dart PairingService integration.
- Native ASan/UBSan, SDK response/pagination/mask tests and ESP32 huge_app compile pass (2,015,004 bytes flash, 71,204 bytes globals).
- Flutter: 264 tests pass, 1 emulator-only test skipped outside emulator; iOS simulator build passes. Flutter suite and analysis logs: /private/tmp/twinglow-shared-flutter-final.log, /private/tmp/twinglow-shared-analysis-final.log. Analysis has 44 informational existing lints; no errors or warnings.
- Independent gpt-6.1-sol (separate context) traced full code and reported five concrete findings; all were fixed, regression-tested and rechecked, with no remaining confirmed findings.
- Reviewed Firestore rules deployed successfully to twinglow-bab2e and read back: exact match with firebase/firestore.rules. Backup: /private/tmp/twinglow-firestore-before-shared-v2.rules. RTDB rules unchanged this implementation.
- Production pair -P3GXKqounihuSfvsWgM has both users' self-consent ACTIVE. On 2026-10-06 at19:59 UTC, a live Flutter/iOS SDK check using the existing owner login completed publication: shared screen ACTIVE v1, five assets, exact four-field references on both devices (owner order0, partner order1). Four isDefault=true templates use the already prepared editable /assets copies; original private image ID remains unchanged.
- No ESP32 connected. Firmware was compiled, not flashed; no physical two-device display or second-phone SDK operation claimed. A booted iPhone17 simulator was subsequently used for live owner-side publication with the production Flutter service.

Shared pools are capped at 10 assets (private pools and animation frame counts unchanged). This guarantees headroom under the 20-document Firestore rule-access budget for atomic foreign-asset retention and distinct-source publication. Existing-link ACL cleanup authorizes against the current screen's prior pool, avoiding unrelated first-linked screen lookups. The previous provisional cap32 was reduced after emulator testing and independent rule-budget review.

Exact remaining device check (use existing accounts and credentials):
1. Install the updated Flutter app on both phones (`cd twin_glow; flutter run -d <phone-id>`), preserving each login. Open Screen Playlist on both. Check sharingPairs/currentPair ACTIVE and sharedScreens/fullPool contains all five IDs; each device ref contains only sharedScreenId/order/enabled/durationMs. Never manually accept the other account's consent.
2. Compile/upload each board separately with its own enrolled DeviceCredentials.h. Use `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app --build-path /private/tmp/twinglow-hardware-build TwinGlow` and `arduino-cli upload --fqbn esp32:esp32:esp32:PartitionScheme=huge_app --input-dir /private/tmp/twinglow-hardware-build --port <that-board-port> TwinGlow`. Do not erase flash/NVS and do not upload the first device's binary to the second.
3. After shared synchronization (60-second polling plus download time), press NEXT if currently on a held clock. Short ACTION cycles all five images. Change order/enabled on one phone and confirm only its playlist changes. Edit the common name/default/pool and one original asset on each phone; both displays update after successful polling/download, even with apps closed.
4. Publish an animation from each side; verify all frame colors, timings and loop setting. Long ACTION sends current image/animation; verify actual partner display and displayed ACK in each direction. CLOCK/SENSOR/GAME stay local.
5. Disconnect Wi-Fi during downloads, restore it, reboot each board and resend; verify previous valid display/cache survives download failures, and duplicate snapshot events do not redisplay.
6. Unpair from each side in separate runs, then reconnect an offline board. Confirm partner ref disappears, shared content ceases, foreign reads fail, and creator's private restored screen remains editable. If cleanup fails, retry unpair; CLOSING blocks new publication until cleanup finishes.

Permission-denied regression fix, 2026-10-06:
- Reproduced the real error: read an existing legacy source screen then replace it via transaction.set; identical batched writes succeeded while the actual transaction was denied. Both private-only and four-template cases reproduced. Precise backend evaluation mechanism remains unconfirmed.
- Changed the source conversion to transaction.update with explicit deletion of all legacy fields outside sharedScreenId/order/enabled/durationMs. Source fingerprint and transaction read/version protection remain; no security rules were loosened or changed for this fix.
- Added actual Firestore emulator transaction regressions for creator userB, long production IDs, five images, zero/four templates, all real reads, foreign access, and unknown legacy metadata removal. Full31rule tests pass,264Flutter pass with1emulator-onlyskip, analysis44infos/noerrorswarnings, iOS simulator build passes.
- Independent gpt-6.1-sol reproduced the issue separately, verified masked update and re-reviewed the implemented patch: no substantive issue remaining.
- Live temporary entrypoint outside repository used production Firebase Auth/Firestore SDK and FirebaseRepositoryImpl.setScreenShared with existing owner login; PASS without administrator bypass. Server readback confirms shared state ACTIVE and both content-free device references. Ordinary app restored after check.
