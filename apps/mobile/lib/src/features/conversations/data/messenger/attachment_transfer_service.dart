import 'dart:async';
import 'dart:io';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/network/veil_api_client.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../../../attachments/data/media_blob_store.dart';
import '../conversation_models.dart';
import 'attachment_sealer.dart';
import 'conversation_crypto_router.dart';
import 'message_content_service.dart';
import 'messenger_api_mapper.dart';
import 'messenger_operation_runner.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'pending_messages.dart';
import 'unqueued_sends.dart';

enum AttachmentTransferPhase {
  staged,
  preparing,
  uploading,
  finalizing,
  failed,
  canceled,
}

class AttachmentTransferSnapshot {
  const AttachmentTransferSnapshot({
    required this.clientMessageId,
    required this.phase,
    required this.progress,
    this.errorMessage,
    this.filename,
    this.contentType,
    this.sizeBytes,
    required this.canRetry,
    required this.canCancel,
  });

  final String clientMessageId;
  final AttachmentTransferPhase phase;
  final double progress;
  final String? errorMessage;
  final String? filename;
  final String? contentType;
  final int? sizeBytes;
  final bool canRetry;
  final bool canCancel;
}

/// Attachment uploads. A queued attachment was sealed into the media folder
/// when it was sent (AttachmentSealer); only that ciphertext is uploaded,
/// and the message that points at it is encrypted once, after the upload
/// completed, with its disappearing timer stamped then (D18).
class AttachmentTransferService {
  AttachmentTransferService({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required VeilApiClient apiClient,
    required MessengerApiMapper mapper,
    required ConversationCryptoRouter crypto,
    required MessageContentService contents,
    required PendingMessages pending,
    required MessengerOperationRunner ops,
    MediaBlobStore? blobs,
    DateTime Function() expiryClock = DateTime.now,
  })  : _store = store,
        _session = session,
        _apiClient = apiClient,
        _mapper = mapper,
        _crypto = crypto,
        _contents = contents,
        _pending = pending,
        _blobsOrNull = blobs,
        _expiryClock = expiryClock;

  // Upload progress is kept in memory on every callback but written to the
  // cache only this often: a restart resumes from a ticket, not a byte.
  static const _progressWriteStep = 0.05;
  static const _progressWriteInterval = Duration(seconds: 1);

  final MessengerStateStore _store;
  final MessengerSessionContext _session;
  final VeilApiClient _apiClient;
  final MessengerApiMapper _mapper;
  final ConversationCryptoRouter _crypto;
  final MessageContentService _contents;
  final PendingMessages _pending;
  final MediaBlobStore? _blobsOrNull;
  // The relay-corrected clock disappearing expiries are stamped on.
  final DateTime Function() _expiryClock;
  final Map<String, AttachmentTransferSnapshot> _transfers = {};
  final Map<String, AttachmentUploadCancellationSignal> _activeUploads = {};

  AttachmentTransferSnapshot? transferFor(String clientMessageId) => _transfers[clientMessageId];

  void _track(
    String clientMessageId, {
    required AttachmentTransferPhase phase,
    required double progress,
    String? errorMessage,
    String? filename,
    String? contentType,
    int? sizeBytes,
    required bool canRetry,
    required bool canCancel,
  }) {
    _transfers[clientMessageId] = AttachmentTransferSnapshot(
      clientMessageId: clientMessageId,
      phase: phase,
      progress: progress.clamp(0, 1).toDouble(),
      errorMessage: errorMessage,
      filename: filename,
      contentType: contentType,
      sizeBytes: sizeBytes,
      canRetry: canRetry,
      canCancel: canCancel,
    );
  }

  /// Shows [draft]'s transfer in [phase] at its current progress.
  void trackDraft(
    String clientMessageId,
    AttachmentUploadDraft draft, {
    required AttachmentTransferPhase phase,
    String? errorMessage,
    required bool canRetry,
    required bool canCancel,
    double? progress,
  }) =>
      _track(
        clientMessageId,
        phase: phase,
        progress: progress ?? progressOf(draft),
        errorMessage: errorMessage,
        filename: draft.filename,
        contentType: draft.contentType,
        sizeBytes: draft.sizeBytes,
        canRetry: canRetry,
        canCancel: canCancel,
      );

  void forget(String clientMessageId) => _transfers.remove(clientMessageId);

