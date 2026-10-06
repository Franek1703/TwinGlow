import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/core/models/pairing_model.dart';
import 'package:twin_glow/core/models/screen_model.dart';
import 'package:twin_glow/core/models/shared_screen_model.dart';
import 'package:twin_glow/core/widgets/shared_screens_panel.dart';
import 'package:twin_glow/features/screen_editor/cubit/screen_editor_image_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';
import 'package:twin_glow/services/firebase/pairing_service.dart';
import 'package:twin_glow/services/firebase/shared_screens_service.dart';
import 'package:twin_glow/services/firebase/shared_catalog_queue.dart';

class MemoryStore implements PairingStore {
  final data = <String, Object?>{};
  int writes = 0;
  bool fail = false;
  @override
  Future<Object?> read(String path) async =>
      data[path] ??
      {
        for (final entry in data.entries)
          if (entry.key.startsWith('$path/'))
            entry.key.substring(path.length + 1): entry.value,
      };
  @override
  Future<void> update(Map<String, Object?> values) async {
    if (fail) throw StateError('offline');
    ++writes;
    for (final entry in values.entries) {
      if (entry.value == null) {
        data.remove(entry.key);
      } else {
        data[entry.key] = jsonDecode(jsonEncode(entry.value));
      }
    }
  }

  @override
  Stream<Object?> watch(String path, {String? field, String? equalTo}) =>
      Stream.fromFuture(read(path));
  @override
  String newKey() => 'key';
  @override
  Future<Map<String, dynamic>> queryEqual(
    String path,
    String field,
    String value, {
    int? limit,
  }) => throw UnimplementedError();
}

class SharedRepository extends FirebaseFakeRepository {
  final pairs = StreamController<PairingModel>.broadcast();
  final previews = StreamController<List<SharedScreenModel>>.broadcast();
  bool failSave = true;
  @override
  Stream<PairingModel> watchPairing(String uid) => pairs.stream;
  @override
  Stream<List<SharedScreenModel>> watchSharedScreens(String id, String uid) =>
      previews.stream;
  @override
  Future<void> updateScreen(
    String device,
    String id,
    ScreenModel screen,
  ) async {
    if (failSave) throw StateError('sharing synchronization failed');
  }
}

