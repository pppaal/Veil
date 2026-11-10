import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_session_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/features/conversations/data/group_sender_key_coordinator.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

// End-to-end (minus the network) exercise of the Sender Keys wiring: three
// members on one fake relay, real X25519/Ed25519/AES-GCM, real
// LibCryptoAdapter identities for sealing the chain-key distributions.

const groupId = 'group-1';

class _Device {
  _Device(this.handle, this.userId, this.deviceId);
  final String handle;
  final String userId;
  final String deviceId;
  late DeviceIdentityMaterial identity;
}

/// One shared relay. Each member gets a client view bound to its device.
class _Relay {
  final Map<String, _Device> devicesByHandle = {};
  int epoch = 0;
  final List<Map<String, dynamic>> sent = [];
  // key: recipientUserId → list of buffered distributions
  final Map<String, List<Map<String, dynamic>>> distributions = {};
  final List<Map<String, dynamic>> distributeCalls = [];
  int serverCounter = 0;

  Map<String, dynamic> conversationJson({List<_Device>? members}) => {
        'id': groupId,
        'type': 'group',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'members': [
          for (final d in members ?? devicesByHandle.values)
            {'userId': d.userId, 'handle': d.handle, 'displayName': d.handle},
        ],
        'lastMessage': null,
        'useSenderKeys': true,
        'currentEpoch': epoch,
      };
}

class _RelayClient extends VeilApiClient {
  _RelayClient(this.relay, this.me) : super(baseUrl: 'http://localhost:3000/v1');
  final _Relay relay;
  final _Device me;
  List<_Device>? visibleMembers;

  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async =>
      {'items': [relay.conversationJson(members: visibleMembers)], 'nextCursor': null};

  @override
  Future<Map<String, dynamic>> getMessages(String accessToken, String conversationId,
          {String? cursor, int limit = 50}) async =>
      {'items': const <Map<String, dynamic>>[], 'nextCursor': null};

  @override
  Future<Map<String, dynamic>> getKeyBundle(String handle) async {
    final d = relay.devicesByHandle[handle]!;
    final bundle = {
      'userId': d.userId,
      'deviceId': d.deviceId,
      'handle': d.handle,
      'identityPublicKey': d.identity.identityPublicKey,
      'signedPrekeyBundle': d.identity.signedPrekeyBundle,
    };
    return {
      'user': {'activeDeviceId': d.deviceId},
      'bundle': bundle,
      'deviceBundles': [bundle],
    };
  }

  @override
  Future<Map<String, dynamic>> sendMessage(String accessToken, Map<String, dynamic> body) async {
    if (body['groupEpoch'] != relay.epoch) {
      throw VeilApiException('stale', statusCode: 400, code: 'group_epoch_stale');
    }
    relay.sent.add(body);
    relay.serverCounter += 1;
    final envelope = body['envelope'] as Map<String, dynamic>;
    return {
      'message': {
        'id': 'srv-${relay.serverCounter}',
        'clientMessageId': body['clientMessageId'],
        'conversationId': body['conversationId'],
        'senderDeviceId': envelope['senderDeviceId'],
        'conversationOrder': relay.serverCounter,
        'ciphertext': envelope['ciphertext'],
        'nonce': envelope['nonce'],
        'messageType': envelope['messageType'],
        'version': envelope['version'],
        'serverReceivedAt': DateTime.utc(2026, 3, 30, 12, relay.serverCounter).toIso8601String(),
      },
      'idempotent': false,
    };
  }

  @override
  Future<Map<String, dynamic>> distributeGroupKeys(String accessToken, String conversationId,
      {required int epoch, required List<Map<String, dynamic>> distributions}) async {
    if (epoch != relay.epoch) {
      throw VeilApiException('stale', statusCode: 400, code: 'group_epoch_stale');
    }
    relay.distributeCalls.add({'from': me.handle, 'epoch': epoch, 'count': distributions.length});
    for (final d in distributions) {
      final recipient = d['recipientUserId'] as String;
      relay.distributions.putIfAbsent(recipient, () => []).add({
        'epoch': epoch,
        'fromUserId': me.userId,
        'fromDeviceId': me.deviceId,
        'encryptedChainKey': d['encryptedChainKey'],
        'nonce': d['nonce'],
        'version': d['version'],
        'createdAt': DateTime.utc(2026, 3, 30).toIso8601String(),
      });
    }
    return {'conversationId': conversationId, 'epoch': epoch, 'accepted': distributions.length, 'expiresInSeconds': 1800};
  }

