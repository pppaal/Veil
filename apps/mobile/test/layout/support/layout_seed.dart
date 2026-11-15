import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/in_memory_message_content_store.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import '../../support/fake_relay.dart';
import 'layout_world.dart';

// What the layout cases show: eight conversations with names of every
// length and script, one chat with a real exchange in it (a long message,
// a reply, an attachment, a long link, a disappearing message, a system
// notice), one conversation with no message yet, a group for the cases that
// ask for one, contacts, calls, devices and stories. Message bodies follow
// the locale of the run, because Korean and English wrap differently.

/// Peers by handle, with the name the relay lists them under. Names are
/// user data, so both locales see the same mix of scripts and lengths.
const peerNames = <String, String?>{
  peerHandle: 'Selene Park',
  'jiwoo': '한지우',
  'rowan': 'Rowan',
  'maximilian': 'Maximilian Alexander von Hohenberg-Schwarzenfeld',
  'seoyeon': '김서연 (디자인팀)',
  'noor': 'Noor Al-Hashimi',
  'tomasz_k': null,
  emptyChatPeerHandle: 'Mira',
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
    this.en,
    this.ko, {
    this.kind = MessageKind.text,
    this.attachment = false,
    this.expires = false,
    this.from,
  });

  final bool mine;
  final String en;
  final String ko;
  final MessageKind kind;
  final bool attachment;
  final bool expires;

  /// Who of a group wrote it, when it is not this device's user.
  final String? from;
}

const _chat = <_Line>[
  _Line(false, 'Did the signed lease come through on your side?', '서명한 임대 계약서 그쪽에도 도착했어?'),
  _Line(true, 'Yes. Sending the scan here so it never touches email.', '응. 이메일 안 거치게 여기로 스캔본 보낼게.'),
  _Line(true, 'lease-signed.pdf', 'lease-signed.pdf', kind: MessageKind.file, attachment: true),
  _Line(
    false,
    'Got it, thank you. Before we send the deposit I want to go over three things: the move-in date moved '
        'to the 14th, the landlord wants the first two months up front, and the clause about subletting is '
        'stricter than the draft we saw last week. Can you read section 7 again tonight and tell me if it '
        'still works for you? I would rather lose a day than sign something we have to fight about later.',
    '확인했어, 고마워. 보증금 보내기 전에 세 가지만 다시 짚고 싶어. 입주일이 14일로 바뀌었고, 집주인이 첫 두 달 '
        '치 월세를 선불로 원하고, 전대 조항이 지난주에 본 초안보다 더 엄격해졌어. 오늘 밤에 7조를 다시 읽어 보고 '
        '여전히 괜찮은지 알려 줄래? 나중에 다툴 일을 만드느니 하루 늦어지는 편이 낫다고 생각해.',
  ),
  _Line(true, 'Reading it now.', '지금 읽어 볼게.'),
  _Line(
    false,
    'The registry entry is at https://registry.example.org/property/KR-11680-2026-0419-0031/owners?verify=true',
    '등기부는 여기 있어 https://registry.example.org/property/KR-11680-2026-0419-0031/owners?verify=true',
  ),
  _Line(false, 'Screenshot taken', '스크린샷이 촬영되었습니다', kind: MessageKind.system),
  _Line(true, 'Account number for the deposit, gone in a week.', '보증금 보낼 계좌번호야. 일주일 뒤에 사라져.', expires: true),
  _Line(true, 'Section 7 is fine. Let us sign tomorrow.', '7조 괜찮아. 내일 서명하자.'),
];

/// How many messages the chat's conversation holds.
int get chatLineCount => _chat.length;

// The last message of every other conversation, oldest conversation first.
// One conversation has none yet.
const _others = <String, _Line?>{
  emptyChatPeerHandle: null,
  'tomasz_k': _Line(true, 'Keys rotated, you should see a new safety number.', '키를 교체했어. 새 안전 번호가 보일 거야.'),
  'noor': _Line(false, 'Photo from the site visit', '현장 방문 사진', kind: MessageKind.image),
  'seoyeon': _Line(false, 'The second mock-up is closer, but the header still feels heavy to me.', '두 번째 시안이 더 낫긴 한데 헤더가 아직 무거워 보여요.'),
  'maximilian': _Line(false, 'Voice note', '음성 메모', kind: MessageKind.voice),
  'rowan': _Line(true, 'See you at nine.', '아홉 시에 봐.'),
  'jiwoo': _Line(false, '내일 회의 자료는 여기로 보낼게', '내일 회의 자료는 여기로 보낼게'),
};

/// The group of the group cases: this user and three of the peers, in a
/// legacy group (frames through the pairwise engine, like every 1:1 here).
const groupConversationId = 'conv-group';
const groupMemberHandles = [peerHandle, 'jiwoo', 'noor'];

const _group = <_Line>[
  _Line(false, 'The movers can do the 14th or the 16th.', '이삿짐 센터는 14일이나 16일에 된대.', from: peerHandle),
  _Line(false, 'The 14th works for me.', '저는 14일 괜찮아요.', from: 'jiwoo'),
  _Line(true, '14th then. I will book the lift for the morning.', '그럼 14일로 하자. 오전에 엘리베이터 예약해 둘게.'),
  _Line(false, 'I can bring the van after six, if someone helps me carry the shelves down.',
      '여섯 시 이후에 밴 가져갈 수 있어요. 책장 내리는 것만 누가 도와주면 돼요.', from: 'noor'),
];

/// How many messages the group's conversation holds.
int get groupLineCount => _group.length;

