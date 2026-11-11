import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_session_state.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/identity_keys.dart';
import 'package:veil_mobile/src/core/network/keys_api.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/prekey_maintenance.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

/// This device's side of the directory: the prekey routes it calls.
class _Directory extends VeilApiClient {
  _Directory() : super(baseUrl: 'http://relay.invalid/v1');

  int available = 0;
  int countRequests = 0;
  final List<List<Map<String, dynamic>>> uploads = [];
  final List<String> signedPrekeyBundles = [];
  final Set<int> storedOneTimePrekeyIds = {};

  /// How many signed prekey publishes still fail, as when offline.
  int failingSignedPrekeyPuts = 0;

  /// How many requests are carried out but answered with an error, as when
  /// the connection drops before the response arrives.
  int lostAnswers = 0;

  @override
  Future<Map<String, dynamic>> getJson(String path, {required String? accessToken, Map<String, String>? query}) async {
    if (path == '/keys/me') {
      return {
        'user': {'id': 'user-me', 'handle': 'me', 'activeDeviceId': 'dev-me'},
        'devices': [
          {
            'deviceId': 'dev-me',
            'identityPublicKey': 'ik-me',
            'signedPrekeyBundle': signedPrekeyBundles.lastOrNull ?? 'none',
            'isActive': true,
            'oneTimePrekey': null,
          },
        ],
      };
    }
    expect(path, '/prekeys/count');
    countRequests += 1;
    return {'available': available};
  }

  @override
  Future<Map<String, dynamic>> postJson(String path, {required String? accessToken, Object? body}) async {
    expect(path, '/prekeys');
    final prekeys = ((body as Map<String, dynamic>)['prekeys'] as List).cast<Map<String, dynamic>>();
    uploads.add(prekeys);
    // Like the server, keys it already holds are skipped.
    available += prekeys.where((prekey) => storedOneTimePrekeyIds.add(prekey['keyId'] as int)).length;
    _answer();
    return {'uploaded': prekeys.length, 'available': available};
  }

  @override
  Future<Map<String, dynamic>> putJson(String path, {required String? accessToken, Object? body}) async {
    expect(path, '/keys/signed-prekey');
    if (failingSignedPrekeyPuts > 0) {
      failingSignedPrekeyPuts -= 1;
      throw VeilApiException('Service unavailable', statusCode: 503);
    }
    final bundle = (body as Map<String, dynamic>)['signedPrekeyBundle'] as String;
    final served = signedPrekeyBundles.lastOrNull;
    if (served != null && _spkIdOf(bundle) <= _spkIdOf(served)) {
      throw VeilApiException('spkId must increase with every rotation', code: 'validation_failed', statusCode: 400);
    }
    signedPrekeyBundles.add(bundle);
    _answer();
    return {'deviceId': 'dev-me', 'spkId': _spkIdOf(bundle)};
  }

  void _answer() {
    if (lostAnswers == 0) return;
    lostAnswers -= 1;
    throw VeilApiException('Connection reset', code: 'network_unavailable');
  }

  static int _spkIdOf(String bundle) =>
      (json.decode(utf8.decode(b64uDecode(bundle))) as Map<String, dynamic>)['spkId'] as int;
}

const _session = AppSessionState(accessToken: 'token', userId: 'user-me', deviceId: 'dev-me', handle: 'me');

/// Records every bootstrap request a controller makes.
class _RecordingSessions implements ConversationSessionBootstrapper {
  _RecordingSessions(this._inner);

  final ConversationSessionBootstrapper _inner;
  final List<SessionBootstrapRequest> requests = [];

  @override
  Future<SessionBootstrapMaterial> bootstrapSession(SessionBootstrapRequest request) {
    requests.add(request);
    return _inner.bootstrapSession(request);
  }

  @override
  Future<SessionBootstrapMaterial> bootstrapSessionFromInbound(InboundSessionBootstrapRequest request) =>
      _inner.bootstrapSessionFromInbound(request);

  @override
  bool hasSessionFor(String conversationId) => _inner.hasSessionFor(conversationId);

  @override
  Future<bool> forceRekeyNextSend(String conversationId) => _inner.forceRekeyNextSend(conversationId);
}