void main() {
  final pair = PairingModel(
    pairId: 'pair',
    pairedUserId: 'bob',
    deviceId: 'A',
    partnerDeviceId: 'B',
  );
  final image = AssetModel(
    id: 'image',
    name: 'Lolypop',
    type: AssetType.image,
    pixelData: AnimationFrameModel.emptyGrid()..[0][0] = 0xffff0000,
  );
  final screen = ScreenModel(
    id: 'screen',
    type: ScreenType.image,
    isShared: true,
    assetId: 'old',
    defaultAssetId: 'image',
  );

  test(
    'sharing publishes default content; repeat sync avoids writes; edits refresh it',
    () async {
      final store = MemoryStore();
      final service = SharedScreensService(store, 'alice');
      await service.sync(pair, [screen], [image], sourceVersion: 1);
      var received = await service.watch('pair', 'alice').first;
      expect(received.single.asset.pixelData![0][0], 0xffff0000);
      expect(received.single.asset.id, 'image');
      await service.sync(pair, [screen], [image], sourceVersion: 1);
      expect(store.writes, 1);
      final edited = image.copyWith(
        pixelData: AnimationFrameModel.emptyGrid()..[0][1] = 0xff00ff00,
      );
      await service.sync(pair, [screen], [edited], sourceVersion: 2);
      received = await service.watch('pair', 'alice').first;
      expect(received.single.asset.pixelData![0][1], 0xff00ff00);
      expect(received.single.asset.pixelData![0][0], 0);
    },
  );

  test(
    'disabling sharing, deleting the source or screen removes the preview',
    () async {
      for (final remaining in [
        [screen.copyWith(isShared: false)],
        <ScreenModel>[],
      ]) {
        final store = MemoryStore();
        final service = SharedScreensService(store, 'alice');
        await service.sync(pair, [screen], [image], sourceVersion: 1);
        await service.sync(pair, remaining, [image], sourceVersion: 2);
        expect(await service.watch('pair', 'alice').first, isEmpty);
      }
      final service = SharedScreensService(MemoryStore(), 'alice');
      await service.sync(pair, [screen], [image], sourceVersion: 1);
      await service.sync(pair, [screen], [], sourceVersion: 2);
      expect(await service.watch('pair', 'alice').first, isEmpty);
    },
  );

  test('an older sync cannot republish after successful sharing-off', () async {
    final store = MemoryStore();
    final service = SharedScreensService(store, 'alice');
    await service.sync(pair, [screen], [image], sourceVersion: 1);
    await service.sync(pair, [], [], sourceVersion: 2);
    await expectLater(
      service.sync(pair, [screen], [image], sourceVersion: 1),
      throwsStateError,
    );
    expect(await service.watch('pair', 'alice').first, isEmpty);
    expect(
      pairingMap(
        await store.read('pairing/sharedScreens/pair/alice'),
      )['sourceVersion'],
      2,
    );
  });

  test(
    'shared queue serializes fresh source reads and releases after failure',
    () async {
      final queue = SharedCatalogQueue();
      final store = MemoryStore();
      final service = SharedScreensService(store, 'alice');
      final started = Completer<void>(), release = Completer<void>();
      var version = 1;
      var source = [screen];
      final first = queue.run('same-owner', () async {
        final readSource = source, readVersion = version;
        started.complete();
        await release.future;
        await service.sync(pair, readSource, [
          image,
        ], sourceVersion: readVersion);
      });
      await started.future;
      source = [];
      version = 2;
      final second = queue.run(
        'same-owner',
        () => service.sync(pair, source, [image], sourceVersion: version),
      );
      release.complete();
      await Future.wait([first, second]);
      expect(await service.watch('pair', 'alice').first, isEmpty);
      await expectLater(
        queue.run('same-owner', () async {
          throw StateError('offline');
        }),
        throwsStateError,
      );
      var executed = false;
      await queue.run('same-owner', () async {
        executed = true;
      });
      expect(executed, true);
    },
  );

  test(
    'failed publication preserves the working preview; unpaired and clock screens do not publish',
    () async {
      final store = MemoryStore();
      final service = SharedScreensService(store, 'alice');
      await service.sync(pair, [screen], [image], sourceVersion: 1);
      store.fail = true;
      await expectLater(
        service.sync(pair, [], [], sourceVersion: 2),
        throwsStateError,
      );
      expect(
        (await service.watch('pair', 'alice').first).single.asset.name,
        'Lolypop',
      );
      store.fail = false;
      await service.sync(PairingModel(), [screen], [image], sourceVersion: 2);
      expect(store.writes, 1);
      await service.sync(
        pair,
        [ScreenModel(id: 'clock', type: ScreenType.clock, isShared: true)],
        [],
        sourceVersion: 2,
      );
      expect(await service.watch('pair', 'alice').first, isEmpty);
    },
  );

  test(
    'animation preview retains frames, timing and pixel clearing; corrupt entries are isolated',
    () {
      final fixture = jsonDecode(
        File('../tests/fixtures/pairing-animation.json').readAsStringSync(),
      );
      final data = {
        'schemaVersion': 1,
        'screenId': 'animation',
        'deviceId': 'A',
        'name': 'Animation Screen',
        'assetId': 'animationAsset',
        'assetName': 'Wave',
        'content': fixture,
      };
      final decoded = decodeSharedScreens({
        'animation': data,
        'bad': {'content': {}},
      });
      expect(decoded.single.asset.frames!.length, 2);
      expect(decoded.single.asset.frames![0].durationMs, 100);
      expect(decoded.single.asset.frames![1].durationMs, 250);
      expect(
        decoded.single.asset.frames![1].pixels[0][0],
        anyOf(0, 0xff000000),
      );
      final corrupt = {
        ...data,
        'content': {
          ...fixture,
          'frameDurationsMs': [1, 250],
        },
      };
      expect(decodeSharedScreens({'animation': corrupt}), isEmpty);
    },
  );

  test(
    'failed screen save reports failure and retry clears the error',
    () async {
      final repository = SharedRepository();
      final cubit = ScreenEditorImageCubit(repository, 'A', screen, [image]);
      addTearDown(cubit.close);
      addTearDown(repository.pairs.close);
      addTearDown(repository.previews.close);
      expect(await cubit.save(), false);
      expect(cubit.state.error, contains('sharing synchronization failed'));
      repository.failSave = false;
      expect(await cubit.save(), true);
      expect(cubit.state.error, null);
    },
  );

  testWidgets(
    'partner preview appears live and disappears immediately after unpair',
    (tester) async {
      final repository = SharedRepository();
      addTearDown(repository.pairs.close);
      addTearDown(repository.previews.close);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(393, 852),
          builder: (_, child) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SharedScreensPanel(
                  repository: repository,
                  userId: 'alice',
                ),
              ),
            ),
          ),
        ),
      );
      repository.pairs.add(pair);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      repository.previews.add([
        SharedScreenModel(
          id: 's',
          deviceId: 'B',
          name: 'Partner screen',
          asset: image,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Shared with you'), findsOneWidget);
      expect(find.text('Lolypop'), findsOneWidget);
      repository.pairs.add(PairingModel());
      await tester.pumpAndSettle();
      expect(find.text('Lolypop'), findsNothing);
      expect(tester.takeException(), null);
    },
  );
}
