import 'package:flutter/widgets.dart' show Locale;
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/in_memory_message_content_store.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../../support/fake_relay.dart';
import 'layout_world.dart';

// What the layout cases show: the chats of an ordinary Tuesday morning,
// April 7, 2026, with the names and the short lines of people texting, seen
// at [layoutNow], a little after the last of them.
// Sam's chat is the one most cases open; its history from Thursday
// evening holds the long message and the long link, above last night's
// short lines and so off the first screen at every size, where a person
// scrolls up to them (the chat-room-history case). Priya's
// chat holds the one notice from the other side, Jonas's the disappearing
// timer, Lena's nothing yet, and the group the cases that ask for one.
// Then contacts.

/// Peers by handle, with the nickname alex gave each on this phone
/// (ContactNicknames, which LayoutWorld writes): the relay keeps no names,
/// and lists members and contacts by handle alone. One of them has no
/// nickname and is shown by handle; one name is long enough to overflow a
/// row. A person's avatar colour comes from their handle (VeilAvatar), so
/// the handles are picked for rows that sit next to each other, in Chats,
/// in Contacts and in the store's Chats shot, to differ in colour: Sam
/// ochre, Priya slate blue, Jonas purple, Alexandra and tom_walsh olive,
/// Omar purple, Mia rose, Lena ochre, and no two neighbours alike.
const peerNames = <String, String?>{
  peerHandle: 'Sam Rivera',
  noticeChatPeerHandle: 'Priya Nair',
  timerChatPeerHandle: 'Jonas Weber',
  'alexandra': 'Alexandra Montgomery-Whitfield',
  'mia': 'Mia Chen',
  _omar: 'Omar Haddad',
  'tom_walsh': null,
  emptyChatPeerHandle: 'Lena Fischer',
};

/// Omar's handle: in the group, and with a chat of his own.
const _omar = 'omar_h';

/// The peer whose chat holds a system notice, and that chat.
const noticeChatPeerHandle = 'priya';
const noticeChatConversationId = 'conv-$noticeChatPeerHandle';

/// The notice in that chat: Priya took a screenshot, and her phone said so
/// under her handle.
const screenshotNotice = '@$noticeChatPeerHandle took a screenshot';

/// The message of Sam's that the legacy case shows as sent from an older
/// app: his first of the morning.
const legacyMessageBody = 'did the lease come through?';

/// The host of the long link in Sam's history, for the case that looks for
/// it.
const longLinkHost = 'rentals.example.com';

/// The newest message of Sam's chat (his) and the newest of ours there, the
/// newest of Jonas's chat (ours) and the newest of the group (Omar's).
const latestChatLine = 'perfect. see you saturday';
const latestOwnChatLine = 'door code is 4417';
const latestTimerChatLine = 'see you at 9';
const latestGroupLine = 'I can bring the van after 6';

void seedParties(FakeRelay relay, LayoutIdentities identities) {
  relay.addParty(RelayParty(
    handle: selfHandle,
    userId: 'user-$selfHandle',
    deviceId: 'dev-$selfHandle',
    identity: identities.self,
  ));
  for (final handle in peerNames.keys) {
    relay.addParty(RelayParty(
      handle: handle,
      userId: 'user-$handle',
      deviceId: 'dev-$handle',
      // One real key is enough for every peer: only the chat's peer is
      // ever compared, and no two peers are compared with each other.
      identity: identities.peer,
    ));
  }
}

/// What the phone's clock reads in every case and every store shot
/// (wallClockProvider): 10:20 that Tuesday, a few minutes after the last
/// line of the morning. So the morning's chats show their times, Mia's
/// "Yesterday" and tom_walsh's "Sat", and Sam's chat says "Yesterday" and
/// "Today" over its days, on any day the gate runs.
final DateTime layoutNow = DateTime.utc(2026, 4, 7, 10, 20);

/// When a line was sent: April [day], 2026, at [hour]:[minute] in the
/// gate's time zone (UTC), so the list and the bubbles read like a real
/// morning.
class _At {
  const _At(this.hour, this.minute, {this.day = 7});

  final int day;
  final int hour;
  final int minute;

  DateTime get time => DateTime.utc(2026, 4, day, hour, minute);
}

class _Line {
  const _Line(
    this.at,
    this.mine,
    this.body, {
    this.kind = MessageKind.text,
    this.attachment = false,
    this.expires = false,
    this.from,
  });

