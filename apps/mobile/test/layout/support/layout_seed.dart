import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/in_memory_message_content_store.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import '../../support/fake_relay.dart';
import 'layout_world.dart';

// What the layout cases show: eight conversations with names of every
// length, one chat with a real exchange in it (a long message, a reply, an
// attachment, a long link, a disappearing message, a system notice), one
// conversation with no message yet, a group for the cases that ask for one,
// contacts and devices.

/// Peers by handle, with the name the relay lists them under. One of them
/// set no name and is listed by handle; one name is long enough to overflow
/// a row.
const peerNames = <String, String?>{
  peerHandle: 'Sam Rivera',
  'priya': 'Priya Nair',
  timerChatPeerHandle: 'Jonas Weber',
  'alexandra': 'Alexandra Montgomery-Whitfield',
  'mia': 'Mia Chen',
  'omar': 'Omar Haddad',
  'tom_walsh': null,
  emptyChatPeerHandle: 'Lena Fischer',
};

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

class _Line {
  const _Line(
    this.mine,
    this.body, {
    this.kind = MessageKind.text,
    this.attachment = false,
    this.expires = false,
    this.from,
  });

  final bool mine;
  final String body;
  final MessageKind kind;
  final bool attachment;
  final bool expires;

  /// Who of a group wrote it, when it is not this device's user.
  final String? from;
}

const _chat = <_Line>[
  _Line(false, 'Did the signed lease come through on your side?'),
  _Line(true, 'Yes. Sending the scan here so it never touches email.'),
  _Line(true, 'lease-signed.pdf', kind: MessageKind.file, attachment: true),
  _Line(
    false,
    'Got it, thank you. Before we send the deposit I want to go over three things: the move-in date moved '
    'to the 14th, the landlord wants the first two months up front, and the clause about subletting is '
    'stricter than the draft we saw last week. Can you read section 7 again tonight and tell me if it '
    'still works for you? I would rather lose a day than sign something we have to fight about later.',
  ),
  _Line(true, 'Reading it now.'),
  _Line(false, 'The registry entry is at https://registry.example.org/property/KR-11680-2026-0419-0031/owners?verify=true'),
  _Line(false, 'Screenshot taken', kind: MessageKind.system),
  _Line(true, 'Account number for the deposit, gone in a week.', expires: true),
  _Line(true, 'Section 7 is fine. Let us sign tomorrow.'),
];

/// How many messages the chat's conversation holds.
int get chatLineCount => _chat.length;

// The last message of every other conversation, oldest conversation first.
// One conversation has none yet.
const _others = <String, _Line?>{
  emptyChatPeerHandle: null,
  'tom_walsh': _Line(true, 'Keys rotated, you should see a new safety number.'),
  'omar': _Line(false, 'Photo from the site visit', kind: MessageKind.image),
  'mia': _Line(false, 'The second mock-up is closer, but the header still feels heavy to me.'),
  'alexandra': _Line(false, 'Voice note', kind: MessageKind.voice),
  timerChatPeerHandle: _Line(true, 'See you at nine.'),
  'priya': _Line(false, 'I will send the slides for tomorrow here.'),
};

/// The group of the group cases: this user and three of the peers, in a
/// legacy group (frames through the pairwise engine, like every 1:1 here).
const groupConversationId = 'conv-group';
const groupMemberHandles = [peerHandle, 'priya', 'omar'];

const _group = <_Line>[
  _Line(false, 'The movers can do the 14th or the 16th.', from: peerHandle),
  _Line(false, 'The 14th works for me.', from: 'priya'),
  _Line(true, '14th then. I will book the lift for the morning.'),
  _Line(false, 'I can bring the van after six, if someone helps me carry the shelves down.', from: 'omar'),
];

/// How many messages the group's conversation holds.
int get groupLineCount => _group.length;

