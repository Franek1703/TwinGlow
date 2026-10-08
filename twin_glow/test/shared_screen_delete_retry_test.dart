// SDK interfaces are intentionally stubbed only at this test boundary, without
// constructing platform channels or changing production inheritance.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/services/firebase/firebase_repository_impl.dart';

// Only the SDK boundary is stubbed. The actual repository deleteAsset branch
// must reconcile a previously committed deletion, including on another retry.
class TestUser implements User {
  @override
  String get uid => 'alice';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuth implements FirebaseAuth {
  @override
  User? get currentUser => TestUser();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MissingAsset implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  bool get exists => false;
  @override
  Map<String, dynamic>? data() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestDocument implements DocumentReference<Map<String, dynamic>> {
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => MissingAsset();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestCollection implements CollectionReference<Map<String, dynamic>> {
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => TestDocument();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestFirestore implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      TestCollection();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestDatabase implements FirebaseDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeleteRepository extends FirebaseRepositoryImpl {
  bool offline = true;
  int reconciliations = 0;
  DeleteRepository()
    : super(
        auth: TestAuth(),
        firestore: TestFirestore(),
        database: TestDatabase(),
      );
  @override
  Future<void> syncSharedScreens(String uid) async {
    expect(uid, 'alice');
    ++reconciliations;
    if (offline) throw StateError('offline');
  }
}

void main() {
  test(
    'retry reconciles the partner catalog even if Firestore asset deletion already committed',
    () async {
      final repository = DeleteRepository();
      await expectLater(
        repository.deleteAsset('already-deleted'),
        throwsA(isA<Exception>()),
      );
      expect(repository.reconciliations, 1);
      repository.offline = false;
      await repository.deleteAsset('already-deleted');
      expect(repository.reconciliations, 2);
    },
  );
}
