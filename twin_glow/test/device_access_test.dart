import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/services/firebase/device_access.dart';

void main() {
  test(
    'legacy, disabled and reassigned mappings cannot block an enrolled device',
    () async {
      final loaded = <String>[];
      final results = await loadOwnedDeviceMappings<String, String>(
        mappings: [
          'legacy',
          'valid',
          'disabled',
          'reassigned',
          'revokedDuringRead',
        ],
        userId: 'owner',
        deviceId: (id) => id,
        readAccess: (id) async {
          if (id == 'legacy') {
            throw FirebaseException(
              plugin: 'database',
              code: 'permission-denied',
            );
          }
          return {
            'ownerUid': id == 'reassigned' ? 'other' : 'owner',
            'enabled': id != 'disabled',
          };
        },
        load: (id) async {
          loaded.add(id);
          if (id == 'revokedDuringRead') {
            throw FirebaseException(
              plugin: 'firestore',
              code: 'permission-denied',
            );
          }
          return id;
        },
      );
      expect(results, ['valid']);
      expect(loaded, ['valid', 'revokedDuringRead']);
    },
  );
  test(
    'network failures propagate rather than masquerading as no owned devices',
    () async {
      await expectLater(
        loadOwnedDeviceMappings<String, String>(
          mappings: ['valid'],
          userId: 'owner',
          deviceId: (id) => id,
          readAccess: (id) async => throw FirebaseException(
            plugin: 'database',
            code: 'network-request-failed',
          ),
          load: (id) async => id,
        ),
        throwsA(isA<FirebaseException>()),
      );
    },
  );
}
