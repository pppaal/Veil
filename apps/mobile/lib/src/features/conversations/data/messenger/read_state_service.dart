import '../../../../core/notifications/local_notification_service.dart';
import 'message_content_service.dart';
import 'messenger_state_store.dart';
import 'receipt_service.dart';

/// What has been read on this phone, and what the Chats list counts.
///
/// For now it only keeps the chat the user is looking at, as the messenger
/// always has; read marks, counts, the unread divider and when a read
/// receipt goes come with the unread work.
class ReadStateService implements MessengerStateObserver {
  ReadStateService({
    required MessengerStateStore store,
    required ReceiptService receipts,
    required LocalNotificationService? notifications,
    required MessageContentService contents,
    required this.receiptsWithheld,
    required DateTime Function() now,
  }) : _store = store;

  final MessengerStateStore _store;

  /// Whether no read receipt may go for [conversationId] now: who its peer
  /// is waits for the user, or it is a 1:1 with someone blocked
  /// (MessengerServices.receiptsWithheld).
  final bool Function(String conversationId) receiptsWithheld;

  /// The conversation the user is looking at right now, or null.
  void setActive(String? conversationId) => _store.activeConversationId = conversationId;

  /// A chat screen ([viewer]) started showing [conversationId].
  void beginViewing(String conversationId, {required Object viewer}) {}

  /// [viewer] stopped showing [conversationId].
  void endViewing(String conversationId, {required Object viewer}) {}

  /// Forgets everything held for the identity that left.
  void clear() {}

  @override
  void conversationsChanged() {}

  @override
  void messagesChanged(String conversationId) {}

  @override
  void pagingChanged(String conversationId) {}
}