/// Fills the relay with the conversations above and stores the content of
/// this device's own messages, which no device can decrypt back. With
/// [withGroup] the newest conversation is the group.
Future<void> seedConversations(FakeRelay relay, LayoutMemoryCache cache, {bool withGroup = false}) async {
  final sealer = createDefaultCryptoAdapter();
  final day = DateTime.utc(2026, 4, 7, 8);
  var minute = 0;

  Future<void> send(String conversationId, String peer, _Line line) async {
    final sender = line.mine ? selfHandle : peer;
    final recipient = line.mine ? peer : selfHandle;
    final attachment = line.attachment
        ? const AttachmentReference(
            attachmentId: '6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f',
            storageKey: 'attachments/6f1c2d3e/blob',
            contentType: 'application/pdf',
            sizeBytes: 2411724,
            sha256: 'sha',
            encryptedKey: 'key',
            nonce: 'nonce',
          )
        : null;
    final expiresAt = line.expires ? DateTime.now().toUtc().add(const Duration(days: 6, hours: 12)) : null;
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'dev-$sender',
      recipientUserId: 'user-$recipient',
      body: line.body,
      messageKind: line.kind,
      recipientBundle: KeyBundle(
        userId: 'user-$recipient',
        deviceId: 'dev-$recipient',
        handle: recipient,
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
      expiresAt: expiresAt,
      attachment: attachment,
    );
    final stored = relay.inject(
      senderHandle: sender,
      conversationId: conversationId,
      envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    final sentAt = day.add(Duration(minutes: minute += 7));
    stored['serverReceivedAt'] = sentAt.toIso8601String();
    if (!line.mine) return;
    stored['deliveredAt'] = sentAt.add(const Duration(seconds: 2)).toIso8601String();
    await cache.put(MessageContentRecord(
      messageKey: stored['id'] as String,
      conversationId: conversationId,
      serverMessageId: stored['id'] as String,
      senderDeviceId: 'dev-$selfHandle',
      body: line.body,
      kind: line.kind,
      attachment: attachment,
      innerExpiresAt: expiresAt,
      status: MessageContentStatus.ok,
      createdAt: sentAt,
      updatedAt: sentAt,
    ));
  }

  for (final entry in _others.entries) {
    relay.addDirect('conv-${entry.key}', selfHandle, entry.key);
    if (entry.value case final line?) await send('conv-${entry.key}', entry.key, line);
  }
  relay.addDirect(chatConversationId, selfHandle, peerHandle);
  for (final line in _chat) {
    await send(chatConversationId, peerHandle, line);
  }
  // The peer read everything but the last message.
  final history = relay.conversations[chatConversationId]!.messages;
  for (final message in history.take(history.length - 1)) {
    if (message['deliveredAt'] != null) message['readAt'] = message['deliveredAt'];
  }
  if (!withGroup) return;
  relay.addGroup(groupConversationId, [selfHandle, ...groupMemberHandles], useSenderKeys: false);
  for (final line in _group) {
    await send(groupConversationId, line.from ?? peerHandle, line);
  }
}

/// The devices the settings screen lists.
const _deviceNames = ['Pixel 9 Pro Fold', 'MacBook Air', 'Old iPhone'];

const _transferSessionId = '8b6f0c1e-2d3a-4f5b-9c7d-1e2f3a4b5c6d';
const _transferToken = 'vt_3QmZ8xT1uKcR7pLwN5sYhB2dJ9aFgE4o';

/// What a case types into a search field: a part of two names (Sam Rivera,
/// Priya Nair) and of nothing else, and a word of two messages.
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
/// outside the messenger call: contacts, the device list and the old-device
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
            'members': [
              for (final member in (conversation['members'] as List).cast<Map<String, dynamic>>())
                <String, dynamic>{
                  ...member,
                  if (peerNames.containsKey(member['handle'])) 'displayName': peerNames[member['handle']],
                },
            ],
          },
      ],
    };
  }

  // What the contacts tab, the start screens and the device list ask the
  // relay to change, kept for the test that asked. A handle the relay has no
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
            <String, dynamic>{
              'handle': handle,
              'displayName': peerNames[handle],
              'avatarPath': null,
              'addedAt': DateTime.utc(2026, 3, 2).toIso8601String(),
            },
      ];

  @override
  Future<Map<String, dynamic>> addContact(String accessToken, Map<String, dynamic> body) async {
    final handle = body['handle'] as String;
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
    final group = relay.addGroup('conv-new-group-${createdGroups.length}', [me.handle, ...handles], useSenderKeys: false);
    return {
      'conversation': {'id': group.id},
    };
  }

  @override
  Future<Map<String, dynamic>> revokeDevice(String accessToken, String deviceId, {Map<String, String>? proof}) async {
    revokedDevices.add(deviceId);
    return const {};
  }

  @override
  Future<Map<String, dynamic>> logoutAuth(String accessToken, {String? refreshToken}) async => const {};

  @override
  Future<Map<String, dynamic>> listDevices(String accessToken) async {
    Map<String, dynamic> device(
      String id,
      String name,
      String platform,
      String trust, {
      required DateTime trustedAt,
      String? joinedFrom,
      bool revoked = false,
    }) =>
        {
          'id': id,
          'deviceName': name,
          'platform': platform,
          'isActive': !revoked,
          'trustState': trust,
          'revokedAt': revoked ? DateTime.utc(2026, 4, 1, 9).toIso8601String() : null,
          'trustedAt': trustedAt.toIso8601String(),
          'joinedFromDeviceId': joinedFrom == null ? null : me.deviceId,
          'joinedFromDeviceName': joinedFrom,
          'joinedFromPlatform': joinedFrom == null ? null : 'android',
          'createdAt': trustedAt.toIso8601String(),
          'lastSeenAt': DateTime.utc(2026, 4, 2).toIso8601String(),
          'lastSyncAt': DateTime.utc(2026, 3, 30).toIso8601String(),
          'lastTrustedActivityAt': DateTime.utc(2026, 4, 2).toIso8601String(),
        };
    // The laptop has gone quiet, until a test revokes it.
    final laptopRevoked = revokedDevices.contains('dev-laptop');
    return {
      'activeDeviceId': me.deviceId,
      'items': [
        device(me.deviceId, _deviceNames[0], 'android', 'current', trustedAt: DateTime.utc(2026, 4, 1, 8)),
        device('dev-laptop', _deviceNames[1], 'macos', laptopRevoked ? 'revoked' : 'stale',
            trustedAt: DateTime.utc(2026, 3, 20, 8), joinedFrom: _deviceNames[0], revoked: laptopRevoked),
        device('dev-old', _deviceNames[2], 'ios', 'revoked', trustedAt: DateTime.utc(2026, 3, 10, 8), revoked: true),
      ],
    };
  }

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

  /// What a search of the archive finds, whatever the query: there is no
  /// index here, so a test names the hits it is about.
  List<MessageSearchResult> archiveHits = const <MessageSearchResult>[];

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
  }) async =>
      MessageSearchPage(items: archiveHits);

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
