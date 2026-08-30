/// Default LED brightness, matching the firmware's `DEFAULT_BRIGHTNESS`.
const int kDefaultBrightness = 128;

/// Nightly window during which the device dims itself.
///
/// Times are minutes since local midnight, which is what the firmware compares
/// against `localtime()` - no string parsing on the device, and no format
/// ambiguity. [endMinute] below [startMinute] means the window crosses midnight,
/// which is the common case (23:00 - 07:00).
class SleepSchedule {
  static const int defaultStartMinute = 23 * 60; // 23:00
  static const int defaultEndMinute = 7 * 60; // 07:00

  /// Dim rather than dark, so the panel still reads as a night light.
  /// Zero is the one special value: it blanks the display entirely.
  static const int defaultBrightness = 10;

  final bool enabled;
  final int startMinute;
  final int endMinute;

  /// 0-255 while asleep. `0` means the panel is blanked, which brightness alone
  /// cannot express - `MatrixDriver::setBrightness` clamps 0 up to 1.
  final int brightness;

  const SleepSchedule({
    this.enabled = false,
    this.startMinute = defaultStartMinute,
    this.endMinute = defaultEndMinute,
    this.brightness = defaultBrightness,
  });

  SleepSchedule copyWith({
    bool? enabled,
    int? startMinute,
    int? endMinute,
    int? brightness,
  }) {
    return SleepSchedule(
      enabled: enabled ?? this.enabled,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SleepSchedule &&
      other.enabled == enabled &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(enabled, startMinute, endMinute, brightness);
}

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

  /// LED brightness while awake, 0-255 (the NeoPixel scale the firmware uses).
  /// The UI works in percent; see `core/utils/brightness_scale.dart`.
  ///
  /// Null means the document has no value yet, which the device reads as "keep
  /// whatever you are running on" - the same rule [tzPosix] follows.
  final int? brightness;

  /// Null means the document has no schedule yet; the device keeps its cached one.
  final SleepSchedule? sleepMode;

  DeviceModel({
    required this.id,
    required this.name,
    required this.isOnline,
    this.hasSensor = false,
    this.userId,
    this.timezone,
    this.tzPosix,
    this.brightness,
    this.sleepMode,
  });

  DeviceModel copyWith({
    String? id,
    String? name,
    bool? isOnline,
    bool? hasSensor,
    String? userId,
    String? timezone,
    String? tzPosix,
    int? brightness,
    SleepSchedule? sleepMode,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      isOnline: isOnline ?? this.isOnline,
      hasSensor: hasSensor ?? this.hasSensor,
      userId: userId ?? this.userId,
      timezone: timezone ?? this.timezone,
      tzPosix: tzPosix ?? this.tzPosix,
      brightness: brightness ?? this.brightness,
      sleepMode: sleepMode ?? this.sleepMode,
    );
  }
}
