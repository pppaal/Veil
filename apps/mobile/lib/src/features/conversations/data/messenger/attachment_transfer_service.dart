import 'dart:async';
import 'dart:io';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/errors/user_facing_error.dart';
import '../../../../core/network/veil_api_client.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../../../attachments/data/attachment_temp_file_store.dart';
import '../conversation_models.dart';
import 'conversation_crypto_router.dart';
import 'message_content_service.dart';
import 'messenger_api_mapper.dart';
import 'messenger_operation_runner.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'pending_messages.dart';

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

/// What an attachment message says in its body; the file is the payload.
const attachmentMessageBody = 'Encrypted attachment';

/// Attachment uploads and download tickets. A staged file is sealed on
/// this device and only its ciphertext is ever uploaded; the message that
/// points at it is encrypted once the upload completed.
class AttachmentTransferService {
  AttachmentTransferService({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required VeilApiClient apiClient,
    required MessengerApiMapper mapper,
    required ConversationCryptoRouter crypto,
    required MessageContentService contents,
    required PendingMessages pending,
    required AttachmentTempFileStore? tempStore,
    required MessengerOperationRunner ops,
  })  : _store = store,
        _session = session,
        _apiClient = apiClient,
        _mapper = mapper,
        _crypto = crypto,
        _contents = contents,
        _pending = pending,
        _tempStore = tempStore,
        _ops = ops;

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
  final AttachmentTempFileStore? _tempStore;
  final MessengerOperationRunner _ops;
  final Map<String, AttachmentTransferSnapshot> _transfers = {};
  final Map<String, String> _downloadErrors = {};
  final Set<String> _resolving = {};
  final Map<String, AttachmentUploadCancellationSignal> _activeUploads = {};

  AttachmentTransferSnapshot? transferFor(String clientMessageId) => _transfers[clientMessageId];

  bool isResolving(String attachmentId) => _resolving.contains(attachmentId);