  void cancelUpload(String clientMessageId) => _activeUploads.remove(clientMessageId)?.cancel();

  static double progressOf(AttachmentUploadDraft? draft) {
    if (draft == null || draft.sizeBytes <= 0) return 0;
    return (draft.bytesUploaded / draft.sizeBytes).clamp(0, 1).toDouble();
  }

  /// Tickets and uploads [pending]'s sealed blob, then encrypts the message
  /// that points at it, stamping its expiry from the chat's timer now. Each
  /// completed step is saved on the record, so a retry after a failure or a
  /// restart resumes from it; a message the user cancelled stops at the next
  /// step. The blob is never deleted here: it stays for the sender's bubble.
  Future<PendingMessageRecord> prepare(PendingMessageRecord pending) async {
    var draft = pending.attachmentUploadDraft;
    if (draft == null) return pending;
    final id = pending.clientMessageId;
    final conversation = _store.conversationById(pending.conversationId) ??
        (throw StateError('The target conversation is no longer available.'));
    final reference = draft.sealedReference;
    // A draft an older build queued (its placeholder frame encrypted, its
    // file found by a path, or sealed under an empty id no recipient can
    // open) is never sent as it is: the user attaches the file again.
    if (reference == null || reference.attachmentId.isEmpty || isOldFormatDraft(pending)) throw _invalid();
    // Found by the sealed id and digest, never by a stored path: an app
    // update moves the container. A blob that is gone is never made up.
    final blobPath =
        await _blobs.pathOf(conversation.id, reference.attachmentId, reference.sha256) ?? (throw _invalid());
    // A chat held since this was sealed uploads nothing until it is settled
    // (D16), as it seals nothing new.
    await _crypto.checkAttachmentSend(conversation);

    draft = await _ensureUploadTicket(draft);
    // Cancelled while it was ticketed, the saved record names no ticket for
    // discard() to release (D19): it is released here.
    if (_pending.isCanceled(id)) await _resetTicket(draft);
    _throwIfCanceled(id);
    pending = pending.copyWith(attachmentUploadDraft: draft);
    await _pending.save(pending);
    await _upload(pending, draft, blobPath);
    _throwIfCanceled(id);

    await _apiClient.completeUpload(_session.requireAuthed().accessToken, {
      'attachmentId': draft.attachmentId,
      'uploadStatus': 'uploaded',
    });
    _activeUploads.remove(id);
    _throwIfCanceled(id);
    trackDraft(id, draft, phase: AttachmentTransferPhase.finalizing, progress: 1, canRetry: false, canCancel: false);

    // Stamped now, on the relay's clock, as a text is when it is sent: a
    // stamp taken when the file was picked could pass during a slow upload
    // and take the message, its content and its blob with it.
    final seconds = draft.disappearAfterSeconds;
    final expiresAt = seconds == null ? null : _expiryClock().add(Duration(seconds: seconds));
    final kind = pending.envelope.messageKind;
    final body = kind == MessageKind.image ? '' : draft.filename;
    final envelope = await _crypto.encrypt(
      conversation: conversation,
      senderDeviceId: pending.senderDeviceId,
      body: body,
      messageKind: kind,
      expiresAt: expiresAt,
      attachment: reference,
    );
    if (expiresAt != null) {
      // In one step: the stored content, the blob's index entry and the
      // bubble; the queued record takes the envelope from the caller.
      await _contents.storeOutbound(
        conversationId: conversation.id,
        clientMessageId: id,
        senderDeviceId: pending.senderDeviceId,
        body: body,
        kind: kind,
        attachment: reference,
        expiresAt: expiresAt,
      );
      await _blobs.setExpiry(conversation.id, reference.attachmentId, expiresAt);
      _store.updateMessagesWhere(
        (message) => message.clientMessageId == id,
        (message) => message.copyWith(expiresAt: expiresAt),
        inConversation: conversation.id,
      );
    }
    return pending.copyWith(envelope: envelope, attachmentUploadDraft: null, state: MessageDeliveryState.pending);
  }

