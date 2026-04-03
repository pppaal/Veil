import '../../../core/crypto/crypto_engine.dart';

class ConversationPreview {
  static const Object _unset = Object();

  ConversationPreview({
    required this.id,
    required this.peerHandle,
    required this.peerDisplayName,
    required this.recipientBundle,
    required this.lastEnvelope,
    required this.updatedAt,
  });

  final String id;
  final String peerHandle;
  final String? peerDisplayName;
  final KeyBundle recipientBundle;
  final CryptoEnvelope? lastEnvelope;
  final DateTime updatedAt;

  ConversationPreview copyWith({
    String? id,
    String? peerHandle,
    Object? peerDisplayName = _unset,
    KeyBundle? recipientBundle,
    Object? lastEnvelope = _unset,
    DateTime? updatedAt,
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
