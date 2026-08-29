import 'package:flutter_timezone/flutter_timezone.dart';

import 'posix_timezones.dart';

/// A timezone in the two forms the device document stores: the IANA name the
/// app shows, and the POSIX rule the firmware applies.
class ResolvedTimeZone {
  final String iana;
  final String posix;

  const ResolvedTimeZone(this.iana, this.posix);
}

/// Reads the phone's timezone and resolves it to a POSIX rule.
///
/// Falls back to the phone's plain UTC offset if the platform cannot name its
/// zone. That loses DST rules, but a device on the right offset beats one stuck
/// on UTC, and the picker can still correct it.
Future<ResolvedTimeZone> resolvePhoneTimeZone() async {
  final offset = DateTime.now().timeZoneOffset;
  try {
    final iana = (await FlutterTimezone.getLocalTimezone()).identifier;
    return ResolvedTimeZone(iana, posixTzFor(iana, offset));
  } catch (_) {
    return ResolvedTimeZone(offsetLabel(offset), fixedOffsetTz(offset));
  }
}

/// Human-readable offset, e.g. `UTC+02:00`. Used only when the zone has no name.
String offsetLabel(Duration offset) {
  if (offset == Duration.zero) return 'UTC';
  final minutes = offset.inMinutes;
  final sign = minutes > 0 ? '+' : '-';
  final abs = minutes.abs();
  final hours = (abs ~/ 60).toString().padLeft(2, '0');
  final rem = (abs % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$rem';
}
