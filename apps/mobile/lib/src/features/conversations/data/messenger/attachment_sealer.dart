import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as digest;

import '../../../../core/crypto/attachment/attachment_cipher_v2.dart';
import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/crypto/random_source.dart';
import '../../../../core/network/veil_api_exception.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../../../../core/util/uuid_v4.dart';
import '../../../attachments/data/media_blob_store.dart';
import '../../../attachments/domain/outgoing_attachment.dart';
import '../../../../core/errors/user_facing_error.dart';
import '../conversation_models.dart';
import 'message_content_service.dart';

/// A staged photo or file, sealed under a fresh id and kept in the media
/// folder until its message is gone.
class SealedAttachment {
  const SealedAttachment({required this.reference, required this.sealedSize, required this.sealedSha256Hex});

  /// The pointer (v2) the message carries: the id, key, nonce, digest,
  /// content type and the plaintext's size.
  final AttachmentReference reference;

  /// The ciphertext's length and SHA-256 (hex), which the upload ticket
  /// names: the relay only ever holds that blob.
  final int sealedSize;
  final String sealedSha256Hex;
}

/// Seals the plaintext the attach flow staged (D16): one isolate reads the
/// file, seals it with pointer v2 under a fresh random id and writes the
/// ciphertext to a reserved part file of the media folder, so neither the
/// plaintext nor the ciphertext crosses into the UI isolate. The blob is
/// then committed with no expiry (D18 stamps one after the upload) and the
/// plaintext deleted, whatever happened.
class AttachmentSealer {
  AttachmentSealer({required MediaBlobStore? blobs, required MessageContentService contents})
      : _blobsOrNull = blobs,
        _contents = contents;

  final MediaBlobStore? _blobsOrNull;
  final MessageContentService _contents;

  MediaBlobStore get _blobs => _blobsOrNull ?? (throw StateError('Sealed attachments have no folder here.'));

  /// Runs [precheck] (the router's: a held conversation throws there and
  /// nothing is sealed), seals, and stores the message's content under
  /// [clientMessageId] with no expiry (D17): kind image with an empty body,
  /// or kind file with the sanitized name, and the sealed pointer, so the
  /// sender's bubble shows the photo or the file from the first frame. The
  /// staged plaintext is deleted either way.
  Future<SealedAttachment> sealAndStore({
    required String conversationId,
    required String clientMessageId,
    required OutgoingAttachment attachment,
    required String Function() senderDeviceId,
    required Future<void> Function() precheck,
  }) async {
    final sealed = await _seal(conversationId: conversationId, attachment: attachment, precheck: precheck);
    try {
      await _contents.storeOutbound(
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        senderDeviceId: senderDeviceId(),
        body: attachment.name,
        kind: messageKindOf(attachment),
        attachment: sealed.reference,
      );
    } catch (_) {
      await _blobs.delete(conversationId, sealed.reference.attachmentId);
      rethrow;
    }
    return sealed;
  }

  Future<SealedAttachment> _seal({
    required String conversationId,
    required OutgoingAttachment attachment,
    required Future<void> Function() precheck,
  }) async {
    try {
      await precheck();
      if (!await File(attachment.path).exists()) throw const PathNotFoundException('', OSError());
      final partPath = await _blobs.reservePartPath();
      final ({AttachmentReference reference, int size, String sha256Hex}) sealed;
      try {
        sealed = await sealStagedFileInIsolate(attachment.path, partPath, attachment.contentType);
        await _blobs.commit(
          partPath: partPath,
          conversationId: conversationId,
          attachmentId: sealed.reference.attachmentId,
          digest: sealed.reference.sha256,
          sizeBytes: sealed.size,
        );
      } catch (_) {
        await _deleteQuietly(partPath);
        rethrow;
      }
      return SealedAttachment(reference: sealed.reference, sealedSize: sealed.size, sealedSha256Hex: sealed.sha256Hex);
    } on PathNotFoundException {
      throw VeilApiException('The staged file is gone.', code: 'attachment_upload_invalid');
    } finally {
      await _deleteQuietly(attachment.path);
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Gone already.
    }
  }
}

/// [sealStagedFile] in an isolate of its own. Top level, so the isolate is
/// handed the three paths and nothing else of the caller's.
Future<({AttachmentReference reference, int size, String sha256Hex})> sealStagedFileInIsolate(
  String plaintextPath,
  String partPath,
  String contentType,
) =>
    Isolate.run(() => sealStagedFile(plaintextPath, partPath, contentType));

