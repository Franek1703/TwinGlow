import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/pairing_model.dart';
import 'package:twin_glow/features/auth/cubit/auth_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';
import 'package:twin_glow/views/pairing/pairing_management_view.dart';

class ViewRepository extends FirebaseFakeRepository {
  final result = Completer<void>();
  final invites = StreamController<List<PairingInvite>>.broadcast();
  @override
  Future<PairingModel> getPairing(String id) async => PairingModel();
  @override
  Stream<PairingModel> watchPairing(String id) => Stream.value(PairingModel());
  @override
  Stream<List<PairingInvite>> watchPairingInvites(
    String id, {
    required bool incoming,
  }) => incoming ? invites.stream : const Stream.empty();
  @override
  Future<void> sendPairingInvite(String id, String email, String device) =>
      result.future;
}

void main() {
  testWidgets(
    'pending invites are visible and confirmation waits for completion',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = ViewRepository();
      final auth = AuthCubit(repo);
      addTearDown(() async {
        await auth.close();
        await repo.invites.close();
      });
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(393, 852),
          builder: (context, child) => BlocProvider.value(
            value: auth,
            child: MaterialApp(home: PairingManagementView(repository: repo)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.invites.add([
        PairingInvite(
          id: 'i',
          fromUid: 'friend',
          toUid: 'user1',
          fromDeviceId: 'B',
          fromEmail: 'friend@example.com',
          toEmail: 'john@example.com',
          status: 'pending',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Invitation from friend@example.com'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'partner@example.com');
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('Send Invite'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Invite'));
      await tester.pump();
      expect(find.text('Invite sent to partner@example.com'), findsNothing);
      repo.result.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Invite sent to partner@example.com'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
}
