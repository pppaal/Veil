// The conversation and message models live in core/domain so the storage
// layer can use them; this library keeps exporting them for its importers.
export '../../../core/domain/chat_message.dart';
export '../../../core/domain/conversation_preview.dart';
export '../../../core/domain/message_search.dart';

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
