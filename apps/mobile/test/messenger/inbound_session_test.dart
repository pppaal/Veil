import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

const conv = 'conv-1';

// Protocol v2 and libsignal open the responder session inside decrypt, so
// the controller's own inbound bootstrap never runs for them. The session
// must still end up on the conversation, bound to the device that sent the
// frame, with the peer's identity key pinned from the directory.
void main() {
  late FakeRelay relay;

  setUp(() {
    relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
  });

  Future<void> relayFromSelene(String body, {String senderDeviceId = 'dev-selene'}) async {
    final selene = StrictMockCryptoAdapter();
    final envelope = await selene.messaging.encryptMessage(
      conversationId: conv,
      senderDeviceId: senderDeviceId,
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
    relay.inject(
      senderHandle: 'selene',
      conversationId: conv,
      envelope: selene.envelopeCodec.encodeApiEnvelope(envelope),
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
    await waitFor(() => session()?.remoteIdentityPublicKey == 'ik-selene');

    expect(session()!.remoteDeviceId, 'dev-selene');
    expect(relay.clientFor('atlas').keyBundleFetches, {'selene': 1});

    // A reply reuses that session instead of opening a second one.
    await atlas.sendText(conversationId: conv, body: 'hi back');
    await waitFor(() => atlas.pendingCountFor(conv) == 0);
    expect(relay.clientFor('atlas').keyBundleFetches, {'selene': 1});
  });

  test('no session is recorded while the engine holds none', () async {
    await relayFromSelene('hello');
    final atlas = mockPartyController(relay, 'atlas');
    addTearDown(atlas.dispose);
    await atlas.applySession(mockPartySession('atlas'));

    await atlas.loadConversationMessages(conv);
    await settle();

    expect(atlas.conversations.single.sessionState, isNull);
    expect(relay.clientFor('atlas').keyBundleFetches, isEmpty);
  });
}