  final _At at;
  final bool mine;
  final String body;
  final MessageKind kind;
  final bool attachment;

  /// Sent to disappear a day later.
  final bool expires;

  /// Who of a group wrote it, when it is not this device's user.
  final String? from;
}

// Sam's chat. Thursday evening: the long message and the long link, as a
// person writes them. They sit above last night's lines, so the first
// screen of the chat starts on ordinary bubbles at every size.
const _samsThursday = <_Line>[
  _Line(
    _At(21, 2, day: 2),
    false,
    'ok so the landlord wants two months up front and the sublet clause changed again. '
    "can you read section 7 before we sign? I really don't want to argue about it later",
  ),
  _Line(_At(21, 5, day: 2), true, 'will read it this weekend'),
  _Line(
    _At(21, 6, day: 2),
    false,
    'this is the place btw https://$longLinkHost/berlin/kreuzberg/two-room-flat-with-balcony-and-courtyard-view-4417',
  ),
];

// Last night: section 7 read, the signing set for the morning, the van.
// Enough short lines that even the tallest case, the tablet's, opens on
// them and not on Thursday's.
const _samsEvening = <_Line>[
  _Line(_At(18, 52, day: 6), true, 'read section 7 finally'),
  _Line(_At(18, 52, day: 6), true, 'looks fine to me'),
  _Line(_At(18, 55, day: 6), false, 'great'),
  _Line(_At(18, 56, day: 6), false, "can you sign it in the morning? I'm at work till 6"),
  _Line(_At(19, 1, day: 6), true, 'sure, first thing'),
  _Line(_At(19, 2, day: 6), false, "you're the best"),
  _Line(_At(19, 30, day: 6), false, 'do we still need a van?'),
  _Line(_At(19, 34, day: 6), true, 'omar said he can bring his'),
  _Line(_At(19, 35, day: 6), true, 'after 6 though'),
  _Line(_At(19, 35, day: 6), false, 'works for me'),
  _Line(_At(19, 41, day: 6), false, "I'll ask the movers about the 14th"),
  _Line(_At(19, 44, day: 6), true, 'ok'),
];

// The morning: short lines, a file, a disappearing message.
const _samsMorning = <_Line>[
  _Line(_At(8, 49), false, legacyMessageBody),
  _Line(_At(8, 51), true, 'yes, just signed it'),
  _Line(_At(8, 52), true, 'lease-signed.pdf', kind: MessageKind.file, attachment: true),
  _Line(_At(9, 3), false, 'got it, thanks'),
  _Line(_At(9, 10), false, 'they moved move-in to the 14th'),
  _Line(_At(9, 17), true, 'even better'),
];

// How the morning ends: the disappearing message and Sam's last word. Where
// his safety number changed instead, the chat ends on the line that says
// so (its text is the phone's own, filled in by seedConversations) and two
// messages of ours after it, which the warnings cases show as not sent.
const _samsEnd = <_Line>[
  _Line(_At(9, 38), true, latestOwnChatLine, expires: true),
  _Line(_At(9, 45), false, latestChatLine),
];
const _samsKeyChange = <_Line>[
  _Line(_At(9, 30), true, '', kind: MessageKind.system),
  _Line(_At(9, 38), true, latestOwnChatLine, expires: true),
  _Line(_At(9, 40), true, "call me when you're there"),
];

const _chat = [..._samsThursday, ..._samsEvening, ..._samsMorning, ..._samsEnd];

// Sam's chat as the account-hold cases list it: under @sam, but with
// another account than the one this phone talked to, so it is not the same
// conversation and holds nothing of Sam's history. All it has is what that
// account sent, which stays locked until the user confirms the account.
const _heldAccountLines = <_Line>[
  _Line(_At(9, 52), false, 'hey, new phone. this is sam'),
  _Line(_At(9, 53), false, 'can you send me the address again?'),
];

/// How many messages the held conversation of the account-hold cases holds.
int get heldAccountLineCount => _heldAccountLines.length;

/// How many messages the chat's conversation holds.
int get chatLineCount => _chat.length;

