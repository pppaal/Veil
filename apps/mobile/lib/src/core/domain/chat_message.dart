import '../crypto/crypto_engine.dart';

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

/// Id prefix of rows this device inserts into a conversation by itself,
/// such as identity notices. Relay ids are UUIDs, and the messenger drops
/// any relayed row that carries this prefix anyway, so no peer and no server
/// can produce a row that passes for one.
const String localNoticeIdPrefix = 'notice:';

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
  bool get isLocalNotice => id.startsWith(localNoticeIdPrefix);

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
