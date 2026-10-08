import 'package:firebase_core/firebase_core.dart';
import 'pairing_service.dart';

/// Historical memberships are references, not ownership credentials. Check the
/// administrator registry before private reads, and tolerate revoked references
/// without hiding unrelated devices. Network failures still reach the caller.
Future<List<R>> loadOwnedDeviceMappings<M, R>({
  required Iterable<M> mappings,
  required String userId,
  required String Function(M) deviceId,
  required Future<Object?> Function(String) readAccess,
  required Future<R?> Function(M) load,
}) async {
  final results = <R>[];
  for (final mapping in mappings) {
    try {
      final access = pairingMap(await readAccess(deviceId(mapping)));
      if (access['ownerUid'] != userId || access['enabled'] != true) continue;
      final result = await load(mapping);
      if (result != null) results.add(result);
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
    }
  }
  return results;
}