// Every other chat, oldest first. Omar sent a photo and Alexandra a voice
// message, neither with words; Lena's chat has no message yet. tom_walsh
// last wrote on Saturday and Mia last night, so the list has older days
// under the morning's times.
const _others = <String, List<_Line>>{
  emptyChatPeerHandle: [],
  'tom_walsh': [_Line(_At(18, 40, day: 4), true, "what's the address again?")],
  'mia': [_Line(_At(20, 15, day: 6), false, 'can you send the photos from saturday?')],
  _omar: [_Line(_At(8, 14), false, '', kind: MessageKind.image, attachment: true)],
  'alexandra': [_Line(_At(8, 28), false, '', kind: MessageKind.voice, attachment: true)],
  timerChatPeerHandle: [
    _Line(_At(8, 30), true, 'You set disappearing messages to 1 day', kind: MessageKind.system),
    _Line(_At(8, 35), true, latestTimerChatLine, expires: true),
  ],
  noticeChatPeerHandle: [
    _Line(_At(8, 31), false, 'is the deck final?'),
    _Line(_At(8, 33), true, 'almost, one more pass tonight'),
    _Line(_At(8, 36), false, screenshotNotice, kind: MessageKind.system),
    _Line(_At(8, 42), false, "I'll bring the slides tomorrow"),
  ],
};

/// The group of the group cases: this user and three of the peers, in a
/// legacy group (frames through the pairwise engine, like every 1:1 here).
const groupConversationId = 'conv-group';
const groupMemberHandles = [peerHandle, noticeChatPeerHandle, _omar];

/// The group's name, as its creator typed it in New group.
const groupName = 'Moving day';

const _group = <_Line>[
  _Line(_At(9, 52), false, 'movers can do the 14th or 16th', from: peerHandle),
  _Line(_At(9, 59), false, '14th works for me', from: noticeChatPeerHandle),
  _Line(_At(10, 6), true, "14th then, I'll book the lift"),
  _Line(_At(10, 13), false, latestGroupLine, from: _omar),
];

/// How many messages the group's conversation holds.
int get groupLineCount => _group.length;

/// Fills the relay with the conversations above and stores the content of
/// this device's own messages, which no device can decrypt back. With
/// [withGroup] the newest conversation is the group. With [keyChange]
/// Sam's chat ends on the change of his safety number. With [heldAccount]
/// the chat listed under @sam is another account's, and holds only what
/// that account sent.
Future<void> seedConversations(
  FakeRelay relay,
  LayoutMemoryCache cache, {
  bool withGroup = false,
  bool keyChange = false,
  bool heldAccount = false,
}) async {
  final sealer = createDefaultCryptoAdapter();
  // The lines are dated April; what disappears must still be there today.
  final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 23));
  final keyChangeNotice = lookupAppLocalizations(const Locale('en')).chatNoticeIdentityChanged;

  Future<void> send(String conversationId, String peer, _Line line) async {
    final sender = line.mine ? selfHandle : peer;
    final recipient = line.mine ? peer : selfHandle;
    final body = line.kind == MessageKind.system && line.body.isEmpty ? keyChangeNotice : line.body;
    final attachment = line.attachment ? _attachmentOf(line.kind) : null;
    final expiry = line.expires ? expiresAt : null;
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'dev-$sender',
      recipientUserId: 'user-$recipient',
      body: body,
      messageKind: line.kind,
      recipientBundle: KeyBundle(
        userId: 'user-$recipient',
        deviceId: 'dev-$recipient',
        handle: recipient,
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
      expiresAt: expiry,
      attachment: attachment,
    );
    final stored = relay.inject(
      senderHandle: sender,
      conversationId: conversationId,
      envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    final sentAt = line.at.time;
    stored['serverReceivedAt'] = sentAt.toIso8601String();
    if (line.kind == MessageKind.text && body.isNotEmpty && !line.attachment) {
      cache.archive.add(MessageSearchResult(
        conversationId: conversationId,
        messageId: stored['id'] as String,
        peerHandle: peer,
        // The cache has no name to give: the relay sent none.
        peerDisplayName: null,
        sentAt: sentAt,
        messageKind: line.kind,
        isMine: line.mine,
        bodySnippet: body,
        conversationOrder: stored['conversationOrder'] as int?,
        // As the phone's index keeps it: a group's hit says who wrote it.
        senderDeviceId: 'dev-$sender',
      ));
    }
    if (!line.mine) return;
    stored['deliveredAt'] = sentAt.add(const Duration(seconds: 2)).toIso8601String();
    await cache.put(MessageContentRecord(
      messageKey: stored['id'] as String,
      conversationId: conversationId,
      serverMessageId: stored['id'] as String,
      senderDeviceId: 'dev-$selfHandle',
      body: body,
      kind: line.kind,
      attachment: attachment,
      innerExpiresAt: expiry,
      status: MessageContentStatus.ok,
      createdAt: sentAt,
      updatedAt: sentAt,
    ));
  }

  // A 1:1 and its lines. The other side read every message of ours that
  // they answered; the ones after their last word are delivered.
  Future<void> seedDirect(String peer, List<_Line> lines) async {
    final conversationId = 'conv-$peer';
    relay.addDirect(conversationId, selfHandle, peer);
    for (final line in lines) {
      await send(conversationId, peer, line);
    }
    final messages = relay.conversations[conversationId]!.messages;
    final lastAnswer = messages.lastIndexWhere((message) =>
        message['senderDeviceId'] != 'dev-$selfHandle' && message['messageType'] != MessageKind.system.name);
    for (final message in messages.take(lastAnswer + 1)) {
      if (message['deliveredAt'] != null) message['readAt'] = message['deliveredAt'];
    }
  }

  for (final MapEntry(key: peer, value: lines) in _others.entries) {
    await seedDirect(peer, lines);
  }
  await seedDirect(
    peerHandle,
    heldAccount
        ? _heldAccountLines
        : [..._samsThursday, ..._samsEvening, ..._samsMorning, ...keyChange ? _samsKeyChange : _samsEnd],
  );
  if (!withGroup) return;
  relay.addGroup(groupConversationId, [selfHandle, ...groupMemberHandles], useSenderKeys: false, name: groupName);
  for (final line in _group) {
    await send(groupConversationId, line.from ?? peerHandle, line);
  }
}