void main() {
  final start = DateTime.utc(2026, 11, 1, 9);
  late DateTime now;
  late _Directory directory;
  late InMemoryLocalPrekeyStore prekeyStore;
  late LibCryptoAdapter adapter;
  late String identityRef;
  late List<String> persistedRefs;
  late PrekeyMaintenance maintenance;

  Future<void> setUpDevice({String? withRef}) async {
    now = start;
    directory = _Directory();
    prekeyStore = InMemoryLocalPrekeyStore();
    adapter = LibCryptoAdapter(clock: () => now)..setLocalPrekeyStore(prekeyStore);
    identityRef = withRef ?? (await adapter.identity.generateDeviceIdentity('dev-me')).identityPrivateKeyRef;
    adapter.setLocalIdentityLoader(() async => identityRef);
    persistedRefs = [];
    maintenance = PrekeyMaintenance(
      prekeys: adapter,
      keys: KeysApi(directory, adapter.keyBundles),
      persistIdentityRef: (ref) async {
        persistedRefs.add(ref);
        identityRef = ref;
      },
      clock: () => now,
    );
  }

  test('uploads when below threshold', () async {
    await setUpDevice();
    directory.available = PrekeyMaintenance.minimumOneTimePrekeys - 1;

    await maintenance.run(_session, force: true);

    expect(directory.uploads.single, hasLength(PrekeyMaintenance.oneTimePrekeyPoolSize - 19));
    final keyIds = {for (final prekey in directory.uploads.single) prekey['keyId']};
    expect(keyIds, hasLength(directory.uploads.single.length), reason: 'ids are never reused');

    // A full enough pool is left alone.
    await maintenance.run(_session, force: true);
    expect(directory.uploads, hasLength(1));
  });

  test('rotates SPK after 7 days', () async {
    await setUpDevice();
    directory.available = 100;

    now = start.add(const Duration(days: 6, hours: 23));
    await maintenance.run(_session, force: true);
    expect(directory.signedPrekeyBundles, isEmpty);

    now = start.add(const Duration(days: 7, minutes: 1));
    await maintenance.run(_session, force: true);
    final bundle = directory.signedPrekeyBundles.single;
    final identityKey = await adapter.identity.extractIdentityPublicKeyFromPrivateRef(identityRef);
    final verified = await verifyRemoteBundle(bundle, identityKey, now: now) as PrekeyBundleV2;
    expect(verified.spkId, 2);
    expect(DateTime.fromMillisecondsSinceEpoch(verified.spkTimestampMs, isUtc: true), now);
    expect(persistedRefs, isEmpty, reason: 'a v2 identity keeps its ref');
    expect((await adapter.currentSignedPrekey())!.createdAt, now);
  });

  test('v1 bundle republished as v2 and upgraded ref persisted', () async {
    final v1Ref = _v1IdentityRef();
    await setUpDevice(withRef: v1Ref);
    directory.available = 100;
    expect(await adapter.currentSignedPrekey(), isNull);

    await maintenance.run(_session, force: true);

    final upgraded = LocalIdentity.tryParse(persistedRefs.single)!;
    expect(upgraded.version, 2);
    final identityKey = await adapter.identity.extractIdentityPublicKeyFromPrivateRef(v1Ref);
    expect(await adapter.identity.extractIdentityPublicKeyFromPrivateRef(persistedRefs.single), identityKey);
    final published = json.decode(utf8.decode(b64uDecode(directory.signedPrekeyBundles.single))) as Map<String, dynamic>;
    expect(published['v'], 2);
    expect(await verifyRemoteBundle(directory.signedPrekeyBundles.single, identityKey, now: now), isA<PrekeyBundleV2>());
  });

  test('a signed prekey publish that failed is retried by the next run', () async {
    final v1Ref = _v1IdentityRef();
    await setUpDevice(withRef: v1Ref);
    directory.available = 100;
    directory.failingSignedPrekeyPuts = 1;

    await maintenance.run(_session);
    expect(directory.signedPrekeyBundles, isEmpty);
    // The keyring already holds the v2 signed prekey and the upgraded ref.
    expect(LocalIdentity.tryParse(identityRef)!.version, 2);

    now = now.add(PrekeyMaintenance.resumeInterval);
    await maintenance.run(_session);

    final identityKey = await adapter.identity.extractIdentityPublicKeyFromPrivateRef(v1Ref);
    final published = await verifyRemoteBundle(directory.signedPrekeyBundles.single, identityKey, now: now);
    expect(published, isA<PrekeyBundleV2>());
    expect((published as PrekeyBundleV2).spkId, 1, reason: 'the signed prekey that failed to publish, not another');
    expect(persistedRefs, hasLength(1));

    // Published now: later runs leave it alone until it is a week old.
    now = now.add(PrekeyMaintenance.resumeInterval);
    await maintenance.run(_session);
    expect(directory.signedPrekeyBundles, hasLength(1));
  });

  test('the signed prekey the directory serves is kept until a successor is published', () async {
    await setUpDevice();
    directory.available = 100;
    directory.failingSignedPrekeyPuts = 2;
    Future<Set<int>> storedIds() async => {for (final prekey in await prekeyStore.loadSignedPrekeys()) prekey.keyId};

    // A week in, rotating to spkId 2 fails to publish; three weeks later
    // spkId 2 is stale and spkId 3 fails too. The directory serves spkId 1
    // throughout, so it must still answer handshakes.
    now = start.add(const Duration(days: 8));
    await maintenance.run(_session, force: true);
    now = start.add(const Duration(days: 30));
    await maintenance.run(_session, force: true);
    expect(await adapter.pruneSignedPrekeys(), 0);
    expect(await storedIds(), {1, 2, 3});

    await maintenance.run(_session, force: true);
    final identityKey = await adapter.identity.extractIdentityPublicKeyFromPrivateRef(identityRef);
    final published = await verifyRemoteBundle(directory.signedPrekeyBundles.single, identityKey, now: now);
    expect((published as PrekeyBundleV2).spkId, 3);
    expect(await adapter.publishedSignedPrekeyId(), 3);

    // The superseded ones retire two weeks after spkId 3 was published.
    now = start.add(const Duration(days: 44));
    expect(await adapter.pruneSignedPrekeys(), 0);
    now = start.add(const Duration(days: 44, hours: 1));
    expect(await adapter.pruneSignedPrekeys(), 2);
    expect(await storedIds(), {3});
  });

  test('a signed prekey stored by a publish whose answer was lost is recorded as published', () async {
    await setUpDevice();
    directory.available = 100;
    now = start.add(const Duration(days: 8));
    directory.lostAnswers = 1;

    await maintenance.run(_session, force: true);
    expect(directory.signedPrekeyBundles, hasLength(1), reason: 'the directory took it');
    expect(await adapter.publishedSignedPrekeyId(), isNull, reason: 'this device never heard so');

    // The retry is refused (spkId must increase); the directory evidently
    // serves this very bundle, so the run records it and completes.
    await maintenance.run(_session, force: true);
    expect(await adapter.publishedSignedPrekeyId(), 2);
    now = now.add(const Duration(hours: 1));
    await maintenance.run(_session);
    expect(directory.countRequests, 2, reason: 'the run completed, so the next resume is throttled');
  });

  test('a refused signed prekey the directory does not serve stays unpublished', () async {
    await setUpDevice();
    directory.available = 100;
    now = start.add(const Duration(days: 8));
    await maintenance.run(_session, force: true);
    // Another rotation the directory refuses outright.
    now = start.add(const Duration(days: 16));
    directory.signedPrekeyBundles.add(_bundleWithSpkId(directory.signedPrekeyBundles.single, 99));

    await maintenance.run(_session, force: true);
    expect(await adapter.publishedSignedPrekeyId(), 2);
  });

  test('one-time prekeys whose upload failed are uploaded again, not replaced', () async {
    await setUpDevice();
    directory.available = 0;
    directory.lostAnswers = 1;

    await maintenance.run(_session, force: true);
    final firstBatch = [for (final prekey in directory.uploads.single) prekey['keyId'] as int];
    await maintenance.run(_session, force: true);

    expect(directory.uploads, hasLength(2));
    expect([for (final prekey in directory.uploads.last) prekey['keyId']], firstBatch);
    expect(directory.available, PrekeyMaintenance.oneTimePrekeyPoolSize);
    expect(await prekeyStore.loadOneTimePrekey(firstBatch.last + 1), isNull, reason: 'nothing more was generated');
  });

  test('throttled to once per 6h', () async {
    await setUpDevice();
    directory.available = 100;

    await Future.wait([
      maintenance.run(_session),
      maintenance.run(_session),
    ]);
    expect(directory.countRequests, 1, reason: 'concurrent runs are one run');

    now = start.add(const Duration(hours: 5, minutes: 59));
    await maintenance.run(_session);
    expect(directory.countRequests, 1);

    now = start.add(const Duration(hours: 6, minutes: 1));
    await maintenance.run(_session);
    expect(directory.countRequests, 2);

    // Signing in or finishing a device transfer runs it regardless.
    await maintenance.run(_session, force: true);
    expect(directory.countRequests, 3);
  });

  test('a failed run is retried by the next one', () async {
    await setUpDevice();
    directory.available = 0;
    final failing = PrekeyMaintenance(
      prekeys: adapter,
      keys: KeysApi(_Unreachable(), adapter.keyBundles),
      persistIdentityRef: (_) async {},
      clock: () => now,
    );

    await failing.run(_session);
    await maintenance.run(_session);

    expect(directory.uploads, hasLength(1));
  });

  test('bootstrap passes claimed OPK', () async {
    final relay = FakeRelay();
    seedMockParties(relay, 'conv-1', ['atlas', 'selene']);
    relay.oneTimePrekeys['dev-selene'] = [
      const OneTimePrekey(keyId: 7, publicKey: 'opk-7'),
      const OneTimePrekey(keyId: 8, publicKey: 'opk-8'),
    ];
    final strict = StrictMockCryptoAdapter(localDeviceId: 'dev-atlas');
    final sessions = _RecordingSessions(strict.sessions);
    final atlas = mockPartyController(relay, 'atlas', adapter: _WithSessions(strict, sessions));
    addTearDown(atlas.dispose);
    await atlas.applySession(mockPartySession('atlas'));

    await atlas.sendText(conversationId: 'conv-1', body: 'first');
    await atlas.sendText(conversationId: 'conv-1', body: 'second');
    await waitFor(() => relay.conversations['conv-1']!.messages.length == 2);

    final request = sessions.requests.single;
    expect(request.remoteOneTimePrekey?.keyId, 7);
    expect(request.remoteOneTimePrekey?.publicKey, 'opk-7');
    expect(relay.claimedOneTimePrekeys['dev-selene'], [7]);
  });
}