  /// Shows a queued attachment's transfer as its record stands: waiting, or
  /// failed (for good, or [afterFailure] until it is retried). The cross
  /// stays on a failed one, so it can go.
  void trackRecord(PendingMessageRecord pending, {bool afterFailure = false}) {
    final id = pending.clientMessageId;
    final failed = afterFailure || pending.state == MessageDeliveryState.failed;
    final phase = failed ? AttachmentTransferPhase.failed : AttachmentTransferPhase.staged;
    if (pending.attachmentUploadDraft case final draft?) {
      trackDraft(id, draft, phase: phase, errorMessage: pending.errorMessage, canRetry: failed, canCancel: true);
    } else if (pending.envelope.attachment case final reference?
        when pending.state == MessageDeliveryState.failed && reference.attachmentId.isNotEmpty) {
      // Uploaded and sealed, but the post failed: the same frame goes on a
      // retry, or the message goes on a cancel.
      _track(id,
          phase: phase,
          progress: 1,
          errorMessage: pending.errorMessage,
          contentType: reference.contentType,
          sizeBytes: reference.sizeBytes,
          canRetry: true,
          canCancel: true);
    }
  }

  /// Deletes what is left of the cancelled attachment [clientMessageId]
  /// once its send settled (D19): the relay is told its upload failed (an
  /// upload it completed too, which deletes the blob there), and its queued
  /// record, its stored content, its sealed blob and its bubble go.
  /// Nothing, when the send was acknowledged meanwhile.
  Future<void> discard(String clientMessageId) async {
    final latest = _pending[clientMessageId];
    if (latest == null) {
      forget(clientMessageId);
      return;
    }
    if (latest.attachmentUploadDraft case final draft? when draft.attachmentId != null) {
      await _resetTicket(draft);
    } else if (latest.attachmentUploadDraft == null && latest.envelope.ciphertext.isNotEmpty) {
      if (latest.envelope.attachment?.attachmentId case final id? when id.isNotEmpty) await _releaseUpload(id);
    }
    // The record first, so a crash in between never leaves a record without
    // its blob. Its content and blob go even when the cache refuses that
    // write (or the record never reached it: OutboxService.sendAttachment):
    // withoutDiscarded drops a record left behind at the next start, rather
    // than send what was cancelled.
    try {
      await _pending.remove(clientMessageId);
    } finally {
      await _contents.discardOutbound(clientMessageId);
      final conversationId = latest.conversationId;
      if (blobIdOf(latest) case final attachmentId? when attachmentId.isNotEmpty) {
        await _blobs.delete(conversationId, attachmentId);
      }
      _store.setMessages(conversationId, [
        for (final message in _store.messagesOf(conversationId))
          if (message.clientMessageId != clientMessageId) message,
      ]);
      _store.syncPreviewFromMessages(conversationId);
      forget(clientMessageId);
      _store.changed();
    }
  }

  /// [records] as hydrate keeps them, and this device's unsent leftovers
  /// dropped (see keptOnRestore).
  Future<List<PendingMessageRecord>> withoutDiscarded(List<PendingMessageRecord> records, {DateTime? startedAt}) =>
      keptOnRestore(records,
          contents: _contents, pending: _pending, blobs: _blobsOrNull, dropBubble: _dropBubble, startedAt: startedAt);

  void _dropBubble(String conversationId, String clientMessageId) {
    final messages = _store.messagesOf(conversationId);
    if (!messages.any((message) => message.clientMessageId == clientMessageId)) return;
    _store.setMessages(conversationId, [
      for (final message in messages)
        if (message.clientMessageId != clientMessageId) message,
    ]);
    _store.syncPreviewFromMessages(conversationId);
  }

  void cancelUploads() {
    for (final signal in _activeUploads.values) {
      signal.cancel();
    }
    _activeUploads.clear();
  }

  /// Forgets every transfer shown.
  void clear() => _transfers.clear();

