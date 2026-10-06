import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:twin_glow/services/firebase/device_access.dart';
import 'package:twin_glow/services/firebase/pairing_service.dart';

class RestPairingStore implements PairingStore {
  final String token;
  final HttpClient client = HttpClient();
  int key = 0;
  RestPairingStore(this.token);
  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final host = Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST']!;
    final uri = Uri.http(host, '/$path.json', {
      'ns': 'demo-twinglow',
      if (token != 'owner') 'auth': token,
      ...?query,
    });
    final r = await client.openUrl(method, uri);
    if (token == 'owner') {
      r.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    }
    if (body != null) {
      r.headers.contentType = ContentType.json;
      r.write(jsonEncode(body));
    }
    final response = await r.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 400) {
      throw FirebaseException(
        plugin: 'database',
        code: response.statusCode == 401
            ? 'permission-denied'
            : 'http-${response.statusCode}',
        message: text,
      );
    }
    return jsonDecode(text);
  }

  @override
  Future<Object?> read(String path) => request('GET', path);
  @override
  Future<Map<String, dynamic>> queryEqual(
    String path,
    String field,
    String value, {
    int? limit,
  }) async => pairingMap(
    await request(
      'GET',
      path,
      query: {
        'orderBy': jsonEncode(field),
        'equalTo': jsonEncode(value),
        if (limit != null) 'limitToFirst': '$limit',
      },
    ),
  );
  @override
  Future<void> update(Map<String, Object?> values) async {
    await request('PATCH', '', body: values);
  }

  @override
  String newKey() => 'dart-${DateTime.now().microsecondsSinceEpoch}-${++key}';
  @override
  Stream<Object?> watch(String path, {String? field, String? equalTo}) =>
      Stream.fromFuture(
        field == null ? read(path) : queryEqual(path, field, equalTo!),
      );
}

Future<Map<String, dynamic>> signup(String email) async {
  final client = HttpClient();
  try {
    final r = await client.postUrl(
      Uri.http(
        Platform.environment['FIREBASE_AUTH_EMULATOR_HOST']!,
        '/identitytoolkit.googleapis.com/v1/accounts:signUp',
        {'key': 'fake'},
      ),
    );
    r.headers.contentType = ContentType.json;
    r.write(
      jsonEncode({
        'email': email,
        'password': 'testing1234',
        'returnSecureToken': true,
      }),
    );
    final response = await r.close();
    return pairingMap(jsonDecode(await utf8.decoder.bind(response).join()));
  } finally {
    client.close(force: true);
  }
}

void main() {
  test(
    'production PairingService creates, retries, accepts, rejects and unpairs under real rules',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final alice = await signup('alice$suffix@example.com'),
          bob = await signup('bob$suffix@example.com');
      final as = RestPairingStore(alice['idToken'] as String),
          bs = RestPairingStore(bob['idToken'] as String),
          admin = RestPairingStore('owner');
      addTearDown(() {
        as.client.close(force: true);
        bs.client.close(force: true);
        admin.client.close(force: true);
      });
      final au = alice['localId'] as String, bu = bob['localId'] as String;
      await admin.request(
        'PUT',
        '',
        body: {
          'deviceAccess': {
            'A': {'authUid': 'auth-A', 'ownerUid': au, 'enabled': true},
            'A2': {'authUid': 'auth-A2', 'ownerUid': au, 'enabled': true},
            'B': {'authUid': 'auth-B', 'ownerUid': bu, 'enabled': true},
          },
        },
      );
      final owned = await loadOwnedDeviceMappings<String, String>(
        mappings: ['legacy', 'A', 'B'],
        userId: au,
        deviceId: (id) => id,
        readAccess: (id) => as.read('deviceAccess/$id'),
        load: (id) async => id,
      );
      expect(owned, ['A']);
      final a = PairingService(as, au, 'alice$suffix@example.com'),
          b = PairingService(bs, bu, 'bob$suffix@example.com');
      await a.ensureProfile();
      await b.ensureProfile();
      await a.sendInvite('BOB$suffix@EXAMPLE.COM', 'A');
      var invites = await b.watchInvites(true).first;
      expect(invites.single.fromDeviceId, 'A');
      final id = invites.single.id;
      await a.sendInvite('bob$suffix@example.com', 'A');
      expect((await b.watchInvites(true).first).length, 1);
      await expectLater(
        a.sendInvite('bob$suffix@example.com', 'A2'),
        throwsStateError,
      );
      await expectLater(a.acceptInvite(id, 'A'), throwsStateError);
      await b.acceptInvite(id, 'B');
      await b.acceptInvite(id, 'B');
      final ap = await a.getPairing(), bp = await b.getPairing();
      expect(ap.pairId, bp.pairId);
      expect(ap.partnerDeviceId, 'B');
      expect(bp.partnerDeviceId, 'A');
      await a.unpair();
      expect((await b.getPairing()).isPaired, false);
      expect((await admin.read('config/B/pair')), null);
      await b.sendInvite('alice$suffix@example.com', 'B');
      invites = await a.watchInvites(true).first;
      await a.resolveInvite(invites.single.id, 'rejected');
      expect((await b.getPairing()).isPaired, false);
      await b.sendInvite('alice$suffix@example.com', 'B');
      invites = await a.watchInvites(true).first;
      await a.acceptInvite(invites.firstWhere((i) => i.isPending).id, 'A');
      expect((await a.getPairing()).deviceId, 'A');
      await b.unpair();
      expect((await a.getPairing()).isPaired, false);
    },
    skip: Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST'] == null
        ? 'Run firebase npm test to exercise security rules'
        : false,
  );
}