/// A v1 identity ref, as builds before protocol v2 stored it: identity keys
/// only, no signed prekey of its own.
String _v1IdentityRef() => b64uEncode(utf8.encode(json.encode({
      'ed25519': b64uEncode(List<int>.generate(32, (i) => i + 1)),
      'x25519': b64uEncode(List<int>.generate(32, (i) => 64 + i)),
    })));

class _Unreachable extends VeilApiClient {
  _Unreachable() : super(baseUrl: 'http://relay.invalid/v1');

  @override
  Future<Map<String, dynamic>> getJson(String path, {required String? accessToken, Map<String, String>? query}) =>
      throw VeilApiException('offline', code: 'network_unavailable');
}

class _WithSessions implements CryptoAdapter {
  _WithSessions(this._inner, this.sessions);

  final CryptoAdapter _inner;

  @override
  final ConversationSessionBootstrapper sessions;

  @override
  String get adapterId => _inner.adapterId;

  @override
  DeviceIdentityProvider get identity => _inner.identity;

  @override
  DeviceAuthChallengeSigner get deviceAuth => _inner.deviceAuth;

  @override
  KeyBundleCodec get keyBundles => _inner.keyBundles;

  @override
  CryptoEnvelopeCodec get envelopeCodec => _inner.envelopeCodec;

  @override
  MessageCryptoEngine get messaging => _inner.messaging;
}

/// [bundle] claiming [spkId], as a directory that moved on would serve it.
String _bundleWithSpkId(String bundle, int spkId) {
  final fields = json.decode(utf8.decode(b64uDecode(bundle))) as Map<String, dynamic>;
  return b64uEncode(utf8.encode(json.encode({...fields, 'spkId': spkId})));
}
