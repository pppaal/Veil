import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import 'message_content_service.dart';
import 'messenger_state_store.dart';

/// The opened content of each conversation's latest message, for the
/// conversation list. Read through the content store, never by decrypting:
/// a message's single decrypt belongs to MessageContentService.
class DecryptedMessageCache {
  DecryptedMessageCache({required MessageContentService contents, required MessengerStateStore store})
      : _contents = contents,
        _store = store;

  final MessageContentService _contents;
  final MessengerStateStore _store;
  final Map<String, MessageContentRecord> _latest = {};

  /// Body of the latest message when it is text that opened; null otherwise.
  String? previewFor(String conversationId) {
    final content = _latest[conversationId];
    return content?.kind == MessageKind.text ? content!.body : null;
  }

  /// Decrypted kind of the latest message, or null until it opened. Never
  /// the envelope's unauthenticated kind.
  MessageKind? kindFor(String conversationId) => _latest[conversationId]?.kind;

  /// Re-reads the latest message of [conversationId] from the content store.
  Future<void> refresh(String conversationId) async {
    final latest = _store.messagesOf(conversationId).lastOrNull;
    final content = latest == null ? null : (await _contents.storedFor([latest]))[latest.id];
    // A newer message arrived while this one was read.
    if (_store.messagesOf(conversationId).lastOrNull?.id != latest?.id) return;
    final opened = content?.status == MessageContentStatus.ok ? content : null;
    final previous = _latest[conversationId];
    if (previous?.kind == opened?.kind && previous?.body == opened?.body) return;
    opened == null ? _latest.remove(conversationId) : _latest[conversationId] = opened;
    _store.changed();
  }

  void clear() => _latest.clear();
}
