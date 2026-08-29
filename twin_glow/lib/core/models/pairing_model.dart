class PairingModel {
  /// Id of the /pairs document. Needed to address shared-screen pointers.
  final String? pairId;
  final String? pairedUserId;
  final String? pairedUserName;
  final int sharedScreensCount;

  PairingModel({
    this.pairId,
    this.pairedUserId,
    this.pairedUserName,
    this.sharedScreensCount = 0,
  });

  bool get isPaired => pairedUserId != null;

  PairingModel copyWith({
    String? pairId,
    String? pairedUserId,
    String? pairedUserName,
    int? sharedScreensCount,
  }) {
    return PairingModel(
      pairId: pairId ?? this.pairId,
      pairedUserId: pairedUserId ?? this.pairedUserId,
      pairedUserName: pairedUserName ?? this.pairedUserName,
      sharedScreensCount: sharedScreensCount ?? this.sharedScreensCount,
    );
  }
}
