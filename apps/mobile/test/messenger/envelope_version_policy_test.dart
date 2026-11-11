import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/envelope_version_policy.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

const conv = 'conv-1';

/// Opens every frame it is handed, so only the controller's version rules
/// stand between a frame and the engine.
class _OpensEverything implements MessageCryptoEngine {
  _OpensEverything(this._inner);

  final MessageCryptoEngine _inner;
  final List<String> opened = [];

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) async {
    opened.add(envelope.version);
    return const DecryptedMessage(body: 'opened', messageKind: MessageKind.text);
  }

  @override
  Future<CryptoEnvelope> encryptMessage({
    required String conversationId,
    required String senderDeviceId,
    required String recipientUserId,
    required String body,
    required MessageKind messageKind,
    required KeyBundle recipientBundle,
    DateTime? expiresAt,
    AttachmentReference? attachment,
  }) =>
      _inner.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: senderDeviceId,
        recipientUserId: recipientUserId,
        body: body,
        messageKind: messageKind,
        recipientBundle: recipientBundle,
        expiresAt: expiresAt,
        attachment: attachment,
      );

  @override
  Future<AttachmentCipher> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required List<int> plaintext,
    required KeyBundle recipientBundle,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<int>> decryptAttachment({
    required AttachmentReference reference,
    required List<int> ciphertext,
    required String localIdentityPrivateRef,
  }) =>
      throw UnimplementedError();
}

CryptoEnvelope _frame(String version, {String conversationId = conv}) => CryptoEnvelope(
      version: version,
      conversationId: conversationId,
      senderDeviceId: 'dev-selene',
      recipientUserId: 'user-atlas',
      ciphertext: 'ct-$version',
      nonce: 'n',
      messageKind: MessageKind.text,
    );

void main() {
  late FakeRelay relay;
  late _OpensEverything engine;
  late SecureStorageService keystore;

  setUp(() {
    relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
    keystore = SecureStorageService(MemorySecureStore());
  });

  Future<VeilMessengerController> atlas() async {
    final strict = StrictMockCryptoAdapter(localDeviceId: 'dev-atlas');
    engine = _OpensEverything(strict.messaging);
    final controller = VeilMessengerController(
      apiClient: relay.clientFor('atlas'),
      cryptoEngine: engine,
      keyBundleCodec: strict.keyBundles,
      envelopeCodec: strict.envelopeCodec,
      sessionBootstrapper: strict.sessions,
      realtimeService: relay.realtimeFor('atlas'),
      cacheService: null,
      envelopeVersions: EnvelopeVersionPolicy(store: keystore.scoped(SecureScope.conversationPolicy)),
    );
    addTearDown(controller.dispose);
    await controller.applySession(mockPartySession('atlas'));
    return controller;
  }

  test('v1 rejected after v2 authenticated', () async {
    final controller = await atlas();
    expect((await controller.decryptEnvelope(_frame('veil-envelope-v1'))).isOk, isTrue,
        reason: 'a conversation that never saw v2 still takes v1');

    expect((await controller.decryptEnvelope(_frame('veil-envelope-v2'))).isOk, isTrue);
    for (final version in ['veil-envelope-v1', 'veil-envelope-v1-dev']) {
      final refused = await controller.decryptEnvelope(_frame(version));
      expect(refused.status, DecryptStatus.failed, reason: version);
      expect(refused.failureReason, 'downgrade_rejected');
      expect(refused.body, isEmpty);
    }
    expect(engine.opened, ['veil-envelope-v1', 'veil-envelope-v2']);

    // The pin outlives the app.
    final relaunched = await atlas();
    expect((await relaunched.decryptEnvelope(_frame('veil-envelope-v1'))).failureReason, 'downgrade_rejected');
    expect(engine.opened, isEmpty);
  });

  test('a legacy frame that opens pins nothing', () async {
    final controller = await atlas();
    final policy = EnvelopeVersionPolicy(store: keystore.scoped(SecureScope.conversationPolicy));

    await controller.decryptEnvelope(_frame('veil-envelope-v1'));

    expect(await policy.rejects(conv, 'veil-envelope-v1'), isFalse);
  });

  test('a Sender Keys group never takes a pairwise frame', () async {
    relay.addGroup('grp', ['atlas', 'selene']);
    final controller = await atlas();

    final refused = await controller.decryptEnvelope(_frame('veil-envelope-v2', conversationId: 'grp'));

    expect(refused.failureReason, 'downgrade_rejected');
    expect(engine.opened, isEmpty);
  });

  test('a pin recorded while another read is in flight is kept', () async {
    final policy = EnvelopeVersionPolicy(store: keystore.scoped(SecureScope.conversationPolicy));

    // Both start reading the empty document; the pin lands between the two.
    await Future.wait([
      policy.noteAuthenticated('conv-b', 'veil-envelope-v2'),
      policy.rejects('conv-a', 'veil-envelope-v1'),
    ]);

    expect(await policy.rejects('conv-b', 'veil-envelope-v1'), isTrue);
  });

  test('an unreadable pin document keeps every conversation off the legacy versions', () async {
    await keystore.scoped(SecureScope.conversationPolicy).write('envelope_versions.v1', '{not json');
    final policy = EnvelopeVersionPolicy(store: keystore.scoped(SecureScope.conversationPolicy));

    expect(await policy.rejects('any', 'veil-envelope-v1'), isTrue);
    expect(await policy.rejects('any', 'veil-envelope-v2'), isFalse);
  });
}
