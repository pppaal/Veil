import '../../../core/crypto/crypto_engine.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum ConversationType { direct, group, channel }

enum MemberRole { owner, admin, member, subscriber }

enum CallType { voice, video }

enum CallStatus { ringing, active, ended, missed, declined }

// ---------------------------------------------------------------------------
// Group & Channel metadata
// ---------------------------------------------------------------------------

class GroupMeta {
  const GroupMeta({
    required this.name,
    this.description,
    this.avatarPath,
    this.isPublic = false,
    this.memberCount = 0,
    this.memberLimit = 500,
    this.link,
  });

  final String name;
  final String? description;
  final String? avatarPath;
  final bool isPublic;
  final int memberCount;
  final int memberLimit;
  final String? link;
}

// Lightweight per-member projection used when the client needs to enumerate
// a group's participants — currently for per-peer safety-number verification.
// Does NOT carry key material; consumers fetch the KeyBundle on demand via
// the users/:handle/key-bundle endpoint. Keeping keys out of the preview
// layer means we don't pay the N-fetch cost on every conversation list load.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.handle,
    this.displayName,
    this.role = MemberRole.member,
  });

  final String userId;
  final String handle;
  final String? displayName;
  final MemberRole role;

  String get title =>
      (displayName != null && displayName!.isNotEmpty)
          ? displayName!
          : '@$handle';
}

class ChannelMeta {
  const ChannelMeta({
    required this.name,
    this.description,
    this.avatarPath,
    this.isPublic = false,
    this.subscriberCount = 0,
    this.link,
  });

  final String name;
  final String? description;
  final String? avatarPath;
  final bool isPublic;
  final int subscriberCount;
  final String? link;
}

// ---------------------------------------------------------------------------
// Contacts & profiles
// ---------------------------------------------------------------------------

class UserContact {
  const UserContact({
    required this.userId,
    required this.contactUserId,
    required this.handle,
    this.displayName,
    this.nickname,
    this.avatarPath,
  });

  final String userId;
  final String contactUserId;
  final String handle;
  final String? displayName;
  final String? nickname;
  final String? avatarPath;

  String get title => nickname ?? displayName ?? '@$handle';
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.handle,
    this.displayName,
    this.bio,
    this.statusMessage,
    this.statusEmoji,
    this.avatarPath,
  });

  final String userId;
  final String handle;
  final String? displayName;
  final String? bio;
  final String? statusMessage;
  final String? statusEmoji;
  final String? avatarPath;
}

// ---------------------------------------------------------------------------
// Stories
// ---------------------------------------------------------------------------

