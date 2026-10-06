import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/pairing_model.dart';
import 'package:twin_glow/features/pairing/cubit/pairing_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';

class ControlledRepository extends FirebaseFakeRepository {
  final pairs = StreamController<PairingModel>.broadcast();
  final invites = StreamController<List<PairingInvite>>.broadcast();
  final operation = Completer<void>();
  @override
  Stream<PairingModel> watchPairing(String id) => pairs.stream;
  @override
  Stream<List<PairingInvite>> watchPairingInvites(
    String id, {
    required bool incoming,
  }) => incoming ? invites.stream : const Stream.empty();
  @override
  Future<void> sendPairingInvite(
    String userId,
    String email,
    String deviceId,
  ) => operation.future;
}

void main() {
  test(
    'send awaits server completion; failure keeps error and live invites still arrive',
    () async {
      final repo = ControlledRepository();
      final cubit = PairingCubit(repo, 'user');
      addTearDown(() async {
        await cubit.close();
        await repo.pairs.close();
        await repo.invites.close();
      });
      await Future<void>.delayed(Duration.zero);
      final send = cubit.sendInvite('friend@example.com', 'A');
      expect(cubit.state.isBusy, true);
      var completed = false;
      send.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      repo.operation.completeError(StateError('permission denied'));
      expect(await send, false);
      expect(cubit.state.isBusy, false);
      expect(cubit.state.error, contains('permission denied'));
      const invite = PairingInvite(
        id: 'i',
        fromUid: 'friend',
        toUid: 'user',
        fromDeviceId: 'B',
        fromEmail: 'friend@example.com',
        toEmail: 'user@example.com',
        status: 'pending',
        createdAt: 1,
      );
      repo.invites.add([invite]);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.incoming, [invite]);
      repo.pairs.add(
        PairingModel(
          pairId: 'pair',
          pairedUserId: 'friend',
          deviceId: 'A',
          partnerDeviceId: 'B',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.pairing.isPaired, true);
      repo.pairs.add(PairingModel());
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.pairing.isPaired, false);
      expect(cubit.state.acknowledgment, isEmpty);
    },
  );
}
