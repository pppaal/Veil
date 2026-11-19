import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/security/local_data_cipher.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

const conv = 'conv-1';

// Protocol v2 and libsignal open the responder session inside decrypt, so
// the controller's own inbound bootstrap never runs for them. The session
// must still end up on the conversation, bound to the device that sent the
// frame. An engine that does not report the identity its handshake proved
// (this mock) leaves the peer's key to be pinned from the directory.
void main() {
  late FakeRelay relay;

  setUp(() {
    relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
  });

  Future<CryptoEnvelope> sealFromSelene(String body, {String conversationId = conv}) {
    return StrictMockCryptoAdapter().messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'dev-selene',
      recipientUserId: 'user-atlas',
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-atlas',
        deviceId: 'dev-atlas',
        handle: 'atlas',
        identityPublicKey: 'ik-atlas',
        signedPrekeyBundle: 'spk-atlas',
      ),
    );
  }

  Future<void> relayFromSelene(String body) async {
    relay.inject(
      senderHandle: 'selene',
      conversationId: conv,
      envelope: StrictMockCryptoAdapter().envelopeCodec.encodeApiEnvelope(await sealFromSelene(body)),
    );
  }

  test('a session the engine opens while decrypting is recorded and pinned', () async {
    await relayFromSelene('hello');
    final atlas = mockPartyController(
      relay,
      'atlas',
      adapter: StrictMockCryptoAdapter(opensSessionOnDecrypt: true),
    );
    addTearDown(atlas.dispose);
    await atlas.applySession(mockPartySession('atlas'));

    await atlas.loadConversationMessages(conv);
    ConversationSessionState? session() =>
        atlas.conversations.firstWhere((item) => item.id == conv).sessionState;
    await waitFor(() => session()?.remoteIdentityPublicKey == relay.partiesByHandle['selene']!.identity.identityPublicKey);

    expect(session()!.remoteDeviceId, 'dev-selene');
    expect(relay.clientFor('atlas').directoryLookups, {'selene': 1});

    // A reply reuses that session instead of opening a second one.
    await atlas.sendText(conversationId: conv, body: 'hi back');
    await waitFor(() => atlas.pendingCountFor(conv) == 0);
    expect(relay.clientFor('atlas').directoryLookups, {'selene': 1});
  });

  test('a session the engine opens while decrypting is in the cache once the frame is open', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final adapter = StrictMockCryptoAdapter(opensSessionOnDecrypt: true);
    final cache = DriftConversationCacheService(
      database,
      envelopeCodec: adapter.envelopeCodec,
      cipher: LocalDataCipher.forTesting('AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'),
    );
    await relayFromSelene('hello');
    final atlas = mockPartyController(relay, 'atlas', adapter: adapter, cacheService: cache);
    addTearDown(atlas.dispose);
    await atlas.applySession(mockPartySession('atlas'));
    await atlas.loadConversationMessages(conv);

    expect((await atlas.decryptMessage(atlas.messagesFor(conv).single)).isOk, isTrue);

    // What a process killed right now would find on the next start: no
    // time has passed for a debounced write.
    final cached = (await cache.readConversations()).where((item) => item.id == conv).singleOrNull;
    expect(cached?.sessionState?.remoteDeviceId, 'dev-selene');
  });

  test('no session is recorded while the engine holds none', () async {
    await relayFromSelene('hello');
    final atlas = mockPartyController(relay, 'atlas');
    addTearDown(atlas.dispose);
    await atlas.applySession(mockPartySession('atlas'));

    await atlas.loadConversationMessages(conv);
    await settle();

    expect(atlas.conversations.single.sessionState, isNull);
    expect(relay.clientFor('atlas').directoryLookups, isEmpty);
  });

  test('a session held back for an unlisted conversation is never put on a group', () async {
    final atlas = mockPartyController(
      relay,
      'atlas',
      adapter: StrictMockCryptoAdapter(opensSessionOnDecrypt: true),
    );
    addTearDown(atlas.dispose);
    await atlas.applySession(mockPartySession('atlas'));
    // Atlas first hears of the legacy group through its first frame.
    relay.addGroup('grp-legacy', ['atlas', 'selene'], useSenderKeys: false);
    final envelope = await sealFromSelene('hello group', conversationId: 'grp-legacy');

    await relay.clientFor('selene').sendMessage('token-selene', {
      'conversationId': 'grp-legacy',
      'clientMessageId': 'client-group-1',
      'envelope': StrictMockCryptoAdapter().envelopeCodec.encodeApiEnvelope(envelope),
    });
    await waitFor(
      () => atlas.conversations.any((item) => item.id == 'grp-legacy'),
      reason: 'the group was never listed',
    );
    await settle();

    expect(atlas.conversations.firstWhere((item) => item.id == 'grp-legacy').sessionState, isNull);
    expect(relay.clientFor('atlas').directoryLookups, isEmpty);
  });
}
