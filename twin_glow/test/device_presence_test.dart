import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/utils/device_presence.dart';
import 'package:twin_glow/features/device/cubit/devices_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';

/// A fake whose presence stream is driven by the test rather than emitting once.
class _PresenceRepository extends FirebaseFakeRepository {
  final _presence = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> watchDevicePresence(String deviceId) =>
      _presence.stream;

  void emitPresence(Map<String, dynamic> data) => _presence.add(data);

  Future<void> dispose() => _presence.close();
}

void main() {
  final now = DateTime.utc(2026, 8, 31, 12, 0, 0);
  int msAgo(Duration age) => now.subtract(age).millisecondsSinceEpoch;

  group('isPresenceOnline', () {
    test('a fresh write is online', () {
      expect(
        isPresenceOnline(
          {'online': true, 'lastSeenMs': msAgo(const Duration(seconds: 5))},
          now: now,
        ),
        isTrue,
      );
    });

    test('survives one missed 20 s update', () {
      expect(
        isPresenceOnline(
          {'online': true, 'lastSeenMs': msAgo(const Duration(seconds: 40))},
          now: now,
        ),
        isTrue,
      );
    });

    test('goes offline once the write is older than the TTL', () {
      expect(
        isPresenceOnline(
          {'online': true, 'lastSeenMs': msAgo(kPresenceTtl)},
          now: now,
        ),
        isTrue,
        reason: 'exactly at the TTL still counts',
      );
      expect(
        isPresenceOnline(
          {
            'online': true,
            'lastSeenMs': msAgo(kPresenceTtl + const Duration(seconds: 1)),
          },
          now: now,
        ),
        isFalse,
      );
    });

    test('an unplugged device reads offline however old the write is', () {
      expect(
        isPresenceOnline(
          {'online': true, 'lastSeenMs': msAgo(const Duration(days: 30))},
          now: now,
        ),
        isFalse,
      );
    });

    test('online: false is offline regardless of freshness', () {
      expect(
        isPresenceOnline(
          {'online': false, 'lastSeenMs': msAgo(Duration.zero)},
          now: now,
        ),
        isFalse,
      );
    });

    test('a missing node is offline', () {
      expect(isPresenceOnline(null, now: now), isFalse);
      expect(isPresenceOnline({}, now: now), isFalse);
    });

    test('a clock running ahead of the phone is skew, not staleness', () {
      expect(
        isPresenceOnline(
          {
            'online': true,
            'lastSeenMs': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
          },
          now: now,
        ),
        isTrue,
      );
    });

    test('falls back to the flag when lastSeenMs is missing or implausible', () {
      // Older firmware, or the fake repository, writes no usable timestamp.
      expect(isPresenceOnline({'online': true}, now: now), isTrue);
      // RtdbRepo falls back to millis() before NTP lands - a 1970 timestamp,
      // which must not be read as a month-old device.
      expect(
        isPresenceOnline({'online': true, 'lastSeenMs': 30000}, now: now),
        isTrue,
      );
    });

    test('accepts the number types RTDB hands back', () {
      final fresh = msAgo(const Duration(seconds: 5));
      expect(
        isPresenceOnline({'online': true, 'lastSeenMs': fresh.toDouble()}, now: now),
        isTrue,
      );
      expect(
        isPresenceOnline({'online': true, 'lastSeenMs': '$fresh'}, now: now),
        isTrue,
      );
    });
  });

  group('presenceAge', () {
    test('reports how long ago the device last wrote', () {
      expect(
        presenceAge(
          {'online': true, 'lastSeenMs': msAgo(const Duration(seconds: 90))},
          now: now,
        ),
        const Duration(seconds: 90),
      );
    });

    test('is null without a usable timestamp', () {
      expect(presenceAge({'online': true}, now: now), isNull);
      expect(presenceAge(null, now: now), isNull);
    });
  });

  group('DevicesCubit presence', () {
    test('a device that stops writing goes offline with no new event',
        () async {
      final repository = _PresenceRepository();
      // Short enough to observe; production re-checks every 10 s.
      final cubit = DevicesCubit(
        repository,
        'user1',
        presenceRecheckInterval: const Duration(milliseconds: 25),
      );
      addTearDown(() async {
        await cubit.close();
        await repository.dispose();
      });

      await cubit.stream.firstWhere((state) => state.hasLoaded);

      // One write, already most of the way through its TTL. This is the only
      // event the stream ever delivers - exactly what an unplugged device
      // leaves behind.
      repository.emitPresence({
        'online': true,
        'lastSeenMs': DateTime.now()
            .subtract(kPresenceTtl - const Duration(milliseconds: 400))
            .millisecondsSinceEpoch,
      });

      // The fake's device already reads online, and _applyPresence() does not
      // re-emit a value that has not changed - so assert the state rather than
      // waiting for an emission that correctly never comes.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.activeDevice!.isOnline, isTrue);

      final wentOffline = await cubit.stream
          .firstWhere((state) => state.activeDevice?.isOnline == false)
          .timeout(const Duration(seconds: 5));

      expect(wentOffline.activeDevice!.isOnline, isFalse);
      expect(wentOffline.devices.single.isOnline, isFalse);
    });

    test('a device still writing stays online across re-checks', () async {
      final repository = _PresenceRepository();
      final cubit = DevicesCubit(
        repository,
        'user1',
        presenceRecheckInterval: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        await cubit.close();
        await repository.dispose();
      });

      await cubit.stream.firstWhere((state) => state.hasLoaded);
      repository.emitPresence({
        'online': true,
        'lastSeenMs': DateTime.now().millisecondsSinceEpoch,
      });
      // Many re-checks later, with no further stream event, it is still online.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(cubit.state.activeDevice!.isOnline, isTrue);
    });
  });
}