// What each message with an attachment carries, by its kind: the signed
// lease (a PDF), Omar's photo and Alexandra's voice message. This build
// opens none of them, so each draws the "Can't open in this version" card.
AttachmentReference _attachmentOf(MessageKind kind) => switch (kind) {
      MessageKind.image => const AttachmentReference(
          attachmentId: '2b7e4c1a-9d3f-4e6b-8a5c-1f0e2d3c4b5a',
          storageKey: 'attachments/2b7e4c1a/blob',
          contentType: 'image/jpeg',
          sizeBytes: 1887437,
          sha256: 'sha',
          encryptedKey: 'key',
          nonce: 'nonce',
        ),
      MessageKind.voice => const AttachmentReference(
          attachmentId: '9c4d2e1f-7a6b-4c5d-9e8f-3a2b1c0d4e5f',
          storageKey: 'attachments/9c4d2e1f/blob',
          contentType: 'audio/mp4',
          sizeBytes: 57344,
          sha256: 'sha',
          encryptedKey: 'key',
          nonce: 'nonce',
        ),
      _ => const AttachmentReference(
          attachmentId: '6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f',
          storageKey: 'attachments/6f1c2d3e/blob',
          contentType: 'application/pdf',
          sizeBytes: 2411724,
          sha256: 'sha',
          encryptedKey: 'key',
          nonce: 'nonce',
        ),
    };

const _transferSessionId = layoutTransferSessionId;

/// The relay's ids for a move, shaped as production's (randomUUID).
const layoutTransferSessionId = '8b6f0c1e-2d3a-4f5b-9c7d-1e2f3a4b5c6d';
const layoutClaimId = '3f2b9c7e-5a14-4d0b-9e2f-8c61a7d4b250';

/// A claimant fingerprint as the relay writes it: SHA-256 in 16 groups of 4.
const layoutClaimFingerprint = '9f2c 41ab 07de 5c33 e18a 6b40 d2f7 0c95 7a1e 33b8 c604 f5d9 28e1 b07c 4d6a 91f3';

// The relay's transfer token is randomUUID() too.
const _transferToken = 'c47d2e19-8a3b-4f60-b915-2e7a0d6c3f84';

/// What a case types into a search field: a part of two names (Sam Rivera,
/// Priya Nair) and of two messages (Priya's last, "I'll bring the slides
/// tomorrow", and one of last night's in Sam's chat), and a word of two of Sam's messages (his first of the
/// morning and the name of the file).
const conversationSearchQuery = 'ri';
const chatSearchQuery = 'lease';

