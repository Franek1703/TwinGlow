import '../../core/models/pairing_model.dart';

/// Transport is injectable so the exact production repository operations can
/// also run against RTDB REST/emulators without Flutter platform channels.
abstract class PairingStore {
  Future<Object?> read(String path);
  Future<Map<String, dynamic>> queryEqual(
    String path,
    String field,
    String value, {
    int? limit,
  });
  Stream<Object?> watch(String path, {String? field, String? equalTo});
  Future<void> update(Map<String, Object?> values);
  String newKey();
}

Map<String, dynamic> pairingMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};
const pairingTimestamp = {'.sv': 'timestamp'};

class PairingService {
  final PairingStore store;
  final String uid, email;
  final DateTime Function() now;
  PairingService(this.store, this.uid, this.email, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  Future<void> ensureProfile() => store.update({
    'pairing/directory/$uid': {'email': email.trim().toLowerCase()},
  });
  Future<PairingModel> getPairing() async {
    final id = await store.read('pairing/users/$uid');
    if (id is! String) return PairingModel();
    final p = pairingMap(await store.read('pairing/pairs/$id'));
    if (p['state'] != 'ACTIVE' || (p['userA'] != uid && p['userB'] != uid)) {
      return PairingModel();
    }
    final a = p['userA'] == uid;
    return PairingModel(
      pairId: id,
      pairedUserId: p[a ? 'userB' : 'userA'] as String,
      pairedUserName: p[a ? 'userBEmail' : 'userAEmail'] as String,
      deviceId: p[a ? 'deviceA' : 'deviceB'] as String,
      partnerDeviceId: p[a ? 'deviceB' : 'deviceA'] as String,
    );
  }

  Stream<PairingModel> watchPairing() =>
      store.watch('pairing/users/$uid').asyncMap((_) => getPairing());
  Stream<List<PairingInvite>> watchInvites(bool incoming) => store
      .watch(
        'pairing/invites',
        field: incoming ? 'toUid' : 'fromUid',
        equalTo: uid,
      )
      .map(
        (value) =>
            pairingMap(value).entries
                .map((e) => PairingInvite.fromMap(e.key, pairingMap(e.value)))
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
  Future<void> _owned(String deviceId) async {
    final binding = pairingMap(await store.read('deviceAccess/$deviceId'));
    if (binding['ownerUid'] != uid || binding['enabled'] != true) {
      throw StateError('Device is not enrolled for this account');
    }
  }

  Future<void> sendInvite(String targetEmail, String deviceId) async {
    await _owned(deviceId);
    await ensureProfile();
    final normalized = targetEmail.trim().toLowerCase();
    if (normalized == email.trim().toLowerCase()) {
      throw StateError('Cannot invite yourself');
    }
    if ((await getPairing()).isPaired) {
      throw StateError('Unpair before sending another invitation');
    }
    final users = await store.queryEqual(
      'pairing/directory',
      'email',
      normalized,
      limit: 1,
    );
    if (users.isEmpty) throw StateError('User not found');
    final toUid = users.keys.single;
    final oldId = await store.read('pairing/pending/$uid/$toUid');
    if (oldId is String) {
      final old = PairingInvite.fromMap(
        oldId,
        pairingMap(await store.read('pairing/invites/$oldId')),
      );
      if (old.isPending && !old.isExpired(now())) {
        if (old.fromDeviceId != deviceId) {
          throw StateError(
            'Cancel the existing invitation before choosing another device',
          );
        }
        return;
      }
      if (old.isPending) await resolveInvite(oldId, 'expired');
    }
    final id = store.newKey();
    try {
      await store.update({
        'pairing/invites/$id': {
          'schemaVersion': 1,
          'fromUid': uid,
          'toUid': toUid,
          'fromDeviceId': deviceId,
          'fromEmail': email.trim().toLowerCase(),
          'toEmail': normalized,
          'status': 'pending',
          'createdAt': pairingTimestamp,
          'updatedAt': pairingTimestamp,
        },
        'pairing/pending/$uid/$toUid': id,
      });
    } catch (_) {
      // A retry after a lost response/concurrent identical request is successful
      // only if the server actually has a matching live invitation.
      final storedId = await store.read('pairing/pending/$uid/$toUid');
      if (storedId is String) {
        final stored = PairingInvite.fromMap(
          storedId,
          pairingMap(await store.read('pairing/invites/$storedId')),
        );
        if (stored.isPending &&
            stored.fromDeviceId == deviceId &&
            !stored.isExpired(now())) {
          return;
        }
      }
      rethrow;
    }
  }

  Future<void> acceptInvite(String id, String deviceId) async {
    await _owned(deviceId);
    final invite = PairingInvite.fromMap(
      id,
      pairingMap(await store.read('pairing/invites/$id')),
    );
    if (invite.toUid != uid) {
      throw StateError('Invitation is addressed to another user');
    }
    if (invite.status == 'accepted') {
      final p = await getPairing();
      if (p.pairId == invite.pairId && p.deviceId == deviceId) return;
      throw StateError('Invitation has already been consumed');
    }
    if (!invite.isPending || invite.isExpired(now())) {
      throw StateError('Invitation is no longer pending');
    }
    final pairId = store.newKey();
    final changes = <String, Object?>{
      'pairing/invites/$id/status': 'accepted',
      'pairing/invites/$id/pairId': pairId,
      'pairing/invites/$id/updatedAt': pairingTimestamp,
      'pairing/pending/${invite.fromUid}/$uid': null,
      'pairing/pairs/$pairId': {
        'schemaVersion': 1,
        'userA': invite.fromUid,
        'userB': uid,
        'deviceA': invite.fromDeviceId,
        'deviceB': deviceId,
        'userAEmail': invite.fromEmail,
        'userBEmail': invite.toEmail,
        'inviteId': id,
        'state': 'ACTIVE',
        'createdAt': pairingTimestamp,
      },
      'pairing/users/${invite.fromUid}': pairId,
      'pairing/users/$uid': pairId,
      'config/${invite.fromDeviceId}/pair': {
        'pairId': pairId,
        'partnerDeviceId': deviceId,
      },
      'config/$deviceId/pair': {
        'pairId': pairId,
        'partnerDeviceId': invite.fromDeviceId,
      },
    };
    try {
      await store.update(changes);
    } catch (_) {
      final p = await getPairing();
      final committed = pairingMap(await store.read('pairing/invites/$id'));
      if (committed['status'] == 'accepted' &&
          committed['pairId'] == p.pairId &&
          p.deviceId == deviceId) {
        return;
      }
      rethrow;
    }
  }

  Future<void> resolveInvite(String id, String status) async {
    if (!['rejected', 'cancelled', 'expired'].contains(status)) {
      throw ArgumentError.value(status);
    }
    final i = PairingInvite.fromMap(
      id,
      pairingMap(await store.read('pairing/invites/$id')),
    );
    if (!i.isPending) return;
    await store.update({
      'pairing/invites/$id/status': status,
      'pairing/invites/$id/updatedAt': pairingTimestamp,
      'pairing/pending/${i.fromUid}/${i.toUid}': null,
    });
  }

  Future<void> unpair() async {
    final p = await getPairing();
    if (!p.isPaired) return;
    final id = p.pairId!;
    await store.update({
      'pairing/pairs/$id/state': 'ENDED',
      'pairing/pairs/$id/endedAt': pairingTimestamp,
      'pairing/users/$uid': null,
      'pairing/users/${p.pairedUserId}': null,
      'config/${p.deviceId}/pair': null,
      'config/${p.partnerDeviceId}/pair': null,
      'config/${p.deviceId}/incoming': null,
      'config/${p.partnerDeviceId}/incoming': null,
      'pairing/mailboxes/$id': null,
      'pairing/acks/$id': null,
    });
  }
}
