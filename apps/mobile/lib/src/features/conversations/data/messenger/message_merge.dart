import '../conversation_models.dart';

/// Merges a page of server messages into the local list. Server copies win
/// field by field, except that receipts and expiry only move one way; local
/// pending/failed messages survive until their server copy arrives.
List<ChatMessage> mergeMessageCollections(
  List<ChatMessage> current,
  List<ChatMessage> incoming,
) {
  final mergedServerMessages = <String, ChatMessage>{};
  final currentPending =
      current.where((message) => message.isPending || message.hasFailed).toList();

  for (final message in current.where((item) => !item.isPending && !item.hasFailed)) {
    mergedServerMessages[message.id] = message;
  }
  for (final message in incoming) {
    final existing = mergedServerMessages[message.id];
    mergedServerMessages[message.id] =
        existing == null ? message : mergeServerMessage(existing, message);
  }

  final ackedClientIds =
      incoming.map((message) => message.clientMessageId).whereType<String>().toSet();

  final merged = <ChatMessage>[
    ...mergedServerMessages.values,
    ...currentPending.where((message) => !ackedClientIds.contains(message.clientMessageId)),
  ];
  merged.sort(compareMessages);
  return merged;
}

ChatMessage mergeServerMessage(ChatMessage current, ChatMessage incoming) {
  final deliveredAt = laterOf(current.deliveredAt, incoming.deliveredAt);
  final readAt = laterOf(current.readAt, incoming.readAt);
  return incoming.copyWith(
    clientMessageId: incoming.clientMessageId ?? current.clientMessageId,
    conversationOrder: incoming.conversationOrder ?? current.conversationOrder,
    searchableBody: incoming.searchableBody ?? current.searchableBody,
    deliveredAt: deliveredAt,
    readAt: readAt,
    // The local value may already be clamped to the authenticated inner
    // expiry; a later server copy can shorten it but never extend or drop it.
    expiresAt: earlierOf(current.expiresAt, incoming.expiresAt),
    deliveryState: resolveDeliveryState(
      base: incoming.deliveryState,
      deliveredAt: deliveredAt,
      readAt: readAt,
    ),
  );
}

int compareMessages(ChatMessage a, ChatMessage b) {
  final aOrder = a.conversationOrder;
  final bOrder = b.conversationOrder;
  if (aOrder != null && bOrder != null) {
    // A local notice shares the order of the message it followed.
    final byOrder = aOrder.compareTo(bOrder);
    return byOrder != 0 ? byOrder : a.sentAt.compareTo(b.sentAt);
  }
  if (aOrder != null) {
    return -1;
  }
  if (bOrder != null) {
    return 1;
  }
  return a.sentAt.compareTo(b.sentAt);
}

DateTime? laterOf(DateTime? left, DateTime? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left.isAfter(right) ? left : right;
}

/// [message] expiring at min(outer, inner) (contract C4): the relay may
/// strip or extend the outer expiresAt, but never the one sealed inside.
ChatMessage withInnerExpiry(ChatMessage message, DateTime? innerExpiresAt) {
  final expiresAt = earlierOf(message.expiresAt, innerExpiresAt);
  return expiresAt == message.expiresAt ? message : message.copyWith(expiresAt: expiresAt);
}

/// The earlier of two optional expiries; null means "never".
DateTime? earlierOf(DateTime? left, DateTime? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left.isBefore(right) ? left : right;
}

MessageDeliveryState resolveDeliveryState({
  required MessageDeliveryState base,
  required DateTime? deliveredAt,
  required DateTime? readAt,
}) {
  if (readAt != null) {
    return MessageDeliveryState.read;
  }
  if (deliveredAt != null) {
    return MessageDeliveryState.delivered;
  }
  return base;
}