  Future<void> _upload(PendingMessageRecord pending, AttachmentUploadDraft draft, String blobPath) async {
    final clientMessageId = pending.clientMessageId;
    final signal = AttachmentUploadCancellationSignal();
    _activeUploads[clientMessageId] = signal;
    trackDraft(clientMessageId, draft, phase: AttachmentTransferPhase.uploading, canRetry: false, canCancel: true);
    var writtenProgress = progressOf(draft);
    var writtenAt = DateTime.now();
    try {
      await _apiClient.uploadEncryptedBlobFile(
        uploadUrl: draft.uploadUrl!,
        headers: draft.uploadHeaders,
        file: File(blobPath),
        cancellationSignal: signal,
        onProgress: (sentBytes, totalBytes) {
          final current = _pending[clientMessageId];
          final currentDraft = current?.attachmentUploadDraft;
          if (current == null || currentDraft == null) return;
          final now = DateTime.now();
          final updatedDraft = currentDraft.copyWith(bytesUploaded: sentBytes, lastUpdatedAt: now);
          final updated = current.copyWith(attachmentUploadDraft: updatedDraft);
          final progress = progressOf(updatedDraft);
          if (progress - writtenProgress >= _progressWriteStep || now.difference(writtenAt) >= _progressWriteInterval) {
            writtenProgress = progress;
            writtenAt = now;
            _pending.save(updated).ignore();
          } else {
            _pending.put(updated);
          }
          _track(
            clientMessageId,
            phase: AttachmentTransferPhase.uploading,
            progress: totalBytes == 0 ? 0 : sentBytes / totalBytes,
            filename: updatedDraft.filename,
            contentType: updatedDraft.contentType,
            sizeBytes: updatedDraft.sizeBytes,
            canRetry: false,
            canCancel: true,
          );
          _store.changed();
        },
      );
    } catch (error) {
      _activeUploads.remove(clientMessageId);
      // A cancelled message releases its ticket once, as it is discarded.
      if (!_pending.isCanceled(clientMessageId)) {
        final reset = await _resetTicket(draft);
        await _pending.save(pending.copyWith(attachmentUploadDraft: reset));
      }
      rethrow;
    }
  }

  Future<AttachmentUploadDraft> _ensureUploadTicket(AttachmentUploadDraft draft) async {
    if (draft.hasUploadTicket && !draft.uploadTicketExpired) return draft;
    final resetDraft = await _resetTicket(draft, releaseRemoteObject: draft.hasUploadTicket);
    final sealedId = resetDraft.sealedReference!.attachmentId;
    final response = await _apiClient.createUploadTicket(_session.requireAuthed().accessToken, {
      'attachmentId': sealedId,
      // The relay only ever holds ciphertext. The real type travels in the
      // sealed reference ('ct') alone, as the web client does it.
      'contentType': 'application/octet-stream',
      'sizeBytes': resetDraft.sizeBytes,
      'sha256': resetDraft.sha256,
    });
    final ticket = _mapper.uploadTicket(response) ?? (throw StateError('Unexpected response shape'));
    // A ticket for any other id would carry a blob no recipient can open.
    if (ticket.attachmentId != sealedId) {
      throw StateError('The relay ticketed a different attachment id than the one sealed.');
    }
    return resetDraft.copyWith(
      attachmentId: sealedId,
      storageKey: ticket.storageKey,
      uploadUrl: ticket.uploadUrl,
      uploadHeaders: ticket.headers,
      uploadExpiresAt: ticket.expiresAt,
      bytesUploaded: 0,
      lastUpdatedAt: DateTime.now(),
    );
  }

  // Drops [draft]'s ticket, telling the relay the upload failed when
  // [releaseRemoteObject].
  Future<AttachmentUploadDraft> _resetTicket(AttachmentUploadDraft draft, {bool releaseRemoteObject = true}) async {
    if (releaseRemoteObject && draft.attachmentId != null) await _releaseUpload(draft.attachmentId!);
    return draft.copyWith(
      attachmentId: null,
      storageKey: null,
      uploadUrl: null,
      uploadHeaders: const <String, String>{},
      uploadExpiresAt: null,
      bytesUploaded: 0,
      lastUpdatedAt: DateTime.now(),
    );
  }

  // Tells the relay [attachmentId]'s upload failed, which deletes its blob
  // there. Best effort: a relay sweep fails stale pending uploads.
  Future<void> _releaseUpload(String attachmentId) async {
    final session = _session.authed;
    if (session == null) return;
    try {
      await _apiClient.completeUpload(session.accessToken, {'attachmentId': attachmentId, 'uploadStatus': 'failed'});
    } catch (_) {
      // Best effort.
    }
  }

  MediaBlobStore get _blobs => _blobsOrNull ?? (throw StateError('Sealed attachments have no folder here.'));

  void _throwIfCanceled(String clientMessageId) {
    if (_pending.isCanceled(clientMessageId)) {
      throw VeilApiException('Attachment upload canceled.', code: 'attachment_upload_canceled');
    }
  }

  static VeilApiException _invalid() => VeilApiException(
        "This attachment can't be sent. Attach the file again.",
        code: 'attachment_upload_invalid',
      );
}