  String? downloadError(String attachmentId) => _downloadErrors[attachmentId];

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
  }) =>
      _track(
        clientMessageId,
        phase: phase,
        progress: progressOf(draft),
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

  Future<AttachmentTempBlob> stage({required String filename, int sizeBytes = 2048}) =>
      _requireTempStore().createOpaqueBlob(filename: filename, sizeBytes: sizeBytes);

  static String guessContentType(String filename) {
    final normalized = filename.toLowerCase();
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) return 'image/jpeg';
    if (normalized.endsWith('.png')) return 'image/png';
    if (normalized.endsWith('.webp')) return 'image/webp';
    if (normalized.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  /// The download URL for [attachmentId], or null when it cannot be had;
  /// the failure is kept for [downloadError].
  Future<String?> downloadUrl(String attachmentId) async {
    final session = _session.authed;
    if (session == null) return null;

    _downloadErrors.remove(attachmentId);
    _resolving.add(attachmentId);
    _store.changed();
    try {
      final response = await _apiClient.getDownloadTicket(session.accessToken, attachmentId);
      return _mapper.downloadUrl(response) ?? (throw StateError('Unexpected response shape'));
    } catch (error) {
      await _ops.handleSecurityException(error);
      final message = formatUserFacingError(error);
      _downloadErrors[attachmentId] = message;
      _ops.showMessage(message);
      return null;
    } finally {
      _resolving.remove(attachmentId);
      _store.changed();
    }
  }

  /// Seals, tickets and uploads [pending]'s attachment, then encrypts the
  /// message that points at it. Each completed step is saved on the record,
  /// so a retry after a failure or a restart resumes from it.
  Future<PendingMessageRecord> prepare(PendingMessageRecord pending) async {
    var draft = pending.attachmentUploadDraft;
    if (draft == null) return pending;
    final tempStore = _requireTempStore();
    final conversation = _store.conversationById(pending.conversationId) ??
        (throw StateError('The target conversation is no longer available.'));

    if (draft.sealedReference == null) {
      final (sealedDraft, plaintextPath) = await _seal(draft, conversation, tempStore);
      draft = sealedDraft;
      pending = pending.copyWith(attachmentUploadDraft: draft);
      await _pending.save(pending);
      await tempStore.deleteTempFile(plaintextPath);
    } else if (draft.sealedReference!.attachmentId.isEmpty) {
      // Sealed by an older build under an empty id, which no recipient can
      // open, and the plaintext was deleted once sealed, so it cannot be
      // re-sealed either. Failing it for good lets the user attach it again.
      throw VeilApiException(
        'This attachment was prepared by an older version of VEIL. Attach the file again.',
        code: 'attachment_upload_invalid',
      );
    }

    draft = await _ensureUploadTicket(draft);
    pending = pending.copyWith(attachmentUploadDraft: draft);
    await _pending.save(pending);
    await _upload(pending, draft);

    final session = _session.requireAuthed();
    await _apiClient.completeUpload(session.accessToken, {
      'attachmentId': draft.attachmentId,
      'uploadStatus': 'uploaded',
    });
    _activeUploads.remove(pending.clientMessageId);
    _track(
      pending.clientMessageId,
      phase: AttachmentTransferPhase.finalizing,
      progress: 1,
      filename: draft.filename,
      contentType: draft.contentType,
      sizeBytes: draft.sizeBytes,
      canRetry: false,
      canCancel: false,
    );

    final attachment = draft.sealedReference!;
    await _contents.storeOutbound(
      conversationId: conversation.id,
      clientMessageId: pending.clientMessageId,
      senderDeviceId: pending.senderDeviceId,
      body: attachmentMessageBody,
      kind: MessageKind.file,
      attachment: attachment,
      expiresAt: pending.envelope.expiresAt,
    );
    final envelope = await _crypto.encrypt(
      conversation: conversation,
      senderDeviceId: pending.senderDeviceId,
      body: attachmentMessageBody,
      messageKind: MessageKind.file,
      expiresAt: pending.envelope.expiresAt,
      attachment: attachment,
    );

    await tempStore.deleteTempFile(draft.tempFilePath);
    return pending.copyWith(envelope: envelope, attachmentUploadDraft: null, state: MessageDeliveryState.pending);
  }

  void cancelUploads() {
    for (final signal in _activeUploads.values) {
      signal.cancel();
    }
    _activeUploads.clear();
  }

  /// Forgets every transfer shown and every download outcome.
  void clear() {
    _resolving.clear();
    _downloadErrors.clear();
    _transfers.clear();
  }

  Future<void> _upload(PendingMessageRecord pending, AttachmentUploadDraft draft) async {
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
        file: File(draft.tempFilePath!),
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
      final reset = await _resetTicket(draft);
      await _pending.save(pending.copyWith(attachmentUploadDraft: reset));
      rethrow;
    }
  }

  // Encrypts the staged file and swaps it for the ciphertext. The reference
  // stays on the draft exactly as sealed, so a retry after a restart
  // re-tickets the same id for the same bytes.
  Future<(AttachmentUploadDraft, String)> _seal(
    AttachmentUploadDraft draft,
    ConversationPreview conversation,
    AttachmentTempFileStore tempStore,
  ) async {
    final staged = await tempStore.createOpaqueBlob(
      filename: draft.filename,
      sizeBytes: draft.sizeBytes,
      existingPath: draft.tempFilePath,
    );
    final cipher = await _crypto.sealAttachment(
      conversation: conversation,
      contentType: draft.contentType,
      plaintext: await File(staged.path).readAsBytes(),
    );
    final sealedFile = File('${staged.path}.sealed');
    await sealedFile.writeAsBytes(cipher.ciphertext, flush: true);
    final sealed = await tempStore.createOpaqueBlob(
      filename: draft.filename,
      sizeBytes: cipher.ciphertext.length,
      existingPath: sealedFile.path,
    );
    final sealedDraft = draft.copyWith(
      tempFilePath: sealed.path,
      sizeBytes: sealed.sizeBytes,
      sha256: sealed.sha256,
      sealedReference: cipher.reference,
      lastUpdatedAt: DateTime.now(),
    );
    return (sealedDraft, staged.path);
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
  // [releaseRemoteObject] (best effort: a relay sweep fails stale uploads).
  Future<AttachmentUploadDraft> _resetTicket(AttachmentUploadDraft draft, {bool releaseRemoteObject = true}) async {
    final session = _session.authed;
    if (releaseRemoteObject && draft.attachmentId != null && session != null) {
      try {
        await _apiClient.completeUpload(session.accessToken, {
          'attachmentId': draft.attachmentId,
          'uploadStatus': 'failed',
        });
      } catch (_) {
        // Cleanup is best-effort. A later backend sweep still marks stale pending uploads failed.
      }
    }
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

  AttachmentTempFileStore _requireTempStore() =>
      _tempStore ?? (throw StateError('Local attachment staging is unavailable on this device.'));
}
