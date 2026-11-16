import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';

import '../layout/support/layout_seed.dart';
import '../layout/support/layout_world.dart';

// "typing…" ends the moment the peer's message arrives, as in Signal and
// WhatsApp. The relay passes on at most one typing signal per 500 ms for a
// chat, so the typing.stop a peer sends right after typing.start (a short
// message sent at once) is dropped, and the dots would otherwise stay up
// for their whole 5 s under the message they announced.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  late LayoutWorld world;

  setUpAll(() async {
    identities = await LayoutIdentities.generate();
  });

  setUp(() async {
    world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
  });

  tearDown(() => world.dispose());

  String? typingInChat() => world.messenger.typingHandleFor(chatConversationId);

  // What the relay pushes to this phone.
  void push(String event, Map<String, dynamic> payload) => world.relay.realtimeFor(selfHandle).deliver(event, payload);

  void peerStartsTyping() => push('typing.start', {
        'conversationId': chatConversationId,
        'userId': 'user-$peerHandle',
        'handle': peerHandle,
      });

  // A message relayed in Sam's chat from [from], pushed to this phone as
  // message.new.
  Future<void> relayMessage(String from, String body, {MessageKind kind = MessageKind.text}) async {
    final sealer = createDefaultCryptoAdapter();
    final to = from == selfHandle ? peerHandle : selfHandle;
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: chatConversationId,
      senderDeviceId: 'dev-$from',
      recipientUserId: 'user-$to',
      body: body,
      messageKind: kind,
      recipientBundle: KeyBundle(
        userId: 'user-$to',
        deviceId: 'dev-$to',
        handle: to,
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
    );
    final stored = world.relay.inject(
      senderHandle: from,
      conversationId: chatConversationId,
      envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    push('message.new', Map<String, dynamic>.of(stored));
  }

  // Lets the router handle what was pushed.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  bool listed(String id) => world.messenger.messagesFor(chatConversationId).any((message) => message.id == id);

  test('the peer\'s message ends their typing in that chat', () async {
    peerStartsTyping();
    await settle();
    expect(typingInChat(), peerHandle, reason: 'the dots are up');

    await relayMessage(peerHandle, 'on my way');
    await settle();
    expect(listed(world.relay.conversations[chatConversationId]!.messages.last['id'] as String), isTrue);
    expect(typingInChat(), isNull, reason: 'the message they typed is in; no typing.stop came');
  });

  test('a message of this phone\'s own does not end the peer\'s typing', () async {
    peerStartsTyping();
    await settle();
    await relayMessage(selfHandle, 'see you there');
    await settle();
    expect(typingInChat(), peerHandle);
  });

  test('a reaction or a screenshot notice from the peer leaves their typing up', () async {
    peerStartsTyping();
    await settle();
    await relayMessage(peerHandle, '\u{1F44D}', kind: MessageKind.reaction);
    await relayMessage(peerHandle, screenshotNotice, kind: MessageKind.system);
    await settle();
    expect(typingInChat(), peerHandle, reason: 'neither is what they were typing');
  });

  test('a message in another chat leaves this chat\'s typing up', () async {
    peerStartsTyping();
    await settle();
    final sealer = createDefaultCryptoAdapter();
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: noticeChatConversationId,
      senderDeviceId: 'dev-$noticeChatPeerHandle',
      recipientUserId: 'user-$selfHandle',
      body: 'running late',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-$selfHandle',
        deviceId: 'dev-$selfHandle',
        handle: selfHandle,
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
    );
    final stored = world.relay.inject(
      senderHandle: noticeChatPeerHandle,
      conversationId: noticeChatConversationId,
      envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    push('message.new', Map<String, dynamic>.of(stored));
    await settle();
    expect(typingInChat(), peerHandle);
  });
}
