import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';
import 'package:veil_mobile/src/core/crypto/message_padding.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/network/keys_api.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/group_sender_key_coordinator.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';

import 'support/group_fixtures.dart';

// Coordinator-level hardening against a malicious relay/directory: it must
// not graft unauthenticated attachments onto messages, or seal to / accept
// from identities the pins refuse, such as a device the server slips into a
// verified member's entry. One member the directory cannot serve must not
// cost the other members the chain either, and who our chain has reached
// must survive a restart.

/// The server: a directory the test can rewrite plus the distribution relay.
class _Server {
  final Map<String, Map<String, dynamic>> directory = <String, Map<String, dynamic>>{};
  final Map<String, List<Map<String, dynamic>>> buffered = <String, List<Map<String, dynamic>>>{};
  final List<List<String>> uploads = <List<String>>[];
  final List<List<String>> uploadedDevices = <List<String>>[];

  /// Handle -> error the directory answers with instead of an entry.
  final Map<String, VeilApiException> lookupFailures = <String, VeilApiException>{};

  /// Error the relay answers every distribution upload with, if set.
  VeilApiException? uploadFailure;

  /// The user's entry in GET /keys/:handle, listing [devices] (by default
  /// just [user]'s own device).
  void publish(TestIdentity user, {List<TestIdentity>? devices}) {
    directory[user.handle] = {
      'user': {'id': user.userId, 'handle': user.handle, 'activeDeviceId': user.deviceId},
      'devices': [for (final d in devices ?? [user]) _listing(d, isActive: d.deviceId == user.deviceId)],
    };
  }

  static Map<String, dynamic> _listing(TestIdentity device, {required bool isActive, String? signedPrekeyBundle}) => {
        'deviceId': device.deviceId,
        'identityPublicKey': device.identityPublicKey,
        'signedPrekeyBundle': signedPrekeyBundle ?? device.signedPrekeyBundle,
        'isActive': isActive,
        'oneTimePrekey': null,
      };
}

class _ServerClient extends VeilApiClient {
  _ServerClient(this.server, this.me) : super(baseUrl: 'http://localhost:3000/v1');

  final _Server server;
  final TestIdentity me;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    required String? accessToken,
    Map<String, String>? query,
  }) async {
    final handle = path.substring('/keys/'.length);
    final failure = server.lookupFailures[handle];
    if (failure != null) throw failure;
    return server.directory[handle]!;
  }

  @override
  Future<Map<String, dynamic>> distributeGroupKeys(
    String accessToken,
    String conversationId, {
    required int epoch,
    required List<Map<String, dynamic>> distributions,
  }) async {
    final failure = server.uploadFailure;
    if (failure != null) throw failure;
    server.uploads.add({for (final d in distributions) d['recipientUserId'] as String}.toList());
    server.uploadedDevices.add([for (final d in distributions) d['recipientDeviceId'] as String]);
    for (final d in distributions) {
      // Like the real relay, a re-send to the same recipient device in the
      // same epoch replaces the blob still buffered for it.
      server.buffered.putIfAbsent(d['recipientUserId'] as String, () => [])
        ..removeWhere((b) =>
            b['fromDeviceId'] == me.deviceId && b['epoch'] == epoch && b['recipientDeviceId'] == d['recipientDeviceId'])
        ..add({
          'conversationId': conversationId,
          'epoch': epoch,
          'fromUserId': me.userId,
          'fromDeviceId': me.deviceId,
          'recipientDeviceId': d['recipientDeviceId'],
          'encryptedChainKey': d['encryptedChainKey'],
          'nonce': d['nonce'],
          'version': d['version'],
        });
    }
    return {'accepted': distributions.length};
  }

  @override
  Future<Map<String, dynamic>> getGroupKeyDistributions(String accessToken, String conversationId) async => {
        'epoch': 0,
        'distributions': [
          for (final blob in server.buffered[me.userId] ?? const <Map<String, dynamic>>[])
            if (blob['recipientDeviceId'] == me.deviceId) blob,
        ],
      };
}

