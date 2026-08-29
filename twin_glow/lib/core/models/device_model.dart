class DeviceModel {
  final String id;
  final String name;
  final bool isOnline;
  final bool hasSensor; // BME680
  final String? userId;

  /// IANA zone name, e.g. `Europe/Warsaw`. Display only - the firmware never
  /// reads this, it exists so the zone is legible in the app and the console.
  final String? timezone;

  /// POSIX TZ rule derived from [timezone], e.g. `CET-1CEST,M3.5.0,M10.5.0/3`.
  /// This is what the device actually applies; see `core/utils/posix_timezones.dart`.
  final String? tzPosix;

  DeviceModel({
    required this.id,
    required this.name,
    required this.isOnline,
    this.hasSensor = false,
    this.userId,
    this.timezone,
    this.tzPosix,
  });

  DeviceModel copyWith({
    String? id,
    String? name,
    bool? isOnline,
    bool? hasSensor,
    String? userId,
    String? timezone,
    String? tzPosix,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      isOnline: isOnline ?? this.isOnline,
      hasSensor: hasSensor ?? this.hasSensor,
      userId: userId ?? this.userId,
      timezone: timezone ?? this.timezone,
      tzPosix: tzPosix ?? this.tzPosix,
    );
  }
}