/// Fills the relay with the conversations above and stores the content of
/// this device's own messages, which no device can decrypt back. With
/// [withGroup] the newest conversation is the group.
Future<void> seedConversations(
  FakeRelay relay,
  LayoutMemoryCache cache, {
  required String locale,
  bool withGroup = false,
}) async {
  final sealer = createDefaultCryptoAdapter();
  final korean = locale == 'ko';
  final day = DateTime.utc(2026, 4, 7, 8);
  var minute = 0;

  Future<void> send(String conversationId, String peer, _Line line) async {
    final body = korean ? line.ko : line.en;
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
      body: body,
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
      body: body,
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

// What the story cases show; a caption follows the run's language, except
// one that is Korean in both.
const _storyCaptions = <(String handle, String en, String ko)>[
  (peerHandle, 'Sunset over the river tonight', '오늘 한강에서 본 노을'),
  (peerHandle, 'Packing is done!', '이사 준비 끝!'),
  ('maximilian', 'First day at the new office', '새 사무실 첫날'),
  ('jiwoo', '주말 등산', '주말 등산'),
  ('noor', 'Site visit', '현장 답사'),
];

/// The devices the settings screen lists.
const _deviceNames = ['Pixel 9 Pro Fold', 'MacBook Air', 'Old iPhone'];

const _transferSessionId = '8b6f0c1e-2d3a-4f5b-9c7d-1e2f3a4b5c6d';
const _transferToken = 'vt_3QmZ8xT1uKcR7pLwN5sYhB2dJ9aFgE4o';

/// What a case types into a search field.
const conversationSearchQuery = 'se';
const chatSearchQuery = 'lease';

/// The names of the fixtures: people, handles and devices. A screen may show
/// one whole, one word of it, or its first letter (an avatar).
List<String> get fixtureNames => [
      selfHandle,
      selfDisplayName,
      ...peerNames.keys,
      ...peerNames.values.nonNulls,
      ..._deviceNames,
    ];

/// Everything else of the fixtures a screen shows as it is: message
/// bodies, story captions, ids and codes.
List<String> get fixtureTexts => [
      for (final line in [..._chat, ..._others.values.nonNulls, ..._group]) ...[line.en, line.ko],
      for (final (_, en, ko) in _storyCaptions) ...[en, ko],
      for (final handle in [selfHandle, ...peerNames.keys]) ...['user-$handle', 'dev-$handle', 'conv-$handle'],
      groupConversationId,
      _transferSessionId,
      _transferToken,
    ];

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

/// The relay as atlas's device reaches it, with the routes the screens
/// outside the messenger call: contacts, call history, stories, the device
/// list and the old-device half of a transfer.
class LayoutRelayClient extends FakeRelayClient {
  LayoutRelayClient(super.relay, super.me, {required this.locale});

  final String locale;

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

  /// What the relay has on record instead of the seeded calls, when a test
  /// sets it.
  List<Map<String, dynamic>>? callRecords;

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
  Future<List<dynamic>> getCallHistory(String accessToken) async {
    if (callRecords case final records?) return records;
    // A day old, so every row reads "Yesterday, hh:mm" whenever it runs.
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toUtc();
    Map<String, dynamic> call(String handle, String type, String status, {required bool mine, int? seconds}) => {
          'id': 'call-$handle-$status',
          'conversationId': 'conv-$handle',
          'counterparty': peerNames[handle] ?? handle,
          'counterpartyHandle': handle,
          'callType': type,
          'status': status,
          'initiatedByMe': mine,
          'duration': seconds,
          'startedAt': yesterday.toIso8601String(),
        };
    return [
      call(peerHandle, 'voice', 'ended', mine: true, seconds: 754),
      call('maximilian', 'video', 'missed', mine: false),
      call('jiwoo', 'voice', 'ended', mine: false, seconds: 3725),
      call('noor', 'video', 'declined', mine: true),
      call('rowan', 'voice', 'missed', mine: false),
      call('seoyeon', 'voice', 'ended', mine: true, seconds: 42),
    ];
  }

  /// The stories the relay lists instead of the seeded ones, when a test
  /// sets it.
  List<Map<String, dynamic>>? storyRecords;

  @override
  Future<List<dynamic>> getStories(String accessToken) async {
    if (storyRecords case final records?) return records;
    final now = DateTime.now().toUtc();
    Map<String, dynamic> story(String handle, int index, String caption, {required bool viewed}) => {
          'id': 'story-$handle-$index',
          'userId': 'user-$handle',
          'handle': handle,
          'displayName': peerNames[handle],
          'contentType': 'text',
          'contentUrl': '',
          'caption': caption,
          'viewCount': 3 + index,
          'viewedByMe': viewed,
          'createdAt': now.subtract(Duration(hours: 2 + index)).toIso8601String(),
          'expiresAt': now.add(Duration(hours: 22 - index)).toIso8601String(),
        };
    final korean = locale == 'ko';
    final seen = <String, int>{};
    return [
      for (final (handle, en, ko) in _storyCaptions)
        story(
          handle,
          seen.update(handle, (count) => count + 1, ifAbsent: () => 0),
          korean ? ko : en,
          viewed: handle == 'maximilian' || handle == 'noor',
        ),
    ];
  }

  /// The stories this device told the relay it viewed, in order.
  final List<String> viewedStories = [];

  @override
  Future<Map<String, dynamic>> viewStory(String accessToken, String storyId) async {
    viewedStories.add(storyId);
    return {'storyId': storyId};
  }

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