class _BundleCodec implements KeyBundleCodec {
  @override
  KeyBundle decodeDirectoryBundle(Map<String, dynamic> json) => KeyBundle(
        userId: json['userId'] as String,
        deviceId: json['deviceId'] as String,
        handle: json['handle'] as String,
        identityPublicKey: json['identityPublicKey'] as String,
        signedPrekeyBundle: json['signedPrekeyBundle'] as String,
      );

  @override
  List<KeyBundle> decodeDirectoryBundles(List<Map<String, dynamic>> json) =>
      json.map(decodeDirectoryBundle).toList();
}

class _Member {
  _Member(
    this.identity,
    this._server,
    this._directory,
    this._group, {
    Map<String, Map<String, dynamic>>? store,
    IdentityKeyValueBackend? pinStore,
  })  : stored = store ?? <String, Map<String, dynamic>>{},
        pinStore = pinStore ?? InMemoryIdentityKeyValueBackend() {
    final client = _ServerClient(_server, identity);
    trust = IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(this.pinStore)));
    coordinator = GroupSenderKeyCoordinator(
      engine: GroupSenderKeyEngine(persister: _persist),
      sealer: _directory.sealer(),
      apiClient: client,
      keys: KeysApi(client, _BundleCodec()),
      identityPrivateRefLoader: () async => 'ref',
      localX25519PrivateParser: (_) => identity.x25519Private,
      localEd25519SeedParser: (_) => identity.ed25519Seed,
      conversationLookup: (_) => _group,
      trustCheck: (conversationId, userId, deviceId, key) async {
        trustChecks.add('$userId/$deviceId/$key');
        if (unresolvable.contains(userId)) {
          throw const FormatException('corrupt pin record');
        }
        return !distrusted.contains(userId) && await trust.admit(conversationId, userId, deviceId, key);
      },
    );
  }

  final TestIdentity identity;
  final _Server _server;
  final IdentityDirectory _directory;
  final ConversationPreview _group;
  late final GroupSenderKeyCoordinator coordinator;

  /// This device's identity pins, the same pin policy the app runs.
  late final IdentityTrust trust;
  final IdentityKeyValueBackend pinStore;

  /// This device's secure store: the engine's last persisted snapshot per
  /// group, round-tripped through JSON as the real store does.
  final Map<String, Map<String, dynamic>> stored;
  final Set<String> distrusted = <String>{};

  /// Users whose trust check throws, like a resolver over a corrupt store.
  final Set<String> unresolvable = <String>{};
  final List<String> trustChecks = <String>[];

  Future<void> _persist(String groupId, Map<String, dynamic>? snapshot) async {
    if (snapshot == null) {
      stored.remove(groupId);
    } else {
      stored[groupId] = json.decode(json.encode(snapshot)) as Map<String, dynamic>;
    }
  }

  /// The same device after the app restarts: a new engine and coordinator
  /// that know only what the secure store restores.
  Future<_Member> restart() async {
    final next = _Member(identity, _server, _directory, _group, store: stored, pinStore: pinStore);
    await next.coordinator.restoreFromSnapshots(Map.of(stored));
    return next;
  }

  GroupSenderKey? get ownChain => coordinator.engine.exportOwnSenderKey(groupId);

  Future<void> prepareSend(ConversationPreview group) => coordinator.prepareSend(
        conversation: group,
        accessToken: 't',
        localUserId: identity.userId,
        localDeviceId: identity.deviceId,
      );

  Future<CryptoEnvelope> send(ConversationPreview group, String body, {AttachmentReference? attachment}) async {
    await prepareSend(group);
    return coordinator.encryptMessage(
      conversation: group,
      senderDeviceId: identity.deviceId,
      body: body,
      messageKind: MessageKind.text,
      attachment: attachment,
    );
  }

  Future<DecryptedMessage> read(CryptoEnvelope envelope) =>
      coordinator.decryptMessage(envelope, accessToken: 't', localUserId: identity.userId);

  Future<void> receiveRealtime(Map<String, dynamic> distribution) =>
      coordinator.handleKeyDistributionEvent(distribution, localUserId: identity.userId, accessToken: 't');

  bool holdsChainOf(TestIdentity sender) =>
      coordinator.engine.hasSenderKeyFor(groupId: groupId, senderDeviceId: sender.deviceId);
}

