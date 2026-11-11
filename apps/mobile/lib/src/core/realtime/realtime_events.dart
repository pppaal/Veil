/// Every key of `RealtimeEventMap` in packages/contracts/src/index.ts.
/// scripts/realtime-contract-check.mjs fails CI when the two drift apart.
const kRealtimeEventNames = <String>{
  'message.new',
  'message.delivered',
  'message.read',
  'message.reaction',
  'message.edited',
  'message.deleted',
  'presence.update',
  'typing.start',
  'typing.stop',
  'conversation.sync',
  'conversation.timer.changed',
  'message.consumed',
  'call.incoming',
  'call.ended',
  'call.accepted',
  'call.declined',
  'call.signal',
  'story.new',
  'group.epoch.bumped',
  'group.key.distribution',
};

/// Contract events the client subscribes to but deliberately does not act
/// on yet, with the reason. They parse as [UnknownRealtimeEvent]. Handling
/// one means adding a typed variant below and removing it here.
const kIgnoredRealtimeEvents = <String, String>{
  'message.edited':
      'Mobile has no edit support yet; it neither sends edits nor re-renders '
          'edited revisions.',
  'message.deleted':
      'Mobile has no delete-for-everyone support yet.',
  'message.consumed':
      'Mobile does not send view-once messages yet.',
  'call.incoming':
      'Calls on mobile are a local preview screen with no signalling yet.',
  'call.ended':
      'Calls on mobile are a local preview screen with no signalling yet.',
  'call.accepted':
      'Calls on mobile are a local preview screen with no signalling yet.',
  'call.declined':
      'Calls on mobile are a local preview screen with no signalling yet.',
  'call.signal':
      'Calls on mobile have no WebRTC stack to consume signalling yet.',
  'story.new':
      'The stories tab fetches the feed when opened instead of live-merging.',
};

/// A realtime event whose payload has been validated against the contract.
///
/// Handlers can switch over the variants without casting raw JSON.
sealed class RealtimeEvent {
  const RealtimeEvent();

  String get name;

  /// Validates [payload] for event [name]. Returns null when a typed event's
  /// payload is malformed (the caller drops it), and [UnknownRealtimeEvent]
  /// for ignored or non-contract names. Never throws.
  static RealtimeEvent? tryParse(String name, Object? payload) {
    if (!kRealtimeEventNames.contains(name) ||
        kIgnoredRealtimeEvents.containsKey(name)) {
      return UnknownRealtimeEvent(name, payload);
    }
    // Map<String, dynamic> is what socket.io's JSON decoding yields and what
    // handlers downstream expect; anything else is malformed.
    if (payload is! Map<String, dynamic>) {
      return null;
    }
    return switch (name) {
      'message.new' => MessageNewEvent._tryParse(payload),
      'message.delivered' => MessageDeliveredEvent._tryParse(payload),
      'message.read' => MessageReadEvent._tryParse(payload),
      'message.reaction' => MessageReactionEvent._tryParse(payload),
      'presence.update' => PresenceUpdateEvent._tryParse(payload),
      'typing.start' => TypingEvent._tryParse(payload, started: true),
      'typing.stop' => TypingEvent._tryParse(payload, started: false),
      'conversation.sync' => ConversationSyncEvent._tryParse(payload),
      'conversation.timer.changed' =>
        ConversationTimerChangedEvent._tryParse(payload),
      'group.key.distribution' => GroupKeyDistributionEvent._tryParse(payload),
      'group.epoch.bumped' => GroupEpochBumpedEvent._tryParse(payload),
      _ => UnknownRealtimeEvent(name, payload),
    };
  }
}

/// A new message as a `ConversationMessageSummary`. The identifying fields
/// are typed; [summary] keeps the whole map for the envelope codec.
final class MessageNewEvent extends RealtimeEvent {
  const MessageNewEvent({
    required this.messageId,
    required this.conversationId,
    required this.senderDeviceId,
    required this.conversationOrder,
    required this.serverReceivedAt,
    required this.summary,
  });

  @override
  String get name => 'message.new';

  final String messageId;
  final String conversationId;
  final String senderDeviceId;
  final int conversationOrder;
  final DateTime serverReceivedAt;
  final Map<String, dynamic> summary;