class Story {
  const Story({
    required this.id,
    required this.userId,
    required this.handle,
    this.displayName,
    required this.contentType,
    required this.contentUrl,
    this.caption,
    required this.expiresAt,
    this.viewCount = 0,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String handle;
  final String? displayName;
  final String contentType;
  final String contentUrl;
  final String? caption;
  final DateTime expiresAt;
  final int viewCount;
  final DateTime createdAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------

class CallRecord {
  const CallRecord({
    required this.id,
    required this.conversationId,
    required this.callType,
    required this.status,
    this.initiatorHandle,
    required this.startedAt,
    this.endedAt,
    this.duration,
  });

  final String id;
  final String conversationId;
  final CallType callType;
  final CallStatus status;
  final String? initiatorHandle;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Duration? duration;

  bool get isMissed => status == CallStatus.missed;
  bool get isActive => status == CallStatus.active;
}

// ---------------------------------------------------------------------------
// Reactions
// ---------------------------------------------------------------------------

class Reaction {
  const Reaction({
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;
}

// ---------------------------------------------------------------------------
// Session & conversation models
// ---------------------------------------------------------------------------

class ConversationSessionState {
  const ConversationSessionState({
    required this.sessionLocator,
    required this.sessionEnvelopeVersion,
    required this.requiresLocalPersistence,
    required this.sessionSchemaVersion,
    required this.localDeviceId,
    required this.remoteDeviceId,
    required this.remoteIdentityFingerprint,
    required this.bootstrappedAt,
    this.auditHint,
  });

  final String sessionLocator;
  final String sessionEnvelopeVersion;
  final bool requiresLocalPersistence;
  final int sessionSchemaVersion;
  final String localDeviceId;
  final String remoteDeviceId;
  final String remoteIdentityFingerprint;
  final DateTime bootstrappedAt;
  final String? auditHint;

  bool matchesBundle(KeyBundle bundle) => remoteDeviceId == bundle.deviceId;

  bool belongsToLocalDevice(String deviceId) => localDeviceId == deviceId;
}

class ConversationPreview {
  static const Object _unset = Object();

  ConversationPreview({
    required this.id,
    required this.peerHandle,
    required this.peerDisplayName,
    required this.recipientBundle,
    required this.lastEnvelope,
    required this.updatedAt,
    this.sessionState,
    this.type = ConversationType.direct,
    this.groupMeta,
    this.channelMeta,
    this.memberCount,
    this.members = const [],
    this.unreadCount = 0,
    this.disappearingTimerSeconds,
  });

  final String id;
  final String peerHandle;
  final String? peerDisplayName;
  final KeyBundle recipientBundle;
  final CryptoEnvelope? lastEnvelope;
  final DateTime updatedAt;
  final ConversationSessionState? sessionState;
  final ConversationType type;
  final GroupMeta? groupMeta;
  final ChannelMeta? channelMeta;
  final int? memberCount;
  // All participants of this conversation, populated only for groups.
  // For direct chats this is empty — the single peer lives in
  // peerHandle/peerDisplayName/recipientBundle. Key material is NOT
  // carried here; resolve per-member KeyBundles on demand.
  final List<GroupMember> members;
  final int unreadCount;
  // Default TTL (seconds) applied to newly-sent messages in this
  // conversation. null = disappearing messages disabled.
  final int? disappearingTimerSeconds;

  ConversationPreview copyWith({
    String? id,
    String? peerHandle,
    Object? peerDisplayName = _unset,
    KeyBundle? recipientBundle,
    Object? lastEnvelope = _unset,
    DateTime? updatedAt,
    Object? sessionState = _unset,
    ConversationType? type,
    Object? groupMeta = _unset,
    Object? channelMeta = _unset,
    Object? memberCount = _unset,
    List<GroupMember>? members,
    int? unreadCount,
    Object? disappearingTimerSeconds = _unset,
  }) {
    return ConversationPreview(
      id: id ?? this.id,
      peerHandle: peerHandle ?? this.peerHandle,
      peerDisplayName:
          identical(peerDisplayName, _unset) ? this.peerDisplayName : peerDisplayName as String?,
      recipientBundle: recipientBundle ?? this.recipientBundle,
      lastEnvelope:
          identical(lastEnvelope, _unset) ? this.lastEnvelope : lastEnvelope as CryptoEnvelope?,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionState:
          identical(sessionState, _unset) ? this.sessionState : sessionState as ConversationSessionState?,
      type: type ?? this.type,
      groupMeta:
          identical(groupMeta, _unset) ? this.groupMeta : groupMeta as GroupMeta?,
      channelMeta:
          identical(channelMeta, _unset) ? this.channelMeta : channelMeta as ChannelMeta?,
      memberCount:
          identical(memberCount, _unset) ? this.memberCount : memberCount as int?,
      members: members ?? this.members,
      unreadCount: unreadCount ?? this.unreadCount,
      disappearingTimerSeconds: identical(disappearingTimerSeconds, _unset)
          ? this.disappearingTimerSeconds
          : disappearingTimerSeconds as int?,
    );
  }
}

class ChatMessage {
  static const Object _unset = Object();

  ChatMessage({
    required this.id,
    required this.senderDeviceId,
    required this.sentAt,
    required this.envelope,
    this.clientMessageId,
    this.conversationOrder,
    this.deliveryState = MessageDeliveryState.sent,
    this.deliveredAt,
    this.readAt,
    this.expiresAt,
    this.searchableBody,
    this.isMine = false,
    this.reactions = const [],
    this.replyToMessageId,
    this.forwardedFrom,
  });

  final String id;
  final String? clientMessageId;
  final String senderDeviceId;
  final DateTime sentAt;
  final CryptoEnvelope envelope;
  final int? conversationOrder;
  final MessageDeliveryState deliveryState;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? expiresAt;
  final String? searchableBody;
  final bool isMine;
  final List<Reaction> reactions;
  final String? replyToMessageId;
  final String? forwardedFrom;

  bool get isPending =>
      deliveryState == MessageDeliveryState.pending ||
      deliveryState == MessageDeliveryState.uploading;
  bool get hasFailed => deliveryState == MessageDeliveryState.failed;

  ChatMessage copyWith({
    String? id,
    Object? clientMessageId = _unset,
    String? senderDeviceId,
    DateTime? sentAt,
    CryptoEnvelope? envelope,
    Object? conversationOrder = _unset,
    MessageDeliveryState? deliveryState,
    Object? deliveredAt = _unset,
    Object? readAt = _unset,
    Object? expiresAt = _unset,
    Object? searchableBody = _unset,
    bool? isMine,
    List<Reaction>? reactions,
    Object? replyToMessageId = _unset,
    Object? forwardedFrom = _unset,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      clientMessageId:
          identical(clientMessageId, _unset) ? this.clientMessageId : clientMessageId as String?,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      sentAt: sentAt ?? this.sentAt,
      envelope: envelope ?? this.envelope,
      conversationOrder:
          identical(conversationOrder, _unset) ? this.conversationOrder : conversationOrder as int?,
      deliveryState: deliveryState ?? this.deliveryState,
      deliveredAt: identical(deliveredAt, _unset) ? this.deliveredAt : deliveredAt as DateTime?,
      readAt: identical(readAt, _unset) ? this.readAt : readAt as DateTime?,
      expiresAt: identical(expiresAt, _unset) ? this.expiresAt : expiresAt as DateTime?,
      searchableBody:
          identical(searchableBody, _unset) ? this.searchableBody : searchableBody as String?,
      isMine: isMine ?? this.isMine,
      reactions: reactions ?? this.reactions,
      replyToMessageId:
          identical(replyToMessageId, _unset) ? this.replyToMessageId : replyToMessageId as String?,
      forwardedFrom:
          identical(forwardedFrom, _unset) ? this.forwardedFrom : forwardedFrom as String?,
    );
  }
}

enum MessageDeliveryState { uploading, pending, sent, delivered, read, failed }

enum MessageSearchSenderFilter { all, mine, theirs }

enum MessageSearchTypeFilter { all, text, media, file, system }

enum MessageSearchDateFilter { any, last7Days, last30Days }

class MessageSearchQuery {
  const MessageSearchQuery({
    required this.query,
    this.conversationId,
    this.senderFilter = MessageSearchSenderFilter.all,
    this.typeFilter = MessageSearchTypeFilter.all,
    this.dateFilter = MessageSearchDateFilter.any,
    this.limit = 20,
    this.beforeSentAt,
    this.beforeMessageId,
  });

  final String query;
  final String? conversationId;
  final MessageSearchSenderFilter senderFilter;
  final MessageSearchTypeFilter typeFilter;
  final MessageSearchDateFilter dateFilter;
  final int limit;
  final DateTime? beforeSentAt;
  final String? beforeMessageId;

  String get normalizedQuery => query.trim().toLowerCase();

  DateTime? resolveCutoff(DateTime now) {
    return switch (dateFilter) {
      MessageSearchDateFilter.any => null,
      MessageSearchDateFilter.last7Days => now.subtract(const Duration(days: 7)),
      MessageSearchDateFilter.last30Days => now.subtract(const Duration(days: 30)),
    };
  }
}

class MessageSearchPage {
  const MessageSearchPage({
    required this.items,
    this.nextBeforeSentAt,
    this.nextBeforeMessageId,
  });

  final List<MessageSearchResult> items;
  final DateTime? nextBeforeSentAt;
  final String? nextBeforeMessageId;

  bool get hasMore => nextBeforeSentAt != null && nextBeforeMessageId != null;
}

class MessageSearchResult {
  const MessageSearchResult({
    required this.conversationId,
    required this.messageId,
    required this.peerHandle,
    required this.peerDisplayName,
    required this.sentAt,
    required this.messageKind,
    required this.isMine,
    required this.bodySnippet,
    this.conversationOrder,
  });

  final String conversationId;
  final String messageId;
  final String peerHandle;
  final String? peerDisplayName;
  final DateTime sentAt;
  final MessageKind messageKind;
  final bool isMine;
  final String bodySnippet;
  final int? conversationOrder;

  String get title => peerDisplayName ?? '@$peerHandle';
}

class MessageNavigationTarget {
  const MessageNavigationTarget({
    required this.messageId,
    required this.requestId,
    this.query,
  });

  final String messageId;
  final int requestId;
  final String? query;
}
