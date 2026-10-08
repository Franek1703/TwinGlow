import 'package:firebase_database/firebase_database.dart';
import 'pairing_service.dart';

class FirebasePairingStore implements PairingStore {
  final FirebaseDatabase database;
  FirebasePairingStore(this.database);
  @override
  Future<Object?> read(String path) async =>
      (await database.ref(path).get()).value;
  @override
  Future<Map<String, dynamic>> queryEqual(
    String path,
    String field,
    String value, {
    int? limit,
  }) async {
    Query q = database.ref(path).orderByChild(field).equalTo(value);
    if (limit != null) q = q.limitToFirst(limit);
    return pairingMap((await q.get()).value);
  }

  @override
  Stream<Object?> watch(String path, {String? field, String? equalTo}) {
    Query q = database.ref(path);
    if (field != null) q = q.orderByChild(field).equalTo(equalTo);
    return q.onValue.map((event) => event.snapshot.value);
  }

  @override
  Future<void> update(Map<String, Object?> values) =>
      database.ref().update(values);
  @override
  String newKey() => database.ref('pairing').push().key!;
}
