class PairingModel {
  /// Id of the authoritative RTDB pairing record.
  final String? pairId;
  final String? pairedUserId;
  final String? pairedUserName;
  final int sharedScreensCount;
  final String? deviceId;
  final String? partnerDeviceId;

  PairingModel({
    this.pairId,
    this.pairedUserId,
    this.pairedUserName,
    this.sharedScreensCount = 0,
    this.deviceId,
    this.partnerDeviceId,
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
      deviceId: deviceId,
      partnerDeviceId: partnerDeviceId,
    );
  }
}

class PairingInvite {
  final String id, fromUid, toUid, fromDeviceId, fromEmail, toEmail, status;
  final int createdAt;
  final String? pairId;
  const PairingInvite({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.fromDeviceId,
    required this.fromEmail,
    required this.toEmail,
    required this.status,
    required this.createdAt,
    this.pairId,
  });
  factory PairingInvite.fromMap(String id, Map<String, dynamic> map) =>
      PairingInvite(
        id: id,
        fromUid: map['fromUid'] as String,
        toUid: map['toUid'] as String,
        fromDeviceId: map['fromDeviceId'] as String,
        fromEmail: map['fromEmail'] as String,
        toEmail: map['toEmail'] as String,
        status: map['status'] as String,
        createdAt: (map['createdAt'] as num).toInt(),
        pairId: map['pairId'] as String?,
      );
  bool get isPending => status == 'pending';
  bool isExpired(DateTime now) =>
      now.millisecondsSinceEpoch >=
      createdAt + const Duration(days: 7).inMilliseconds;
}
