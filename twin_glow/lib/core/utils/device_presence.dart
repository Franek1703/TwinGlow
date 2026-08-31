/// Liveness from the `/presence/<deviceId>` node, kept in one place so every
/// reader agrees on what "online" means.
///
/// The firmware rewrites the node every `PRESENCE_UPDATE_INTERVAL_MS` (20 s,
/// `TwinGlow/Config.h`) with `online: true` and a fresh `lastSeenMs`. Nothing
/// ever writes `online: false`: a device that is unplugged, crashes or loses
/// Wi-Fi simply stops writing, and FirebaseClient 2.2.7 has no `onDisconnect`
/// to register a tombstone with. So the flag on its own reads as online
/// forever - it is the freshness of `lastSeenMs` that says the device is there.
library;

/// How long a presence write stays trustworthy.
///
/// Three writes at the firmware's 20 s interval, so a single dropped update
/// (or one slow TLS handshake) does not blink the badge, while a device that
/// has genuinely gone reads as offline about a minute later.
const Duration kPresenceTtl = Duration(seconds: 60);

/// How often a held presence value is re-judged against the clock.
///
/// The RTDB stream only delivers events when the node *changes*, and a dead
/// device changes nothing. Without a repeating re-check the last value - the
/// one that said `online: true` - would stand forever.
const Duration kPresenceRecheckInterval = Duration(seconds: 10);

/// Timestamps below this are not wall-clock times.
///
/// The firmware falls back to `millis()` when NTP has not landed yet
/// (`RtdbRepo::updatePresence`), which lands in 1970 and would otherwise read
/// as ancient. The same 2001-09-09 floor the firmware uses to sanity-check
/// `time()`.
const int _minPlausibleEpochMs = 1000000000 * 1000;

/// Whether a device counts as online, given the presence node it last wrote.
///
/// [now] defaults to the current time; pass it to judge a snapshot against a
/// specific instant. A missing or implausible `lastSeenMs` falls back to the
/// flag alone, so presence written by an older firmware (or by the fake
/// repository) still reads the way it used to.
bool isPresenceOnline(Map<dynamic, dynamic>? presence, {DateTime? now}) {
  if (presence == null) return false;
  if (presence['online'] != true) return false;

  final lastSeenMs = _asEpochMs(presence['lastSeenMs']);
  if (lastSeenMs == null) return true;

  final ageMs = (now ?? DateTime.now()).millisecondsSinceEpoch - lastSeenMs;
  // A negative age means the device's clock runs ahead of the phone's. That is
  // skew, not staleness, so it counts as fresh.
  return ageMs <= kPresenceTtl.inMilliseconds;
}

/// The age of a presence write, or null when it carries no usable timestamp.
Duration? presenceAge(Map<dynamic, dynamic>? presence, {DateTime? now}) {
  if (presence == null) return null;
  final lastSeenMs = _asEpochMs(presence['lastSeenMs']);
  if (lastSeenMs == null) return null;
  return Duration(
    milliseconds: (now ?? DateTime.now()).millisecondsSinceEpoch - lastSeenMs,
  );
}

/// RTDB hands numbers back as int or double depending on how they were written.
int? _asEpochMs(Object? value) {
  final int ms;
  if (value is int) {
    ms = value;
  } else if (value is double) {
    ms = value.round();
  } else if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed == null) return null;
    ms = parsed;
  } else {
    return null;
  }
  return ms >= _minPlausibleEpochMs ? ms : null;
}
