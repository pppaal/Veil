import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import '../support/counting_crypto_adapter.dart';
import '../support/fake_relay.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

const conv = 'conv-1';

void main() {
  test('a cached message whose content this device retired never comes back on launch', () async {
    final relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
    final crypto = CountingCryptoAdapter(StrictMockCryptoAdapter());
    KeyBundle bundleOf(String handle) =>
        crypto.keyBundles.decodeDirectoryBundle(relay.partiesByHandle[handle]!.bundleJson);
    final selene = StrictMockCryptoAdapter();
    final envelope = await selene.messaging.encryptMessage(
      conversationId: conv,
      senderDeviceId: 'dev-selene',
      recipientUserId: 'user-atlas',
      body: 'expired before the clamped copy was saved',
      messageKind: MessageKind.text,
      recipientBundle: bundleOf('atlas'),
    );
    // The relay still serves the frame, like one that sweeps late.
    final relayed = relay.inject(
      senderHandle: 'selene',
      conversationId: conv,
      envelope: selene.envelopeCodec.encodeApiEnvelope(envelope),
    );

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftConversationCacheService(database, envelopeCodec: crypto.envelopeCodec);
    // The previous run cached the message without its inner expiry and then
    // retired its content when that expiry passed.
    final cached = ChatMessage(
      id: relayed['id'] as String,
      senderDeviceId: 'dev-selene',
      sentAt: DateTime.utc(2026, 4, 1, 9),
      envelope: envelope,
    );
    await cache.storeConversations([
      ConversationPreview(
        id: conv,
        peerHandle: 'selene',
        peerDisplayName: 'selene',
        recipientBundle: bundleOf('selene'),
        lastEnvelope: envelope,
        updatedAt: DateTime.utc(2026, 4, 1, 9),
      ),
    ]);
    await cache.storeMessages(conv, [cached]);
    await cache.deleteExpired(DateTime.now(), messageKeys: [cached.id]);

    final atlas = mockPartyController(relay, 'atlas', adapter: crypto, cacheService: cache);
    addTearDown(atlas.dispose);
    await atlas.applySession(mockPartySession('atlas'));
    await atlas.loadConversationMessages(conv);

    expect(atlas.messagesFor(conv), isEmpty);
    expect(crypto.counts.decrypt, 0);
  });
}