  static MessageNewEvent? _tryParse(Map<String, dynamic> payload) {
    if (payload
        case {
          'id': String messageId,
          'conversationId': String conversationId,
          'senderDeviceId': String senderDeviceId,
          'conversationOrder': int conversationOrder,
          'ciphertext': String _,
          'nonce': String _,
          'messageType': String _,
          'serverReceivedAt': String receivedAt,
        }) {
      final serverReceivedAt = DateTime.tryParse(receivedAt);
      final optionalFieldsValid = _isOptional<String>(payload['clientMessageId']) &&
          _isOptional<String>(payload['version']) &&
          _isOptional<Map<String, dynamic>>(payload['attachment']) &&
          _isOptionalTimestamp(payload['expiresAt']) &&
          _isOptionalTimestamp(payload['deliveredAt']) &&
          _isOptionalTimestamp(payload['readAt']);
      if (serverReceivedAt == null ||
          !optionalFieldsValid ||
          !_allNonEmpty([messageId, conversationId, senderDeviceId])) {
        return null;
      }
      return MessageNewEvent(
        messageId: messageId,
        conversationId: conversationId,
        senderDeviceId: senderDeviceId,
        conversationOrder: conversationOrder,
        serverReceivedAt: serverReceivedAt,
        summary: payload,
      );
    }
    return null;
  }
}

final class MessageDeliveredEvent extends RealtimeEvent {
  const MessageDeliveredEvent({
    required this.messageId,
    required this.userId,
    required this.deliveredAt,
  });

  @override
  String get name => 'message.delivered';

  final String messageId;
  final String userId;
  final DateTime deliveredAt;

  static MessageDeliveredEvent? _tryParse(Map<String, dynamic> payload) {
    if (payload
        case {
          'messageId': String messageId,
          'userId': String userId,
          'deliveredAt': String rawDeliveredAt,
        }) {
      final deliveredAt = DateTime.tryParse(rawDeliveredAt);
      if (deliveredAt == null || !_allNonEmpty([messageId, userId])) {
        return null;
      }
      return MessageDeliveredEvent(
        messageId: messageId,
        userId: userId,
        deliveredAt: deliveredAt,
      );
    }
    return null;
  }
}

final class MessageReadEvent extends RealtimeEvent {
  const MessageReadEvent({
    required this.messageId,
    required this.userId,
    required this.readAt,
  });

  @override
  String get name => 'message.read';

  final String messageId;
  final String userId;
  final DateTime readAt;

  static MessageReadEvent? _tryParse(Map<String, dynamic> payload) {
    if (payload
        case {
          'messageId': String messageId,
          'userId': String userId,
          'readAt': String rawReadAt,
        }) {
      final readAt = DateTime.tryParse(rawReadAt);
      if (readAt == null || !_allNonEmpty([messageId, userId])) {
        return null;
      }
      return MessageReadEvent(
        messageId: messageId,
        userId: userId,
        readAt: readAt,
      );
    }
    return null;
  }
}

final class MessageReactionEvent extends RealtimeEvent {
  const MessageReactionEvent({
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.added,
  });

  @override
  String get name => 'message.reaction';

  final String messageId;
  final String userId;

  /// Empty for removals, which the server sends without the emoji.
  final String emoji;
  final bool added;

  static MessageReactionEvent? _tryParse(Map<String, dynamic> payload) {
    final added = switch (payload['action']) {
      'add' => true,
      'remove' => false,
      _ => null,
    };
    if (added == null) {
      return null;
    }
    if (payload
        case {
          'messageId': String messageId,
          'userId': String userId,
          'emoji': String emoji,
        } when _allNonEmpty([messageId, userId])) {
      return MessageReactionEvent(
        messageId: messageId,
        userId: userId,
        emoji: emoji,
        added: added,
      );
    }
    return null;
  }
}

final class PresenceUpdateEvent extends RealtimeEvent {
  const PresenceUpdateEvent({
    required this.userId,
    required this.online,
    required this.updatedAt,
  });

  @override
  String get name => 'presence.update';

  final String userId;
  final bool online;
  final DateTime updatedAt;

  static PresenceUpdateEvent? _tryParse(Map<String, dynamic> payload) {
    final online = switch (payload['status']) {
      'online' => true,
      'offline' => false,
      _ => null,
    };
    if (online == null) {
      return null;
    }
    if (payload
        case {
          'userId': String userId,
          'updatedAt': String rawUpdatedAt,
        } when userId.isNotEmpty) {
      final updatedAt = DateTime.tryParse(rawUpdatedAt);
      if (updatedAt == null) {
        return null;
      }
      return PresenceUpdateEvent(
        userId: userId,
        online: online,
        updatedAt: updatedAt,
      );
    }
    return null;
  }
}

/// `typing.start` ([started] true) or `typing.stop`.
final class TypingEvent extends RealtimeEvent {
  const TypingEvent({
    required this.started,
    required this.conversationId,
    required this.userId,
    required this.handle,
  });

  @override
  String get name => started ? 'typing.start' : 'typing.stop';

  final bool started;
  final String conversationId;
  final String userId;
  final String handle;

  static TypingEvent? _tryParse(
    Map<String, dynamic> payload, {
    required bool started,
  }) {
    if (payload
        case {
          'conversationId': String conversationId,
          'userId': String userId,
          'handle': String handle,
        } when _allNonEmpty([conversationId, userId, handle])) {
      return TypingEvent(
        started: started,
        conversationId: conversationId,
        userId: userId,
        handle: handle,
      );
    }
    return null;
  }
}