/// The body of message [number] of a history made by [seedHistory].
String historyLine(int number) => 'History line $number';

/// Adds [count] one-line messages from [peer] to the conversation with
/// them, oldest first, and returns their ids: a history several screens
/// long, of which a chat builds only the part around what it shows.
Future<List<String>> seedHistory(FakeRelay relay, {required String peer, required int count}) async {
  final sealer = createDefaultCryptoAdapter();
  final ids = <String>[];
  for (var number = 1; number <= count; number++) {
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: 'conv-$peer',
      senderDeviceId: 'dev-$peer',
      recipientUserId: 'user-$selfHandle',
      body: historyLine(number),
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-$selfHandle',
        deviceId: 'dev-$selfHandle',
        handle: selfHandle,
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
    );
    final stored = relay.inject(
      senderHandle: peer,
      conversationId: 'conv-$peer',
      envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    ids.add(stored['id'] as String);
  }
  return ids;
}

/// The relay as alex's device reaches it, with the routes the screens
/// outside the messenger call: contacts, signing out and the old-device
/// half of a transfer.
class LayoutRelayClient extends FakeRelayClient {
  LayoutRelayClient(super.relay, super.me);

  /// The disappearing timer of each conversation that has one, in seconds,
  /// as the relay keeps it: seeded for one conversation, set by the chat.
  final Map<String, int?> timers = {timerChatConversationId: 86400};

  @override
  Future<Map<String, dynamic>> setDisappearingTimer(String accessToken, String conversationId, int? seconds) async {
    timers[conversationId] = seconds;
    return const {};
  }

  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async {
    final response = await super.getConversations(accessToken);
    return {
      ...response,
      'items': [
        for (final conversation in (response['items'] as List).cast<Map<String, dynamic>>())
          {
            ...conversation,
            if (timers.containsKey(conversation['id'])) 'disappearingTimerSeconds': timers[conversation['id']],
          },
      ],
    };
  }

  // What the contacts tab, the start screens and Sign out ask the relay to
  // change, kept for the test that asked. A handle the relay has no
  // party for is refused, as a real relay refuses it.
  final List<String> addedContacts = [];
  final Set<String> removedContacts = {};
  final List<Map<String, dynamic>> createdGroups = [];
  final List<String> revokedDevices = [];

  void _requireParty(String handle) {
    if (!relay.partiesByHandle.containsKey(handle)) throw Exception('Request failed: HTTP 404');
  }

  @override
  Future<List<dynamic>> getContacts(String accessToken) async => [
        for (final handle in [...peerNames.keys, ...addedContacts.where((added) => !peerNames.containsKey(added))])
          if (!removedContacts.contains(handle))
            // What the relay keeps of a contact (ContactSummary): no name.
            <String, dynamic>{
              'handle': handle,
              'addedAt': DateTime.utc(2026, 3, 2).toIso8601String(),
            },
      ];

  @override
  Future<Map<String, dynamic>> addContact(String accessToken, Map<String, dynamic> body) async {
    // Looked up and kept in lower case, as ContactsService does.
    final handle = (body['handle'] as String).toLowerCase();
    _requireParty(handle);
    addedContacts.add(handle);
    removedContacts.remove(handle);
    return {'handle': handle};
  }

  @override
  Future<Map<String, dynamic>> removeContact(String accessToken, String handle) async {
    removedContacts.add(handle);
    return const {};
  }

  @override
  Future<Map<String, dynamic>> createDirectConversation(String accessToken, String peerHandle) async {
    _requireParty(peerHandle);
    final existing = relay.conversations.values
        .where((conversation) =>
            conversation.type == 'direct' &&
            conversation.memberHandles.contains(me.handle) &&
            conversation.memberHandles.contains(peerHandle))
        .firstOrNull;
    final conversation = existing ?? relay.addDirect('conv-$peerHandle', me.handle, peerHandle);
    return {
      'conversation': {'id': conversation.id},
    };
  }

  @override
  Future<Map<String, dynamic>> createGroup(String accessToken, Map<String, dynamic> body) async {
    final handles = (body['memberHandles'] as List<dynamic>? ?? const <dynamic>[]).cast<String>();
    handles.forEach(_requireParty);
    createdGroups.add(Map<String, dynamic>.of(body));
    final group = relay.addGroup('conv-new-group-${createdGroups.length}', [me.handle, ...handles],
        useSenderKeys: false, name: body['name'] as String);
    return {
      'conversation': {'id': group.id},
    };
  }

