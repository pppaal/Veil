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
  final bool isMine;

  bool get isPending => deliveryState == MessageDeliveryState.pending;
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
      isMine: isMine ?? this.isMine,
    );
  }
}

enum MessageDeliveryState { pending, sent, delivered, read, failed }
