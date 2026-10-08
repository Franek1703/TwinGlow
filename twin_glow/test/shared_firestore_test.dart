import 'dart:convert';
import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/pairing_model.dart';
import 'package:twin_glow/core/models/screen_model.dart';
import 'package:twin_glow/services/firebase/shared_firestore_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late SharedFirestoreService alice, bob;
  PairingModel pair(String who) => PairingModel(
    pairId: 'pair',
    pairedUserId: who == 'alice' ? 'bob' : 'alice',
    deviceId: who == 'alice' ? 'A' : 'B',
    partnerDeviceId: who == 'alice' ? 'B' : 'A',
  );
  ScreenModel model({List<String>? ids, int? version, String? defaultId}) =>
      ScreenModel(
        id: 'source',
        type: ScreenType.image,
        name: 'Shared album',
        isShared: true,
        availableAssetIds: ids ?? ['a0', 'a1', 'a2', 'a3', 'a4'],
        defaultAssetId: defaultId ?? 'a0',
        sharedVersion: version,
      );
  setUp(() async {
    db = FakeFirebaseFirestore();
    alice = SharedFirestoreService(db, 'alice');
    bob = SharedFirestoreService(db, 'bob');
    await db.doc('devices/A').set({'configVersion': 0});
    await db.doc('devices/B').set({'configVersion': 0});
    await db.doc('devices/A/screens/source').set({
      'order': 3,
      'enabled': true,
      'durationMs': 10000,
      ...SharedFirestoreService.content(model()),
      'type': 'image',
    });
    await db.doc('devices/B/screens/clock').set({
      'order': 0,
      'enabled': true,
      'type': 'clock',
    });
    for (var i = 0; i < 5; i++) {
      await db.doc('assets/a$i').set({
        'ownerUid': 'alice',
        'isDefault': false,
        'type': 'IMAGE',
        'encoding': 'SPARSE_PACKED_V1',
        'pixelsPacked': '00ff0000',
      });
    }
  });
  Future<String> publish() async {
    expect(await alice.consent(pair('alice')), false);
    expect(await bob.consent(pair('bob')), true);
    return alice.publish(pair('alice'), 'A', 'source', model());
  }

  test(
    'bilateral consent, whole five-image pool, two references and idempotent migration',
    () async {
      final id = await publish();
      final shared = (await db.doc('sharedScreens/$id').get()).data()!;
      expect(shared['availableAssetIds'], ['a0', 'a1', 'a2', 'a3', 'a4']);
      final refs = shared['screenRefs'] as Map;
      final a = (await db.doc('devices/A/screens/source').get()).data()!;
      final b = (await db.doc('devices/B/screens/${refs['B']}').get()).data()!;
      expect(a, {
        'sharedScreenId': id,
        'order': 3,
        'enabled': true,
        'durationMs': 10000,
      });
      expect(b['order'], 1);
      expect(b.containsKey('availableAssetIds'), false);
      expect((await db.collection('assets').get()).docs.length, 5);
      await alice.publish(pair('alice'), 'A', 'source', model());
      expect((await db.collection('devices/B/screens').get()).docs.length, 2);
      Object? firestoreValue(Object? value) {
        if (value is String) return {'stringValue': value};
        if (value is bool) return {'booleanValue': value};
        if (value is int) return {'integerValue': '$value'};
        if (value is List) {
          return {
            'arrayValue': {'values': value.map(firestoreValue).toList()},
          };
        }
        if (value is Map) {
          return {
            'mapValue': {
              'fields': {
                for (final e in value.entries) e.key: firestoreValue(e.value),
              },
            },
          };
        }
        return {'nullValue': null};
      }

      expect(
        {
          'fields': {
            for (final e in shared.entries) e.key: firestoreValue(e.value),
          },
        },
        jsonDecode(
          File(
            '../tests/fixtures/shared-screen-firestore.json',
          ).readAsStringSync(),
        ),
      );
    },
  );
  test(
    'pending consent cannot publish and does not modify the source',
    () async {
      await expectLater(
        alice.publish(pair('alice'), 'A', 'source', model()),
        throwsStateError,
      );
      expect(
        (await db.doc('devices/A/screens/source').get())
            .data()!['sharedScreenId'],
        isNull,
      );
    },
  );
  test(
    'partner edits the same pool; stale version rejects; local order remains independent',
    () async {
      final id = await publish();
      await db.doc('devices/B/screens/shared_$id').update({
        'order': 9,
        'enabled': false,
      });
      await bob.update(
        id,
        model(ids: ['a0', 'a4'], defaultId: 'a4', version: 1),
      );
      expect(
        (await db.doc('sharedScreens/$id').get()).data()!['defaultAssetId'],
        'a4',
      );
      await expectLater(alice.update(id, model(version: 1)), throwsStateError);
      expect(
        (await db.doc('devices/A/screens/source').get()).data()!['order'],
        3,
      );
      expect(
        (await db.doc('devices/B/screens/shared_$id').get()).data()!['order'],
        9,
      );
      expect(
        (await db.doc('assets/a1').get()).data()!['sharedScreenIds'],
        isEmpty,
      );
    },
  );
  test(
    'missing asset fails without replacing working source or creating partner reference',
    () async {
      await alice.consent(pair('alice'));
      await bob.consent(pair('bob'));
      await db.doc('assets/a4').delete();
      await expectLater(
        alice.publish(pair('alice'), 'A', 'source', model()),
        throwsStateError,
      );
      expect(
        (await db.doc('devices/A/screens/source').get())
            .data()!['sharedScreenId'],
        isNull,
      );
      expect((await db.collection('devices/B/screens').get()).docs.length, 1);
    },
  );
  test(
    'public templates are copied once into canonical assets and never edited in place',
    () async {
      await db.doc('assets/a0').update({'isDefault': true});
      final id = await publish();
      expect(
        (await db.doc('sharedScreens/$id').get()).data()!['defaultAssetId'],
        SharedFirestoreService.copyId('copy', id, 'a0'),
      );
      expect(
        (await db.doc('assets/a0').get()).data()!['sharedScreenIds'],
        isNull,
      );
      expect(
        (await db
                .doc(
                  'assets/${SharedFirestoreService.copyId('copy', id, 'a0')}',
                )
                .get())
            .data()!['ownerUid'],
        'alice',
      );
    },
  );
  test(
    'partner stops sharing: creator keeps private content including partner-owned assets',
    () async {
      final id = await publish();
      await db.doc('assets/b').set({
        'ownerUid': 'bob',
        'isDefault': false,
        'type': 'IMAGE',
        'pixelsPacked': '00ffffff',
      });
      await bob.update(id, model(ids: ['a0', 'b'], version: 1));
      await bob.stop(id);
      final a = (await db.doc('devices/A/screens/source').get()).data()!;
      expect(a['sharedScreenId'], isNull);
      expect(a['order'], 3);
      expect(a['isShared'], false);
      expect(a['availableAssetIds'], [
        'a0',
        SharedFirestoreService.copyId('retained', id, 'b'),
      ]);
      expect(
        (await db
                .doc(
                  'assets/${SharedFirestoreService.copyId('retained', id, 'b')}',
                )
                .get())
            .data()!['ownerUid'],
        'alice',
      );
      expect(
        (await db.doc('devices/B/screens/shared_$id').get()).exists,
        false,
      );
      await bob.stop(id); // Retry must be a no-op, not a second restore/copy.
      await bob.revoke('pair');
      await expectLater(alice.consent(pair('alice')), throwsStateError);
    },
  );
  test(
    'animation pools retain the full encoded animations and other screen types are rejected',
    () async {
      await alice.consent(pair('alice'));
      await bob.consent(pair('bob'));
      await db.doc('assets/anim').set({
        'ownerUid': 'alice',
        'isDefault': false,
        'type': 'ANIMATION',
        'encoding': 'DELTA_SPARSE_PACKED_V1',
        'basePixelsPacked': '00ff0000',
        'frameDeltasPacked': ['00000000'],
        'frameDurationsMs': [100, 200],
        'frameCount': 2,
        'loop': true,
      });
      final animation = ScreenModel(
        id: 'source',
        type: ScreenType.animation,
        availableAssetIds: ['anim'],
        defaultAssetId: 'anim',
      );
      await db
          .doc('devices/A/screens/source')
          .update(SharedFirestoreService.content(animation));
      final id = await alice.publish(pair('alice'), 'A', 'source', animation);
      expect(
        (await db.doc('sharedScreens/$id').get()).data()!['type'],
        'ANIMATION',
      );
      expect((await db.doc('assets/anim').get()).data()!['frameDurationsMs'], [
        100,
        200,
      ]);
      expect(
        () => SharedFirestoreService.validate(
          SharedFirestoreService.content(
            ScreenModel(id: 'clock', type: ScreenType.clock),
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'a revoked screen can be shared again without reviving old references or duplicating assets',
    () async {
      final first = await publish();
      await alice.stop(first);
      final second = await alice.publish(pair('alice'), 'A', 'source', model());
      expect(second, isNot(first));
      expect(
        (await db.doc('sharedScreens/$first').get()).data()!['state'],
        'REVOKED',
      );
      expect((await db.collection('assets').get()).docs.length, 5);
      expect((await db.collection('devices/B/screens').get()).docs.length, 2);
    },
  );
  test(
    'migration derives content and fingerprint from one fresh source snapshot',
    () async {
      await alice.consent(pair('alice'));
      await bob.consent(pair('bob'));
      final stale = model();
      await db.doc('devices/A/screens/source').update({
        'name': 'Concurrent edit',
        'availableAssetIds': ['a4'],
        'defaultAssetId': 'a4',
      });
      final id = await alice.publish(pair('alice'), 'A', 'source', stale);
      final data = (await db.doc('sharedScreens/$id').get()).data()!;
      expect(data['name'], 'Concurrent edit');
      expect(data['availableAssetIds'], ['a4']);
      expect(data['defaultAssetId'], 'a4');
    },
  );
  test(
    'closing freezes publication and edits, and cleans active plus staging screens on retry',
    () async {
      final id = await publish();
      await db.doc('sharedScreens/stage').set({
        ...(await db.doc('sharedScreens/$id').get()).data()!,
        'state': 'STAGING',
        'contentVersion': 0,
      });
      await bob.beginClosing(pair('bob'));
      expect(await alice.consent(pair('alice')), false);
      await expectLater(alice.update(id, model(version: 1)), throwsStateError);
      await expectLater(
        alice.publish(pair('alice'), 'A', 'source', model()),
        throwsStateError,
      );
      await bob.stop('stage');
      await bob.stop(id);
      await bob.beginClosing(pair('bob'));
      await bob.stop(id);
      await bob.revoke('pair');
      expect(
        (await db.doc('sharedScreens/stage').get()).data()!['state'],
        'REVOKED',
      );
      expect(
        (await db.doc('devices/A/screens/source').get())
            .data()!['sharedScreenId'],
        isNull,
      );
      expect((await db.collection('devices/B/screens').get()).docs.length, 1);
      for (var i = 0; i < 5; i++) {
        expect(
          (await db.doc('assets/a$i').get()).data()!['sharedScreenIds'],
          isEmpty,
        );
      }
    },
  );
  test(
    'repeated retention uses bounded IDs even for maximum-length inputs',
    () async {
      final screen = List.filled(220, 's').join();
      var asset = List.filled(95, 'a').join();
      for (var i = 0; i < 20; i++) {
        final next = SharedFirestoreService.copyId('retained', screen, asset);
        expect(next.length, lessThanOrEqualTo(95));
        expect(next, SharedFirestoreService.copyId('retained', screen, asset));
        expect(
          next,
          isNot(SharedFirestoreService.copyId('retained', screen, 'other')),
        );
        asset = next;
      }
    },
  );
  test(
    'closing a fresh pair creates a tombstone before any consent can activate it',
    () async {
      await bob.beginClosing(pair('bob'));
      expect(await alice.consent(pair('alice')), false);
      expect(await bob.consent(pair('bob')), false);
      await expectLater(
        alice.publish(pair('alice'), 'A', 'source', model()),
        throwsStateError,
      );
      await bob.revoke('pair');
      expect(
        (await db.doc('sharingPairs/pair').get()).data()!['state'],
        'REVOKED',
      );
    },
  );
  test(
    'foreign maximum-length asset survives retention then sharing and retention in reverse',
    () async {
      final first = await publish();
      final foreign = List.filled(95, 'b').join();
      await db.doc('assets/$foreign').set({
        'ownerUid': 'bob',
        'isDefault': false,
        'type': 'IMAGE',
        'pixelsPacked': '00ffffff',
      });
      await bob.update(first, model(ids: ['a0', foreign], version: 1));
      await alice.stop(first);
      final retained =
          ((await db.doc('devices/A/screens/source').get())
                          .data()!['availableAssetIds']
                      as List)
                  .last
              as String;
      expect(retained.length, lessThanOrEqualTo(95));
      await db.doc('assets/b0').set({
        'ownerUid': 'bob',
        'isDefault': false,
        'type': 'IMAGE',
        'pixelsPacked': '00ff0000',
      });
      final reverseModel = model(ids: ['b0'], defaultId: 'b0');
      await db.doc('devices/B/screens/reverse').set({
        ...SharedFirestoreService.content(reverseModel),
        'order': 8,
        'enabled': true,
        'durationMs': 10000,
      });
      final reverse = await bob.publish(
        pair('bob'),
        'B',
        'reverse',
        reverseModel,
      );
      await alice.update(
        reverse,
        model(ids: ['b0', retained], defaultId: retained, version: 1),
      );
      await alice.stop(reverse);
      final local = (await db.doc('devices/B/screens/reverse').get()).data()!;
      final twiceRetained = local['defaultAssetId'] as String;
      expect(twiceRetained.length, lessThanOrEqualTo(95));
      final asset = (await db.doc('assets/$twiceRetained').get()).data()!;
      expect(asset['ownerUid'], 'bob');
      expect(asset['pixelsPacked'], '00ffffff');
    },
  );
  test('shared pool cap protects atomic rule access budget', () {
    final ten = List.generate(10, (i) => 'asset_$i');
    SharedFirestoreService.validate(
      SharedFirestoreService.content(model(ids: ten, defaultId: ten.first)),
    );
    expect(
      () => SharedFirestoreService.validate(
        SharedFirestoreService.content(
          model(ids: [...ten, 'overflow'], defaultId: ten.first),
        ),
      ),
      throwsStateError,
    );
  });
}