  @override
  Future<Map<String, dynamic>> revokeDevice(String accessToken, String deviceId, {Map<String, String>? proof}) async {
    revokedDevices.add(deviceId);
    return const {};
  }

  /// What the next step-up challenge (the first step of Sign out and
  /// Delete account) is refused with; unset, it goes to the network, which
  /// a test does not reach.
  Object? challengeError;

  @override
  Future<Map<String, dynamic>> challenge(Map<String, dynamic> body) {
    final error = challengeError;
    if (error != null) throw error;
    return super.challenge(body);
  }

  @override
  Future<Map<String, dynamic>> logoutAuth(String accessToken, {String? refreshToken}) async => const {};

  @override
  Future<Map<String, dynamic>> initTransfer(String accessToken, String deviceId) async => {
        'sessionId': _transferSessionId,
        'transferToken': _transferToken,
        'expiresAt': DateTime.now().toUtc().add(const Duration(minutes: 4, seconds: 30)).toIso8601String(),
      };
}

/// The device's cache as a map: stored message content (this device's own
/// messages are shown from it) and nothing else kept between launches.
class LayoutMemoryCache implements ConversationCacheService, MessageContentStore {
  final InMemoryMessageContentStore _contents = InMemoryMessageContentStore();

  /// What a search of the archive finds, whatever the query, when a test
  /// names the hits it is about.
  List<MessageSearchResult> archiveHits = const <MessageSearchResult>[];

  /// Every seeded line with words, as the archive a phone that opened every
  /// chat would hold (seedConversations fills it).
  final List<MessageSearchResult> archive = [];

  /// Whether a search with no [archiveHits] looks through [archive] for the
  /// query, as the phone's own index does; off, it finds nothing.
  bool searchesArchive = false;

  @override
  Future<void> put(MessageContentRecord record) => _contents.put(record);

  @override
  Future<MessageContentRecord?> get(String messageKey) => _contents.get(messageKey);

  @override
  Future<Map<String, MessageContentRecord>> getMany(Iterable<String> messageKeys) => _contents.getMany(messageKeys);

  @override
  Future<Map<String, DateTime>> innerExpiries(Iterable<String> messageKeys) => _contents.innerExpiries(messageKeys);

  @override
  Future<void> rekeyLocalToServer({required String clientMessageId, required String serverMessageId}) =>
      _contents.rekeyLocalToServer(clientMessageId: clientMessageId, serverMessageId: serverMessageId);

  @override
  Future<void> deleteConversation(String conversationId) => _contents.deleteConversation(conversationId);

  @override
  Future<void> deleteExpired(DateTime now, {Iterable<String> messageKeys = const []}) =>
      _contents.deleteExpired(now, messageKeys: messageKeys);

  @override
  Future<Set<String>> retiredAmong(Iterable<String> messageKeys) => _contents.retiredAmong(messageKeys);

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> purgeExpiredMessages({DateTime? now}) async {}

  @override
  Future<List<ConversationPreview>> readConversations() async => const [];

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async => const [];

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async => const [];

  @override
  Future<ConversationPagingState> readPagingState(String conversationId) async => const ConversationPagingState();

  @override
  Future<void> removePendingMessage(String clientMessageId) async {}

  @override
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) async {}

  @override
  Future<List<String>> searchCachedMessageIds({required String conversationId, required String query}) async =>
      const [];

  @override
  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
    required String currentDeviceId,
  }) async {
    if (archiveHits.isNotEmpty || !searchesArchive) return MessageSearchPage(items: archiveHits);
    final term = query.normalizedQuery;
    if (term.isEmpty) return const MessageSearchPage(items: <MessageSearchResult>[]);
    // Newest first, as the phone's index answers.
    final hits = [
      for (final hit in archive)
        if (hit.bodySnippet.toLowerCase().contains(term)) hit,
    ]..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return MessageSearchPage(items: hits.take(query.limit).toList());
  }

  @override
  Future<void> storeConversations(List<ConversationPreview> conversations) async {}

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) async {}

  @override
  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  }) async {}

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) async {}
}
