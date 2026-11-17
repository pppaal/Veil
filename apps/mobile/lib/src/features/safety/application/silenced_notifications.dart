import '../../../core/domain/conversation_preview.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../data/blocked_accounts.dart';
import '../data/conversation_mutes.dart';

/// Whether a new message in [conversation] (listed as [conversationId])
/// raises no notification on this phone: the chat is muted, or it is a 1:1
/// with someone the user blocked. The server refuses what a blocked account
/// sends from the moment of the block, but a message it took before can
/// still arrive; it is kept like any other, without a notification.
bool conversationSilenced(
  String conversationId,
  ConversationPreview? conversation, {
  required ConversationMutes mutes,
  required BlockedAccounts blocked,
}) {
  if (mutes.isMuted(conversationId)) return true;
  return conversation != null &&
      conversation.type == ConversationType.direct &&
      blocked.isBlocked(conversation.recipientBundle.userId);
}

/// The notifications the messenger raises, less those of the chats
/// [isSilenced] names. Everything else goes to [inner] as it is.
class SilencedNotifications implements LocalNotificationService {
  SilencedNotifications(this._inner, {required bool Function(String conversationId) isSilenced})
      : _isSilenced = isSilenced;

  final LocalNotificationService _inner;
  final bool Function(String conversationId) _isSilenced;

  @override
  void Function(String? conversationId)? get onNotificationTapped => _inner.onNotificationTapped;

  @override
  set onNotificationTapped(void Function(String? conversationId)? handler) => _inner.onNotificationTapped = handler;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<bool> requestPermission() => _inner.requestPermission();

  @override
  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    if (_isSilenced(conversationId)) return;
    await _inner.showMessageNotification(conversationId: conversationId, title: title, body: body);
  }

  // Muted or not: one raised before the mute still goes when it is read.
  @override
  Future<void> cancelConversation(String conversationId) => _inner.cancelConversation(conversationId);
}
