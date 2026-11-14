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
// notice), one conversation with no message yet, contacts, calls, devices
// and stories. Message bodies follow the locale of the run, because Korean
// and English wrap differently.

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
  const _Line(this.mine, this.en, this.ko, {this.kind = MessageKind.text, this.attachment = false, this.expires = false});

  final bool mine;
  final String en;
  final String ko;
  final MessageKind kind;
  final bool attachment;
  final bool expires;
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

/// Fills the relay with the conversations above and stores the content of
/// this device's own messages, which no device can decrypt back.
Future<void> seedConversations(FakeRelay relay, LayoutMemoryCache cache, {required String locale}) async {
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
}

/// The relay as atlas's device reaches it, with the routes the screens
/// outside the messenger call: contacts, call history, stories, the device
/// list and the old-device half of a transfer.
class LayoutRelayClient extends FakeRelayClient {
  LayoutRelayClient(super.relay, super.me, {required this.locale});

  final String locale;

  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async {
    final response = await super.getConversations(accessToken);
    return {
      ...response,
      'items': [
        for (final conversation in (response['items'] as List).cast<Map<String, dynamic>>())
          {
            ...conversation,
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

  @override
  Future<List<dynamic>> getContacts(String accessToken) async => [
        for (final entry in peerNames.entries)
          <String, dynamic>{
            'handle': entry.key,
            'displayName': entry.value,
            'avatarPath': null,
            'addedAt': DateTime.utc(2026, 3, 2).toIso8601String(),
          },
      ];

  @override
  Future<List<dynamic>> getCallHistory(String accessToken) async {
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

  @override
  Future<List<dynamic>> getStories(String accessToken) async {
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
    return [
      story(peerHandle, 0, korean ? '오늘 한강에서 본 노을' : 'Sunset over the river tonight', viewed: false),
      story(peerHandle, 1, korean ? '이사 준비 끝!' : 'Packing is done!', viewed: false),
      story('maximilian', 0, korean ? '새 사무실 첫날' : 'First day at the new office', viewed: true),
      story('jiwoo', 0, '주말 등산', viewed: false),
      story('noor', 0, korean ? '현장 답사' : 'Site visit', viewed: true),
    ];
  }

  @override
  Future<Map<String, dynamic>> viewStory(String accessToken, String storyId) async => {'storyId': storyId};

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
    return {
      'activeDeviceId': me.deviceId,
      'items': [
        device(me.deviceId, 'Pixel 9 Pro Fold', 'android', 'current', trustedAt: DateTime.utc(2026, 4, 1, 8)),
        device('dev-laptop', 'MacBook Air', 'macos', 'stale',
            trustedAt: DateTime.utc(2026, 3, 20, 8), joinedFrom: 'Pixel 9 Pro Fold'),
        device('dev-old', 'Old iPhone', 'ios', 'revoked', trustedAt: DateTime.utc(2026, 3, 10, 8), revoked: true),
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> initTransfer(String accessToken, String deviceId) async => {
        'sessionId': '8b6f0c1e-2d3a-4f5b-9c7d-1e2f3a4b5c6d',
        'transferToken': 'vt_3QmZ8xT1uKcR7pLwN5sYhB2dJ9aFgE4o',
        'expiresAt': DateTime.now().toUtc().add(const Duration(minutes: 4, seconds: 30)).toIso8601String(),
      };
}

/// The device's cache as a map: stored message content (this device's own
/// messages are shown from it) and nothing else kept between launches.
class LayoutMemoryCache implements ConversationCacheService, MessageContentStore {
  final InMemoryMessageContentStore _contents = InMemoryMessageContentStore();

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
      const MessageSearchPage(items: <MessageSearchResult>[]);

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
