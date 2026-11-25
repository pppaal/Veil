import 'local_notice.dart';
import 'message_content_service.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';

/// Inserts the notices this device writes into a conversation by itself.
class LocalNoticeWriter {
  LocalNoticeWriter({
    required MessengerStateStore store,
    required MessageContentService contents,
    required MessengerSessionContext session,
    required Future<void> Function() flush,
  })  : _store = store,
        _contents = contents,
        _session = session,
        _flush = flush;

  final MessengerStateStore _store;
  final MessageContentService _contents;
  final MessengerSessionContext _session;
  final Future<void> Function() _flush;

  /// Inserts [notice] into [conversationId] unless it is already there.
  Future<void> write(String conversationId, LocalNotice? notice) async {
    if (notice == null || _store.messagesOf(conversationId).any((message) => message.id == notice.message.id)) return;
    await _contents.storeLocalNotice(notice.message, notice.code);
    if (_session.isClosed) return;
    _store.mergeMessages(conversationId, [notice.message]);
    // Written at once, not on the debounced flush: the event behind a
    // notice (a device admitted, a key change) is not raised again after a
    // restart, so a notice lost to a crash would be lost for good.
    await _flush();
  }
}
