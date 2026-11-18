import '../../../../core/storage/conversation_cache_service.dart';
import '../../../attachments/data/media_blob_store.dart';
import '../conversation_models.dart';
import 'attachment_sealer.dart';
import 'message_content_service.dart';
import 'pending_messages.dart';

/// What hydrate keeps of [records], the queue the cache held, and what of
/// this device's unsent messages it drops for good.
///
/// Dropped from the queue: every attachment the user cancelled whose
/// record the cache would not drop (discard deleted its stored content and
/// blob). It is neither sent nor shown again, and its row goes now. One
/// whose blob alone is gone stays, and fails for good if sent.
///
/// Then, with [startedAt] (when this hydrate began): everything this device
/// stored for a message of its own that no record queues, neither in the
/// cache nor in [pending]: the app stopped between sealing a photo or file
/// and writing its record, or the cache refused a text's record. Nothing
/// would ever send it, so its stored content (a photo's or file's key with
/// it), its sealed blob and the bubble the cache kept for it ([dropBubble])
/// go now. Only content stored in an earlier second than [startedAt]
/// counts, so a send under way while this runs is never taken.
Future<List<PendingMessageRecord>> keptOnRestore(
  List<PendingMessageRecord> records, {
  required MessageContentService contents,
  required PendingMessages pending,
  required MediaBlobStore? blobs,
  required void Function(String conversationId, String clientMessageId) dropBubble,
  DateTime? startedAt,
}) async {
  bool checked(PendingMessageRecord record) => isAttachmentRecord(record) && !isOldFormatDraft(record);
  ChatMessage echoOf(PendingMessageRecord record) => ChatMessage(
      id: 'local-${record.clientMessageId}',
      clientMessageId: record.clientMessageId,
      senderDeviceId: record.senderDeviceId,
      sentAt: record.createdAt,
      envelope: record.envelope);
  final stored = await contents.storedFor([for (final record in records) if (checked(record)) echoOf(record)]);
  final kept = <PendingMessageRecord>[];
  for (final record in records) {
    if (!checked(record) || stored.containsKey('local-${record.clientMessageId}')) {
      kept.add(record);
    } else {
      await pending.drop(record.clientMessageId).catchError((Object _) {});
      final id = blobIdOf(record);
      if (id != null && id.isNotEmpty) await blobs?.delete(record.conversationId, id).catchError((Object _) {});
    }
  }
  if (startedAt != null) {
    await _dropUnqueued(records,
        contents: contents, pending: pending, blobs: blobs, dropBubble: dropBubble, startedAt: startedAt);
  }
  return kept;
}

Future<void> _dropUnqueued(
  List<PendingMessageRecord> records, {
  required MessageContentService contents,
  required PendingMessages pending,
  required MediaBlobStore? blobs,
  required void Function(String conversationId, String clientMessageId) dropBubble,
  required DateTime startedAt,
}) async {
  final queued = {for (final record in [...records, ...pending.all]) record.clientMessageId};
  // The cache keeps whole seconds: content of startedAt's own second may be
  // a send that began after it.
  final before = startedAt.subtract(Duration(microseconds: startedAt.microsecondsSinceEpoch % Duration.microsecondsPerSecond));
  for (final content in await contents.unqueuedOutbound().catchError((Object _) => const <MessageContentRecord>[])) {
    final id = content.clientMessageId;
    if (id == null || queued.contains(id) || !content.createdAt.isBefore(before)) continue;
    await contents.discardOutbound(id).catchError((Object _) {});
    dropBubble(content.conversationId, id);
    final attachmentId = content.attachment?.attachmentId;
    if (attachmentId != null && attachmentId.isNotEmpty) {
      await blobs?.delete(content.conversationId, attachmentId).catchError((Object _) {});
    }
  }
}
