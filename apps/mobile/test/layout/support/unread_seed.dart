import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';

import 'layout_seed.dart';
import 'layout_world.dart';

// What the unread cases show on top of the seeded morning: messages that
// came after the first list (so the first list, which reads everything a
// new phone finds, leaves them unread), delivered as the relay delivers a
// new message, and one chat the user marked unread.

/// Priya's conversation; Mia's, Omar's.
const miaConversationId = 'conv-mia';
const omarConversationId = 'conv-omar_h';

/// The lines that arrive in Priya's, Mia's and Jonas's chats, newest last.
const priyaUnreadLines = ['the deck is done', 'sending it tonight', 'tell me if the charts look off'];
const miaUnreadLines = ['never mind, found them'];
const jonasUnreadLines = ['train is late', 'there in 20'];

/// What Sam writes in the cases that open his chat: a short run that fits
/// on one screen, and the start of a long one that does not.
const samShortRun = [
  "I'm outside",
  "the buzzer doesn't work",
  'can you come down?',
  'never mind, a neighbour let me in',
];

/// The long run: [samShortRun] then more of the same afternoon's texting,
/// [samLongRunLength] lines in all.
const samLongRunLength = 30;

List<String> samLongRun() => [
      for (var index = 0; index < samLongRunLength; index++)
        index < samShortRun.length ? samShortRun[index] : _samMore[(index - samShortRun.length) % _samMore.length],
    ];

const _samMore = [
  'ok up on 3',
  'the door is open',
  'boxes are in the hall',
  'do you want the lamp?',
  'I can take the shelf too',
  'where do the plates go',
  'kitchen or storage?',
  'found the tape',
  'the movers are early',
  'they say 20 min',
  'is the lift booked?',
  'sorry, wrong floor',
  'ok found it',
  'the key works',
];

/// Delivers [lines] from [peer] in the 1:1 with them (or in [inChat]): each
/// sealed, stored by the relay after what the first list named, and pushed
/// over the socket as message.new, one minute apart from [firstAt]. Then
/// the chat's history is read once, so every line is loaded before the
/// screen opens.
Future<void> deliverLines(
  LayoutWorld world,
  String peer,
  List<String> lines, {
  required DateTime firstAt,
  String? inChat,
}) async {
  final sealer = createDefaultCryptoAdapter();
  final conversationId = inChat ?? 'conv-$peer';
  for (final (index, body) in lines.indexed) {
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'dev-$peer',
      recipientUserId: 'user-$selfHandle',
      body: body,
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
      senderHandle: peer,
      conversationId: conversationId,
      envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    stored['serverReceivedAt'] = firstAt.add(Duration(minutes: index)).toIso8601String();
    world.relay.realtimeFor(selfHandle).deliver('message.new', Map<String, dynamic>.of(stored));
  }
  await world.messenger.loadConversationMessages(conversationId);
}

/// The Chats list of the unread cases: Priya 3, Mia 1, Jonas 2 (whose chat
/// a case mutes) and Omar's photo, which the user marked unread.
Future<void> seedUnreadChats(LayoutWorld world) async {
  await deliverLines(world, timerChatPeerHandle, jonasUnreadLines, firstAt: DateTime.utc(2026, 4, 7, 9, 50));
  await deliverLines(world, 'mia', miaUnreadLines, firstAt: DateTime.utc(2026, 4, 7, 9, 58));
  await deliverLines(world, noticeChatPeerHandle, priyaUnreadLines, firstAt: DateTime.utc(2026, 4, 7, 10, 2));
  await world.messenger.loadConversationMessages(omarConversationId);
  world.messenger.reads.markUnread(omarConversationId);
}

/// Sam's chat with [samShortRun] unread, which fits on the screen.
Future<void> seedShortUnreadRun(LayoutWorld world) =>
    deliverLines(world, peerHandle, samShortRun, firstAt: DateTime.utc(2026, 4, 7, 10, 15));

/// Sam's chat with [samLongRun] unread, which takes several screens.
Future<void> seedLongUnreadRun(LayoutWorld world) =>
    deliverLines(world, peerHandle, samLongRun(), firstAt: DateTime.utc(2026, 4, 7, 9, 49));
