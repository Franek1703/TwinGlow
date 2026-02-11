class DeviceModel {
  final String id;
  final String name;
  final bool isOnline;
  final bool hasSensor; // BME680
  final String? userId;

  DeviceModel({
    required this.id,
    required this.name,
    required this.isOnline,
    this.hasSensor = false,
    this.userId,
  });

  DeviceModel copyWith({
    String? id,
    String? name,
    bool? isOnline,
    bool? hasSensor,
    String? userId,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      isOnline: isOnline ?? this.isOnline,
      hasSensor: hasSensor ?? this.hasSensor,
      userId: userId ?? this.userId,
    );
  }
}