  @override
  Future<Map<String, dynamic>> getGroupKeyDistributions(String accessToken, String conversationId) async {
    final mine = (relay.distributions[me.userId] ?? const [])
        .where((d) => d['epoch'] == relay.epoch)
        .toList(growable: false);
    return {'conversationId': conversationId, 'epoch': relay.epoch, 'distributions': mine};
  }
}

class _FakeRealtime extends RealtimeService {
  void Function(String event, dynamic payload)? onEvent;
  @override
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {
    this.onEvent = onEvent;
    onConnectionChanged?.call(true);
  }

  @override
  void disconnect() {}
  @override
  void emit(String event, Map<String, dynamic> payload) {}
}

class _Member {
  _Member(this.device, this.relay) {
    api = _RelayClient(relay, device);
    adapter = LibCryptoAdapter();
    final engine = GroupSenderKeyEngine();
    coordinator = GroupSenderKeyCoordinator(
      engine: engine,
      sealer: GroupSenderKeySealer(resolveRecipientPrekey: LibIdentityKeys.resolveRemoteX25519),
      apiClient: api,
      keyBundleCodec: adapter.keyBundles,
      identityPrivateRefLoader: () async => device.identity.identityPrivateKeyRef,
      localX25519PrivateParser: LibIdentityKeys.localX25519Private,
      localEd25519SeedParser: LibIdentityKeys.localEd25519Seed,
    );
    realtime = _FakeRealtime();
    controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: adapter.messaging,
      keyBundleCodec: adapter.keyBundles,
      envelopeCodec: adapter.envelopeCodec,
      sessionBootstrapper: adapter.sessions,
      realtimeService: realtime,
      cacheService: null,
      identityPrivateRefLoader: () async => device.identity.identityPrivateKeyRef,
      groupCrypto: coordinator,
    );
  }

  final _Device device;
  final _Relay relay;
  late final _RelayClient api;
  late final LibCryptoAdapter adapter;
  late final GroupSenderKeyCoordinator coordinator;
  late final _FakeRealtime realtime;
  late final VeilMessengerController controller;

  Future<void> signIn() => controller.applySession(AppSessionState(
        accessToken: 'token-${device.handle}',
        userId: device.userId,
        deviceId: device.deviceId,
        handle: device.handle,
        displayName: device.handle,
        onboardingAccepted: true,
        locked: false,
        initializing: false,
      ));

  /// Decrypt a frame the relay recorded, as the UI would.
  Future<String> read(Map<String, dynamic> sentBody) async {
    final env = adapter.envelopeCodec.decodeApiEnvelope(
      (sentBody['envelope'] as Map<String, dynamic>)..['conversationId'] = groupId,
    );
    return (await controller.decryptEnvelope(env)).body;
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late _Relay relay;
  late _Member alice;
  late _Member bob;
  late _Member carol;

  setUp(() async {
    relay = _Relay();
    final devices = [
      _Device('alice', 'user-alice', 'dev-alice'),
      _Device('bob', 'user-bob', 'dev-bob'),
      _Device('carol', 'user-carol', 'dev-carol'),
    ];
    for (final d in devices) {
      d.identity = await LibCryptoAdapter().identity.generateDeviceIdentity(d.deviceId);
      relay.devicesByHandle[d.handle] = d;
    }
    alice = _Member(devices[0], relay);
    bob = _Member(devices[1], relay);
    carol = _Member(devices[2], relay);
    for (final m in [alice, bob, carol]) {
      await m.signIn();
    }
  });

  tearDown(() {
    for (final m in [alice, bob, carol]) {
      m.controller.dispose();
    }
  });

  test('first group send distributes the chain key and others decrypt via pickup', () async {
    await alice.controller.sendText(conversationId: groupId, body: 'hello group');
    await _settle();

    expect(relay.sent, hasLength(1));
    final body = relay.sent.single;
    final envelope = body['envelope'] as Map<String, dynamic>;
    expect(envelope['version'], kGroupEnvelopeVersion);
    expect(envelope.containsKey('recipientUserId'), isFalse);
    expect(body['groupEpoch'], 0);
    // One distribution call covering bob + carol.
    expect(relay.distributeCalls, [
      {'from': 'alice', 'epoch': 0, 'count': 2},
    ]);

    // bob and carol were "offline": they fetch the buffered blob on demand.
    expect(await bob.read(body), 'hello group');
    expect(await carol.read(body), 'hello group');
    // alice reads her own frame back.
    expect(await alice.read(body), 'hello group');

    // A second send reuses the chain — no redistribution.
    await alice.controller.sendText(conversationId: groupId, body: 'second');
    await _settle();
    expect(relay.distributeCalls, hasLength(1));
    expect(await bob.read(relay.sent.last), 'second');
  });

  test('realtime distribution event installs the key without a relay fetch', () async {
    await alice.controller.sendText(conversationId: groupId, body: 'live');
    await _settle();
    final blob = relay.distributions['user-bob']!.single;
    bob.realtime.onEvent!('group.key.distribution', {
      'conversationId': groupId,
      ...blob,
    });
    await _settle();
    expect(
      bob.coordinator.engine.hasSenderKeyFor(groupId: groupId, senderDeviceId: 'dev-alice'),
      isTrue,
    );
    expect(await bob.read(relay.sent.single), 'live');
  });

  test('a stranger cannot impersonate a member in the distribution channel', () async {
    await alice.controller.sendText(conversationId: groupId, body: 'x');
    await _settle();
    final real = relay.distributions['user-bob']!.single;
    // Claim the blob came from carol's device: the directory says carol's
    // identity key is different, so the signature check fails and nothing
    // is installed.
    bob.realtime.onEvent!('group.key.distribution', {
      'conversationId': groupId,
      ...real,
      'fromUserId': 'user-carol',
      'fromDeviceId': 'dev-carol',
    });
    await _settle();
    expect(
      bob.coordinator.engine.hasSenderKeyFor(groupId: groupId, senderDeviceId: 'dev-carol'),
      isFalse,
    );
  });

  test('epoch bump re-keys: removed member is locked out, remaining members continue', () async {
    await alice.controller.sendText(conversationId: groupId, body: 'before');
    await _settle();
    expect(await carol.read(relay.sent.single), 'before');

    // Server removes carol → epoch 1. Remaining members get the event; the
    // directory listing now shows only alice + bob.
    relay.epoch = 1;
    final remaining = [alice.device, bob.device];
    alice.api.visibleMembers = remaining;
    bob.api.visibleMembers = remaining;
    for (final m in [alice, bob]) {
      m.realtime.onEvent!('group.epoch.bumped', {
        'conversationId': groupId,
        'epoch': 1,
        'reason': 'leave',
        'userId': 'user-carol',
      });
    }
    await _settle();

    // Both re-keyed and redistributed to exactly one other member.
    final epoch1Calls = relay.distributeCalls.where((c) => c['epoch'] == 1).toList();
    expect(epoch1Calls.map((c) => c['count']), everyElement(1));
    expect(epoch1Calls.map((c) => c['from']).toSet(), {'alice', 'bob'});

    await alice.controller.sendText(conversationId: groupId, body: 'after');
    await _settle();
    final after = relay.sent.last;
    expect(after['groupEpoch'], 1);
    expect(await bob.read(after), 'after');
    // carol still holds epoch-0 state only.
    expect(await carol.read(after), '[Message from a previous group epoch]');
  });

  test('legacy groups (flag off) keep the 1:1 envelope path untouched', () async {
    final legacyRelay = _Relay()
      ..devicesByHandle.addAll(relay.devicesByHandle);
    final api = _LegacyClient(legacyRelay, alice.device);
    final adapter = LibCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: adapter.messaging,
      keyBundleCodec: adapter.keyBundles,
      envelopeCodec: adapter.envelopeCodec,
      sessionBootstrapper: adapter.sessions,
      realtimeService: _FakeRealtime(),
      cacheService: null,
      groupCrypto: alice.coordinator,
    );
    addTearDown(controller.dispose);
    await controller.applySession(AppSessionState(
      accessToken: 't',
      userId: alice.device.userId,
      deviceId: alice.device.deviceId,
      handle: 'alice',
      displayName: 'alice',
      onboardingAccepted: true,
      locked: false,
      initializing: false,
    ));
    final convo = controller.conversations.single;
    expect(convo.useSenderKeys, isFalse);
    expect(convo.groupEpoch, 0);
    expect(legacyRelay.distributeCalls, isEmpty);
  });
}

class _LegacyClient extends _RelayClient {
  _LegacyClient(super.relay, super.me);
  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async {
    final json = relay.conversationJson()..['useSenderKeys'] = false;
    return {'items': [json], 'nextCursor': null};
  }
}
