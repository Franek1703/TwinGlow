class PairingModel {
  final String? pairedUserId;
  final String? pairedUserName;
  final int sharedScreensCount;

  PairingModel({
    this.pairedUserId,
    this.pairedUserName,
    this.sharedScreensCount = 0,
  });

  bool get isPaired => pairedUserId != null;

  PairingModel copyWith({
    String? pairedUserId,
    String? pairedUserName,
    int? sharedScreensCount,
  }) {
    return PairingModel(
      pairedUserId: pairedUserId ?? this.pairedUserId,
      pairedUserName: pairedUserName ?? this.pairedUserName,
      sharedScreensCount: sharedScreensCount ?? this.sharedScreensCount,
    );
  }
}