/// [e] with outer, server-controlled fields rewritten by the relay.
CryptoEnvelope _withOuter(CryptoEnvelope e, {AttachmentReference? attachment, MessageKind? messageKind}) =>
    CryptoEnvelope(
      version: e.version,
      conversationId: e.conversationId,
      senderDeviceId: e.senderDeviceId,
      recipientUserId: e.recipientUserId,
      ciphertext: e.ciphertext,
      nonce: e.nonce,
      messageKind: messageKind ?? e.messageKind,
      attachment: attachment ?? e.attachment,
    );

/// What the directory answers for a user with no trusted active device.
final _noActiveDevice = VeilApiException(
  'Active device bundle not found',
  code: 'active_device_not_found',
  statusCode: 404,
);

final _unavailable = VeilApiException('Service unavailable', statusCode: 503);

const _attachment = AttachmentReference(
  attachmentId: 'att-1',
  storageKey: 'blobs/att-1',
  contentType: 'image/png',
  sizeBytes: 1234,
  sha256: 'digest',
  encryptedKey: 'wrapped',
  nonce: 'att-nonce',
);

void main() {
  late _Server server;
  late IdentityDirectory directory;
  late TestIdentity aliceId;
  late TestIdentity bobId;
  late TestIdentity carolId;
  late ConversationPreview group;
  late _Member alice;
  late _Member bob;

  setUp(() async {
    server = _Server();
    directory = IdentityDirectory();
    aliceId = await TestIdentity.generate(userId: 'user-alice', deviceId: 'dev-alice', handle: 'alice');
    bobId = await TestIdentity.generate(userId: 'user-bob', deviceId: 'dev-bob', handle: 'bob');
    carolId = await TestIdentity.generate(userId: 'user-carol', deviceId: 'dev-carol', handle: 'carol');
    for (final id in [aliceId, bobId, carolId]) {
      directory.add(id);
      server.publish(id);
    }
    group = ConversationPreview(
      id: groupId,
      peerHandle: '',
      peerDisplayName: null,
      recipientBundle: const KeyBundle(
        userId: '',
        deviceId: '',
        handle: '',
        identityPublicKey: '',
        signedPrekeyBundle: '',
      ),
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 1, 1),
      type: ConversationType.group,
      members: [
        for (final id in [aliceId, bobId, carolId]) GroupMember(userId: id.userId, handle: id.handle),
      ],
      useSenderKeys: true,
      groupEpoch: 0,
    );
    alice = _Member(aliceId, server, directory, group);
    bob = _Member(bobId, server, directory, group);
  });

  test('outer attachment ignored when inner pointer absent', () async {
    final envelope = await alice.send(group, 'just text');
    final grafted = _withOuter(
      envelope,
      attachment: _attachment.copyWith(attachmentId: 'evil', storageKey: 'server/evil.bin'),
    );

    final out = await bob.read(grafted);
    expect(out.body, 'just text');
    expect(out.attachment, isNull);
  });

  test('group frames carry the 1:1 inner payload and still read older pointer forms', () async {
    final current = await bob.read(await alice.send(group, 'photo', attachment: _attachment));
    expect(current.body, 'photo');
    expect(current.attachment?.attachmentId, 'att-1');
    expect(current.attachment?.encryptedKey, 'wrapped');
    expect(current.attachment?.sizeBytes, 1234);
    // The storage key is a relay detail and is not sealed into the frame.
    expect(current.attachment?.storageKey, isEmpty);

    Future<DecryptedMessage> readLegacy(Map<String, dynamic> payload) async {
      final ct = await alice.coordinator.engine.encrypt(
        groupId: groupId,
        localDeviceId: aliceId.deviceId,
        plaintext: MessagePadding.pad(utf8.encode(json.encode(payload))),
      );
      return bob.read(CryptoEnvelope(
        version: kGroupEnvelopeVersion,
        conversationId: groupId,
        senderDeviceId: aliceId.deviceId,
        recipientUserId: '',
        ciphertext: ct.payload,
        nonce: ct.nonce,
        messageKind: MessageKind.text,
      ));
    }

    // Older group clients wrote long keys; older 1:1 clients short ones.
    final longForm = await readLegacy({
      'body': 'photo',
      'kind': 'image',
      'att': {'attachmentId': 'att-1', 'storageKey': 'blobs/att-1', 'sizeBytes': 1234, 'sha256': 'digest'},
    });
    expect(longForm.attachment?.storageKey, 'blobs/att-1');
    expect(longForm.attachment?.sizeBytes, 1234);
    final shortForm = await readLegacy({
      'body': 'photo',
      'kind': 'image',
      'att': {'id': 'att-2', 'sk': 'blobs/att-2', 'ct': 'image/jpeg', 'sz': 99, 'h': 'd', 'ek': 'k', 'n': 'n'},
    });
    expect(shortForm.messageKind, MessageKind.image);
    expect(shortForm.attachment?.attachmentId, 'att-2');
    expect(shortForm.attachment?.storageKey, 'blobs/att-2');
    expect(shortForm.attachment?.contentType, 'image/jpeg');
    expect(shortForm.attachment?.sizeBytes, 99);
  });

  test('seals once per trusted device with recipientDeviceId', () async {
    final bobTablet = await TestIdentity.generate(userId: bobId.userId, deviceId: 'dev-bob-tablet', handle: 'bob');
    directory.add(bobTablet);
    server.publish(bobId, devices: [bobId, bobTablet]);

    final envelope = await alice.send(group, 'to every device');

    expect(server.uploadedDevices, [
      [bobId.deviceId, bobTablet.deviceId, carolId.deviceId],
    ]);
    expect(server.uploads, [
      [bobId.userId, carolId.userId],
    ]);
    // Each device opens the blob addressed to it.
    final tablet = _Member(bobTablet, server, directory, group);
    expect((await bob.read(envelope)).body, 'to every device');
    expect((await tablet.read(envelope)).body, 'to every device');

    // Every member holds the chain now, so later sends upload nothing.
    await alice.prepareSend(group);
    expect(server.uploads, hasLength(1));
  });

  test('server-injected device for verified member is not sealed to and its distribution is rejected', () async {
    // alice verified bob's device out of band.
    await alice.trust.admit(groupId, bobId.userId, bobId.deviceId, bobId.identityPublicKey);
    await alice.trust.resolver.markVerified(bobId.userId, bobId.deviceId, bobId.identityPublicKey);
    // The server lists a device of its own under bob's account.
    final ghost = await TestIdentity.generate(userId: bobId.userId, deviceId: 'dev-ghost', handle: 'bob');
    directory.add(ghost);
    server.publish(bobId, devices: [bobId, ghost]);

    await alice.prepareSend(group);
    expect(server.uploadedDevices.single, [bobId.deviceId, carolId.deviceId]);
    expect(directory.resolvedBundles, isNot(contains(ghost.signedPrekeyBundle)));
    final pending = alice.trust.pendingFor(groupId)!;
    expect(pending.deviceId, ghost.deviceId);
    expect(pending.requiresReverification, isTrue);

    // The ghost's chain, signed with the ghost's identity, is refused.
    final ghostMember = _Member(ghost, server, directory, group);
    final forged = await ghostMember.send(group, 'impersonating bob');
    final blob = server.buffered[aliceId.userId]!.singleWhere((b) => b['fromDeviceId'] == ghost.deviceId);
    await alice.receiveRealtime(blob);
    expect(alice.holdsChainOf(ghost), isFalse);
    final read = await alice.read(forged);
    expect(read.status, DecryptStatus.awaitingKey);
    expect(read.body, isEmpty);
  });

  test('trustCheck false prevents sealing and rejects distribution signer', () async {
    alice.distrusted.add(bobId.userId);
    await alice.prepareSend(group);
    expect(alice.trustChecks, contains('${bobId.userId}/${bobId.deviceId}/${bobId.identityPublicKey}'));
    expect(server.uploads.expand((u) => u), isNot(contains(bobId.userId)));

    // alice accepts bob after all; bob refuses alice's identity.
    alice.distrusted.clear();
    bob.distrusted.add(aliceId.userId);
    final envelope = await alice.send(group, 'hello bob');
    final blob = server.buffered[bobId.userId]!.single;

    await bob.receiveRealtime(blob);
    expect(bob.trustChecks, contains('${aliceId.userId}/${aliceId.deviceId}/${aliceId.identityPublicKey}'));
    expect(bob.holdsChainOf(aliceId), isFalse);
    expect((await bob.read(envelope)).status, DecryptStatus.awaitingKey);

    // The trust decision was the only thing in the way.
    bob.distrusted.clear();
    await bob.receiveRealtime(blob);
    expect((await bob.read(envelope)).body, 'hello bob');
  });

  test('member whose directory lookup is 404 is skipped without blocking the others', () async {
    server.lookupFailures[carolId.handle] = _noActiveDevice;

    final envelope = await alice.send(group, 'carol has no device right now');
    expect(server.uploads, [
      [bobId.userId],
    ]);
    expect((await bob.read(envelope)).body, 'carol has no device right now');

    // carol has not been reached: each send asks again, and nothing is
    // uploaded while the directory still has no device for her.
    await alice.prepareSend(group);
    expect(server.uploads, hasLength(1));

    server.lookupFailures.clear();
    final carol = _Member(carolId, server, directory, group);
    final later = await alice.send(group, 'welcome back');
    expect(server.uploads.last, [carolId.userId]);
    expect((await carol.read(later)).body, 'welcome back');
  });

  test('a lookup failure that is not about the member fails the round for a retry', () async {
    server.lookupFailures[carolId.handle] = _unavailable;

    // Shipping a frame now would leave it unreadable for whoever was not
    // reached, so the send fails instead.
    await expectLater(alice.prepareSend(group), throwsA(isA<VeilApiException>()));
    expect(server.uploads, isEmpty);

    server.lookupFailures.clear();
    await alice.prepareSend(group);
    expect(server.uploads, [
      [bobId.userId, carolId.userId],
    ]);
  });

  test('once a member holds the chain, failing to reach the rest does not fail the send', () async {
    server.lookupFailures[carolId.handle] = _noActiveDevice;
    await alice.send(group, 'bob only');
    expect(server.uploads, [
      [bobId.userId],
    ]);

    // bob can read whatever alice sends next, so a transient failure while
    // retrying carol must not cost him the message.
    server.lookupFailures[carolId.handle] = _unavailable;
    final envelope = await alice.send(group, 'still readable by bob');
    expect(server.uploads, hasLength(1));
    expect((await bob.read(envelope)).body, 'still readable by bob');

    server.lookupFailures.clear();
    final carol = _Member(carolId, server, directory, group);
    final later = await alice.send(group, 'carol too');
    expect(server.uploads.last, [carolId.userId]);
    expect((await carol.read(later)).body, 'carol too');
  });

  test('member whose signed prekey does not verify is skipped', () async {
    // carol's entry presents a prekey her identity key never signed.
    server.directory[carolId.handle] = {
      'user': {'id': carolId.userId, 'handle': carolId.handle, 'activeDeviceId': carolId.deviceId},
      'devices': [_Server._listing(carolId, isActive: true, signedPrekeyBundle: bobId.signedPrekeyBundle)],
    };

    final envelope = await alice.send(group, 'hello bob');
    expect(server.uploads, [
      [bobId.userId],
    ]);
    expect((await bob.read(envelope)).body, 'hello bob');
  });

  test('a trust check that throws fails closed without aborting the round', () async {
    alice.unresolvable.add(carolId.userId);
    bob.unresolvable.add(aliceId.userId);

    final envelope = await alice.send(group, 'hello bob');
    expect(server.uploads, [
      [bobId.userId],
    ]);

    final blob = server.buffered[bobId.userId]!.single;
    await bob.receiveRealtime(blob);
    expect(bob.holdsChainOf(aliceId), isFalse);

    bob.unresolvable.clear();
    await bob.receiveRealtime(blob);
    expect((await bob.read(envelope)).body, 'hello bob');
  });

  test('distribution whose sender the directory cannot serve waits for a later pickup', () async {
    final envelope = await alice.send(group, 'hello bob');
    final blob = server.buffered[bobId.userId]!.single;

    server.lookupFailures[aliceId.handle] = _unavailable;
    await bob.receiveRealtime(blob);
    expect(bob.holdsChainOf(aliceId), isFalse);

    server.lookupFailures.clear();
    expect((await bob.read(envelope)).body, 'hello bob');
  });

  test('a restarted device hands its restored chain to a member it never reached', () async {
    server.lookupFailures[carolId.handle] = _noActiveDevice;
    await alice.send(group, 'before the restart');
    expect(server.uploads, [
      [bobId.userId],
    ]);

    final restarted = await alice.restart();
    expect(groupKeyBytesEqual(restarted.ownChain!.signingPublicKey, alice.ownChain!.signingPublicKey), isTrue);

    server.lookupFailures.clear();
    final carol = _Member(carolId, server, directory, group);
    final after = await restarted.send(group, 'after the restart');
    expect(server.uploads.last, [carolId.userId]);
    expect((await carol.read(after)).body, 'after the restart');

    await restarted.prepareSend(group);
    expect(server.uploads, hasLength(2));
  });

  test('a restart does not resend the chain to members who already hold it', () async {
    final first = await alice.send(group, 'sent before the restart');
    final restarted = await alice.restart();
    final second = await restarted.send(group, 'sent after the restart');
    expect(server.uploads, hasLength(1));

    // bob was offline throughout. A resend would have replaced the blob
    // buffered for him with one starting after the first frame.
    expect((await bob.read(first)).body, 'sent before the restart');
    expect((await bob.read(second)).body, 'sent after the restart');
  });

  test('a restarted device hands its chain to everyone after a distribution that threw', () async {
    server.uploadFailure = _unavailable;
    await expectLater(alice.prepareSend(group), throwsA(isA<VeilApiException>()));
    expect(server.uploads, isEmpty);
    expect(alice.stored, contains(groupId), reason: 'the chain was persisted before the upload');

    server.uploadFailure = null;
    final restarted = await alice.restart();
    expect(groupKeyBytesEqual(restarted.ownChain!.signingPublicKey, alice.ownChain!.signingPublicKey), isTrue);

    final envelope = await restarted.send(group, 'readable by everyone');
    expect(server.uploads, [
      [bobId.userId, carolId.userId],
    ]);
    final carol = _Member(carolId, server, directory, group);
    expect((await bob.read(envelope)).body, 'readable by everyone');
    expect((await carol.read(envelope)).body, 'readable by everyone');
  });

  test('an unreadable frame carries no body and ignores the outer kind', () async {
    bob.distrusted.add(aliceId.userId);
    final envelope = await alice.send(group, 'hello');

    final out = await bob.read(_withOuter(envelope, messageKind: MessageKind.system));
    expect(out.status, DecryptStatus.awaitingKey);
    expect(out.body, isEmpty);
    expect(out.messageKind, MessageKind.text);
  });
}
