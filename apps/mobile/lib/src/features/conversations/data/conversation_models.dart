// The conversation and message models live in core/domain so the storage
// layer can use them; this library keeps exporting them for its importers.
export '../../../core/domain/chat_message.dart';
export '../../../core/domain/conversation_preview.dart';
export '../../../core/domain/message_search.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum CallType { voice, video }

enum CallStatus { ringing, active, ended, missed, declined }

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
// Navigation
// ---------------------------------------------------------------------------

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