/// Seals the plaintext at [plaintextPath] with pointer v2 under a fresh
/// random id, writes the ciphertext to [partPath], and returns only the
/// reference and the blob's size and digest. Run in an isolate of its own
/// (AttachmentSealer), so neither the plaintext nor the ciphertext crosses
/// into the caller's.
Future<({AttachmentReference reference, int size, String sha256Hex})> sealStagedFile(
  String plaintextPath,
  String partPath,
  String contentType,
) async {
  final plaintext = await File(plaintextPath).readAsBytes();
  final cipher = await encryptAttachmentV2(
    attachmentId: randomUuidV4(),
    storageKey: '',
    contentType: contentType,
    plaintext: plaintext,
    random: SecureRandomSource(),
  );
  plaintext.fillRange(0, plaintext.length, 0);
  final blob = cipher.ciphertext;
  await File(partPath).writeAsBytes(blob, flush: true);
  return (reference: cipher.reference, size: blob.length, sha256Hex: digest.sha256.convert(blob).toString());
}

/// Whether [pending] is a photo or file message.
bool isAttachmentRecord(PendingMessageRecord pending) =>
    pending.attachmentUploadDraft != null || pending.envelope.attachment != null;

/// The sealed blob [pending] names, if it is an attachment.
String? blobIdOf(PendingMessageRecord pending) =>
    pending.attachmentUploadDraft?.sealedReference?.attachmentId ?? pending.envelope.attachment?.attachmentId;

/// [record], an older build's draft, failed for good (D22): it cannot be sent
/// as it is. Its staged and sealed files go with hydrate's cleanup of
/// staging.
PendingMessageRecord failedOldDraft(PendingMessageRecord record) => record.copyWith(
      state: MessageDeliveryState.failed,
      nextRetryAt: null,
      errorMessage: formatUserFacingError(VeilApiException('Attach the file again.', code: 'attachment_upload_invalid')),
    );

/// The kind a sent photo or file message has (D9, D13).
MessageKind messageKindOf(OutgoingAttachment attachment) =>
    attachment.kind == OutgoingAttachmentKind.photo ? MessageKind.image : MessageKind.file;

/// The envelope a queued attachment carries until its upload is done
/// (D17). It is never sent: its ciphertext is empty (the outbox refuses to
/// post one), it has no expiry, and its pointer names only the sealed blob,
/// so the bubble and the cleanup can find it.
CryptoEnvelope placeholderEnvelope({
  required ConversationPreview conversation,
  required String senderDeviceId,
  required MessageKind kind,
  required String attachmentId,
}) =>
    CryptoEnvelope(
      version: '',
      conversationId: conversation.id,
      senderDeviceId: senderDeviceId,
      recipientUserId: conversation.type == ConversationType.group ? '' : conversation.recipientBundle.userId,
      ciphertext: '',
      nonce: '',
      messageKind: kind,
      attachment: blobPointer(attachmentId),
    );

/// A pointer that names a sealed blob and nothing else.
AttachmentReference blobPointer(String attachmentId) => AttachmentReference(
      attachmentId: attachmentId,
      storageKey: '',
      contentType: '',
      sizeBytes: 0,
      sha256: '',
      encryptedKey: '',
      nonce: '',
    );

/// Whether [pending] is an attachment draft an older build queued: its
/// placeholder frame was encrypted (and its file staged by path), which no
/// build that ever shipped did (D22).
bool isOldFormatDraft(PendingMessageRecord pending) =>
    pending.attachmentUploadDraft != null && pending.envelope.ciphertext.isNotEmpty;

/// [pending]'s placeholder envelope with its blob pointer, which the cache
/// does not keep for a draft.
PendingMessageRecord withBlobPointer(PendingMessageRecord pending) {
  final envelope = pending.envelope;
  final id = pending.attachmentUploadDraft?.sealedReference?.attachmentId;
  if (id == null || id.isEmpty || envelope.attachment != null || envelope.ciphertext.isNotEmpty) return pending;
  return pending.copyWith(
    envelope: CryptoEnvelope(
      version: envelope.version,
      conversationId: envelope.conversationId,
      senderDeviceId: envelope.senderDeviceId,
      recipientUserId: envelope.recipientUserId,
      ciphertext: envelope.ciphertext,
      nonce: envelope.nonce,
      messageKind: envelope.messageKind,
      expiresAt: envelope.expiresAt,
      attachment: blobPointer(id),
    ),
  );
}

/// The upload draft of a freshly sealed attachment: what the upload needs
/// and nothing about where the file was. Its blob is found again through
/// the media store by the sealed id and digest (D22).
AttachmentUploadDraft sealedDraft(
  OutgoingAttachment attachment,
  SealedAttachment sealed, {
  required Duration? disappearAfter,
}) =>
    AttachmentUploadDraft(
      filename: attachment.name,
      contentType: sealed.reference.contentType,
      sizeBytes: sealed.sealedSize,
      sha256: sealed.sealedSha256Hex,
      sealedReference: sealed.reference,
      disappearAfterSeconds: disappearAfter?.inSeconds,
      lastUpdatedAt: DateTime.now(),
    );
