import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';
import 'package:veil_mobile/src/core/crypto/message_padding.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/group_sender_key_coordinator.dart';

import 'support/group_fixtures.dart';

// Coordinator-level hardening against a malicious relay/directory: it must
// not graft unauthenticated attachments onto messages, pick devices for us,
// or seal to / accept from identities the trust check refuses.

/// The server: a directory the test can rewrite plus the distribution relay.
class _Server {
  final Map<String, Map<String, dynamic>> directory = <String, Map<String, dynamic>>{};
  final Map<String, List<Map<String, dynamic>>> buffered = <String, List<Map<String, dynamic>>>{};
  final List<List<String>> uploads = <List<String>>[];

  void publish(TestIdentity user, {List<TestIdentity>? devices, String? activeDeviceId}) {
    final listed = devices ?? [user];
    directory[user.handle] = {
      'user': {'activeDeviceId': activeDeviceId ?? user.deviceId},
      'bundle': listed.first.directoryBundle,
      'deviceBundles': [for (final d in listed) d.directoryBundle],
    };
  }
}

class _ServerClient extends VeilApiClient {
  _ServerClient(this.server, this.me) : super(baseUrl: 'http://localhost:3000/v1');

  final _Server server;
  final TestIdentity me;

  @override
  Future<Map<String, dynamic>> getKeyBundle(String handle) async => server.directory[handle]!;

  @override
  Future<Map<String, dynamic>> distributeGroupKeys(
    String accessToken,
    String conversationId, {
    required int epoch,
    required List<Map<String, dynamic>> distributions,
  }) async {
    server.uploads.add([for (final d in distributions) d['recipientUserId'] as String]);
    for (final d in distributions) {
      server.buffered.putIfAbsent(d['recipientUserId'] as String, () => []).add({
        'conversationId': conversationId,
        'epoch': epoch,
        'fromUserId': me.userId,
        'fromDeviceId': me.deviceId,
        'encryptedChainKey': d['encryptedChainKey'],
        'nonce': d['nonce'],
        'version': d['version'],
      });
    }
    return {'accepted': distributions.length};
  }

  @override
  Future<Map<String, dynamic>> getGroupKeyDistributions(String accessToken, String conversationId) async =>
      {'epoch': 0, 'distributions': server.buffered[me.userId] ?? const <Map<String, dynamic>>[]};
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
  _Member(this.identity, _Server server, IdentityDirectory directory, ConversationPreview group) {
    coordinator = GroupSenderKeyCoordinator(
      engine: GroupSenderKeyEngine(),
      sealer: directory.sealer(),
      apiClient: _ServerClient(server, identity),
      keyBundleCodec: _BundleCodec(),
      identityPrivateRefLoader: () async => 'ref',
      localX25519PrivateParser: (_) => identity.x25519Private,
      localEd25519SeedParser: (_) => identity.ed25519Seed,
      trustCheck: (userId, deviceId, key) async {
        trustChecks.add('$userId/$deviceId/$key');
        return !distrusted.contains(userId);
      },
    )..conversationLookup = (_) => group;
  }

  final TestIdentity identity;
  late final GroupSenderKeyCoordinator coordinator;
  final Set<String> distrusted = <String>{};
  final List<String> trustChecks = <String>[];

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
      coordinator.handleKeyDistributionEvent(distribution, localUserId: identity.userId);
}

CryptoEnvelope _withOuterAttachment(CryptoEnvelope e, AttachmentReference attachment) => CryptoEnvelope(
      version: e.version,
      conversationId: e.conversationId,
      senderDeviceId: e.senderDeviceId,
      recipientUserId: e.recipientUserId,
      ciphertext: e.ciphertext,
      nonce: e.nonce,
      messageKind: e.messageKind,
      attachment: attachment,
    );

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
    final grafted = _withOuterAttachment(
      envelope,
      _attachment.copyWith(attachmentId: 'evil', storageKey: 'server/evil.bin'),
    );

    final out = await bob.read(grafted);
    expect(out.body, 'just text');
    expect(out.attachment, isNull);
  });

  test('inner attachment pointer decodes from long-key and short-key forms', () async {
    final longForm = await bob.read(await alice.send(group, 'photo', attachment: _attachment));
    expect(longForm.attachment?.storageKey, 'blobs/att-1');
    expect(longForm.attachment?.sizeBytes, 1234);

    // The 1:1 adapter writes the same pointer with short keys.
    final shortPayload = json.encode({
      'body': 'photo',
      'kind': 'image',
      'att': {'id': 'att-2', 'sk': 'blobs/att-2', 'ct': 'image/jpeg', 'sz': 99, 'h': 'd', 'ek': 'k', 'n': 'n'},
    });
    final ct = await alice.coordinator.engine.encrypt(
      groupId: groupId,
      localDeviceId: aliceId.deviceId,
      plaintext: MessagePadding.pad(utf8.encode(shortPayload)),
    );
    final shortForm = await bob.read(CryptoEnvelope(
      version: kGroupEnvelopeVersion,
      conversationId: groupId,
      senderDeviceId: aliceId.deviceId,
      recipientUserId: '',
      ciphertext: ct.payload,
      nonce: ct.nonce,
      messageKind: MessageKind.text,
    ));
    expect(shortForm.messageKind, MessageKind.image);
    expect(shortForm.attachment?.attachmentId, 'att-2');
    expect(shortForm.attachment?.storageKey, 'blobs/att-2');
    expect(shortForm.attachment?.contentType, 'image/jpeg');
    expect(shortForm.attachment?.sizeBytes, 99);
  });

  test('member without active device is skipped, not sealed to first bundle', () async {
    // The directory lists only a server-injected device for bob.
    final ghost = await TestIdentity.generate(userId: bobId.userId, deviceId: 'dev-ghost', handle: 'bob');
    directory.add(ghost);
    server.publish(bobId, devices: [ghost], activeDeviceId: bobId.deviceId);

    await alice.prepareSend(group);
    expect(server.uploads, [
      [carolId.userId],
    ]);
    expect(directory.resolvedBundles, isNot(contains(ghost.signedPrekeyBundle)));

    // bob's real device shows up: the next send hands him the chain.
    server.publish(bobId);
    final envelope = await alice.send(group, 'now you can read this');
    expect(server.uploads.last, [bobId.userId]);
    expect((await bob.read(envelope)).body, 'now you can read this');

    // Nobody is pending any more, so later sends upload nothing.
    await alice.prepareSend(group);
    expect(server.uploads, hasLength(2));
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
    expect(
      bob.coordinator.engine.hasSenderKeyFor(groupId: groupId, senderDeviceId: aliceId.deviceId),
      isFalse,
    );
    expect((await bob.read(envelope)).body, '[Awaiting sender key — sync required]');

    // The trust decision was the only thing in the way.
    bob.distrusted.clear();
    await bob.receiveRealtime(blob);
    expect((await bob.read(envelope)).body, 'hello bob');
  });
}