enum ConversationSyncReason { message, membership, refresh }

final class ConversationSyncEvent extends RealtimeEvent {
  const ConversationSyncEvent({
    required this.conversationId,
    required this.reason,
  });

  @override
  String get name => 'conversation.sync';

  final String conversationId;
  final ConversationSyncReason reason;

  static ConversationSyncEvent? _tryParse(Map<String, dynamic> payload) {
    if (payload
        case {
          'conversationId': String conversationId,
          'reason': String rawReason,
        } when conversationId.isNotEmpty) {
      final reason = ConversationSyncReason.values.asNameMap()[rawReason];
      if (reason == null) {
        return null;
      }
      return ConversationSyncEvent(
        conversationId: conversationId,
        reason: reason,
      );
    }
    return null;
  }
}

final class ConversationTimerChangedEvent extends RealtimeEvent {
  const ConversationTimerChangedEvent({
    required this.conversationId,
    required this.disappearingTimerSeconds,
  });

  @override
  String get name => 'conversation.timer.changed';

  final String conversationId;

  /// Null when the timer was turned off.
  final int? disappearingTimerSeconds;

  static ConversationTimerChangedEvent? _tryParse(
    Map<String, dynamic> payload,
  ) {
    // The key must be present: a payload that merely forgot the field must
    // not read as "timer turned off".
    if (payload
        case {
          'conversationId': String conversationId,
          'disappearingTimerSeconds': int? seconds,
        } when conversationId.isNotEmpty && (seconds == null || seconds > 0)) {
      return ConversationTimerChangedEvent(
        conversationId: conversationId,
        disappearingTimerSeconds: seconds,
      );
    }
    return null;
  }
}

/// A sender-key chain-key distribution addressed to this user. The chain
/// key stays opaque here; the group coordinator opens it.
final class GroupKeyDistributionEvent extends RealtimeEvent {
  const GroupKeyDistributionEvent({
    required this.conversationId,
    required this.epoch,
    required this.fromUserId,
    required this.fromDeviceId,
    required this.encryptedChainKey,
    required this.nonce,
    required this.version,
  });

  @override
  String get name => 'group.key.distribution';

  final String conversationId;
  final int epoch;
  final String fromUserId;
  final String fromDeviceId;
  final String encryptedChainKey;
  final String nonce;
  final String version;

  static GroupKeyDistributionEvent? _tryParse(Map<String, dynamic> payload) {
    if (payload
        case {
          'conversationId': String conversationId,
          'epoch': int epoch,
          'fromUserId': String fromUserId,
          'fromDeviceId': String fromDeviceId,
          'encryptedChainKey': String encryptedChainKey,
          'nonce': String nonce,
          'version': String version,
        }
        when epoch >= 0 &&
            _allNonEmpty([
              conversationId,
              fromUserId,
              fromDeviceId,
              encryptedChainKey,
              version,
            ])) {
      return GroupKeyDistributionEvent(
        conversationId: conversationId,
        epoch: epoch,
        fromUserId: fromUserId,
        fromDeviceId: fromDeviceId,
        encryptedChainKey: encryptedChainKey,
        nonce: nonce,
        version: version,
      );
    }
    return null;
  }
}

enum GroupMembershipChange { join, leave }

final class GroupEpochBumpedEvent extends RealtimeEvent {
  const GroupEpochBumpedEvent({
    required this.conversationId,
    required this.epoch,
    required this.reason,
    required this.userId,
  });

  @override
  String get name => 'group.epoch.bumped';

  final String conversationId;
  final int epoch;
  final GroupMembershipChange reason;

  /// The member who joined or left.
  final String userId;

  static GroupEpochBumpedEvent? _tryParse(Map<String, dynamic> payload) {
    if (payload
        case {
          'conversationId': String conversationId,
          'epoch': int epoch,
          'reason': String rawReason,
          'userId': String userId,
        } when epoch >= 0 && _allNonEmpty([conversationId, userId])) {
      final reason = GroupMembershipChange.values.asNameMap()[rawReason];
      if (reason == null) {
        return null;
      }
      return GroupEpochBumpedEvent(
        conversationId: conversationId,
        epoch: epoch,
        reason: reason,
        userId: userId,
      );
    }
    return null;
  }
}

/// An ignored contract event or a name outside the contract, passed through
/// unvalidated for handlers that choose to look at it.
final class UnknownRealtimeEvent extends RealtimeEvent {
  const UnknownRealtimeEvent(this.name, this.payload);

  @override
  final String name;
  final Object? payload;
}

bool _isOptional<T>(Object? value) => value == null || value is T;

bool _isOptionalTimestamp(Object? value) {
  return value == null || (value is String && DateTime.tryParse(value) != null);
}

bool _allNonEmpty(List<String> values) => values.every((v) => v.isNotEmpty);
