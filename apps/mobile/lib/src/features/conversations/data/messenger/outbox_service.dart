import 'dart:async';
import 'dart:math';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/errors/user_facing_error.dart';
import '../../../../core/network/veil_api_client.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../conversation_models.dart';
import '../group_sender_key_coordinator.dart';
import 'attachment_transfer_service.dart';
import 'conversation_crypto_router.dart';
import 'conversation_peer_bindings.dart';
import 'identity_trust.dart';
import 'message_content_service.dart';
import 'message_merge.dart';
import 'messenger_api_mapper.dart';
import 'messenger_operation_runner.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'pending_messages.dart';
import 'retry_policy.dart';

/// Messages on their way to the relay. A message is encrypted and queued
/// at once, shown as pending, and sent oldest first; a send that fails is
/// retried on a schedule (see retry_policy.dart) or left for the user.
class OutboxService {
  OutboxService({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required VeilApiClient apiClient,
    required MessengerApiMapper mapper,
    required ConversationCryptoRouter crypto,
    required MessageContentService contents,
    required PendingMessages pending,
    required AttachmentTransferService attachments,
    required MessengerOperationRunner ops,
    Duration retrySweepInterval = const Duration(seconds: 3),
    DateTime Function() expiryClock = DateTime.now,
  })  : _store = store,
        _session = session,
        _apiClient = apiClient,
        _mapper = mapper,
        _crypto = crypto,
        _contents = contents,
        _pending = pending,
        _attachments = attachments,
        _ops = ops,
        _expiryClock = expiryClock {
    _retrySweep = Timer.periodic(retrySweepInterval, (_) => unawaited(drain()));
  }

  final MessengerStateStore _store;
  final MessengerSessionContext _session;
  final VeilApiClient _apiClient;
  final MessengerApiMapper _mapper;
  final ConversationCryptoRouter _crypto;
  final MessageContentService _contents;
  final PendingMessages _pending;
  final AttachmentTransferService _attachments;
  final MessengerOperationRunner _ops;
  // The relay-corrected clock disappearing expiries are stamped on: the
  // relay refuses an expiry already past by its clock, and recipients
  // retire messages by theirs.
  final DateTime Function() _expiryClock;
  final Random _random = Random.secure();
  late final Timer _retrySweep;
  bool _draining = false;

  bool get hasPendingWork => !_pending.isEmpty;

  Iterable<String> get pendingConversationIds => _pending.all.map((pending) => pending.conversationId);

  DateTime? nextRetryAt(String conversationId) {
    DateTime? earliest;
    for (final pending in _pending.all) {
      final nextRetryAt = pending.nextRetryAt;
      if (pending.conversationId != conversationId || nextRetryAt == null) continue;
      if (earliest == null || nextRetryAt.isBefore(earliest)) earliest = nextRetryAt;
    }
    return earliest;
  }

  /// Encrypts and queues one message; false when that failed (the failure
  /// is shown as usual).
  Future<bool> send({
    required String conversationId,
    required String body,
    required MessageKind messageKind,
    Duration? disappearAfter,
  }) async {
    var queued = false;
    await _ops.run(() async {
      final session = _session.requireAuthed();
      final conversation = _store.requireConversation(conversationId);
      final clientMessageId = _nextClientMessageId();
      final expiresAt = disappearAfter == null ? null : _expiryClock().add(disappearAfter);
      final envelope = await _encryptOutbound(
        conversation: conversation,
        senderDeviceId: session.deviceId,
        clientMessageId: clientMessageId,
        body: body,
        messageKind: messageKind,
        expiresAt: expiresAt,
      );
      await _enqueue(conversation: conversation, senderDeviceId: session.deviceId, clientMessageId: clientMessageId, envelope: envelope);
      queued = true;
      unawaited(drain(conversationId: conversationId));
    });
    return queued;
  }

  /// Queues a staged placeholder file as an attachment message.
  Future<void> sendAttachmentPlaceholder(String conversationId, {required String filename}) async {
    await _ops.run(() async {
      final session = _session.requireAuthed();
      final conversation = _store.requireConversation(conversationId);
      final clientMessageId = _nextClientMessageId();
      final tempBlob = await _attachments.stage(filename: filename);
      final envelope = await _encryptOutbound(
        conversation: conversation,
        senderDeviceId: session.deviceId,
        clientMessageId: clientMessageId,
        body: attachmentMessageBody,
        messageKind: MessageKind.file,
      );
      await _enqueue(
        conversation: conversation,
        senderDeviceId: session.deviceId,
        clientMessageId: clientMessageId,
        envelope: envelope,
        draft: AttachmentUploadDraft(
          filename: filename,
          contentType: AttachmentTransferService.guessContentType(filename),
          sizeBytes: tempBlob.sizeBytes,
          sha256: tempBlob.sha256,
          tempFilePath: tempBlob.path,
          lastUpdatedAt: tempBlob.createdAt,
        ),
      );
      unawaited(drain(conversationId: conversationId));
    });
  }

  /// Retries queued messages now, failed ones included.
  Future<void> retry([String? conversationId]) =>
      drain(conversationId: conversationId, markFailuresAsRetrying: true, ignoreRetrySchedule: true);

  /// Sends what is due, oldest first. Only one drain runs at a time; a
  /// failure is recorded on its message and the drain moves on, so one
  /// stalled send never holds back the ones after it.
  Future<void> drain({
    String? conversationId,
    bool markFailuresAsRetrying = false,
    bool ignoreRetrySchedule = false,
  }) async {
    if (_session.isClosed || _draining || _session.authed == null) return;

    _draining = true;
    try {
      final now = DateTime.now();
      final due = _pending.all
          .where((item) => conversationId == null || item.conversationId == conversationId)
          .where((item) => markFailuresAsRetrying || item.state != MessageDeliveryState.failed)
          .where((item) => ignoreRetrySchedule || item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final pending in due) {
        await _sendOne(pending, now);
      }
    } finally {
      _draining = false;
      _store.changed();
    }
  }

  /// Stops [clientMessageId]'s attachment upload and fails its message, so
  /// the user may retry it.
  Future<void> cancelAttachment(String clientMessageId) async {
    final pending = _pending[clientMessageId];
    final draft = pending?.attachmentUploadDraft;
    if (pending == null || draft == null) return;

    _attachments.cancelUpload(clientMessageId);
    final failed = pending.copyWith(
      state: MessageDeliveryState.failed,
      errorMessage: 'Attachment upload was canceled on this device.',
      nextRetryAt: null,
      lastAttemptAt: DateTime.now(),
    );
    await _pending.save(failed);
    _setLocalState(clientMessageId, MessageDeliveryState.failed, errorMessage: failed.errorMessage);
    _attachments.trackDraft(
      clientMessageId,
      draft,
      phase: AttachmentTransferPhase.canceled,
      errorMessage: failed.errorMessage,
      canRetry: true,
      canCancel: false,
    );
    _store.changed();
  }

  /// Takes back the queue the cache held and shows each queued message.
  /// Returns the staging files still in use.
  Set<String> restore(List<PendingMessageRecord> records) {
    _pending.restore(records);
    final keepTempPaths = <String>{};
    for (final pending in records) {
      final draft = pending.attachmentUploadDraft;
      if (draft?.tempFilePath case final path?) keepTempPaths.add(path);
      if (draft != null) {
        final failed = pending.state == MessageDeliveryState.failed;
        _attachments.trackDraft(
          pending.clientMessageId,
          draft,
          phase: failed ? AttachmentTransferPhase.failed : AttachmentTransferPhase.staged,
          errorMessage: pending.errorMessage,
          canRetry: failed,
          canCancel: !failed,
        );
      }
      _store.setMessages(
        pending.conversationId,
        mergeMessageCollections(_store.messagesOf(pending.conversationId), [_optimisticMessage(pending)]),
      );
    }
    return keepTempPaths;
  }

  void clear() => _pending.clear();

  void dispose() => _retrySweep.cancel();

  Future<void> _sendOne(PendingMessageRecord pending, DateTime now) async {
    final hasAttachment = pending.attachmentUploadDraft != null;
    var marked = pending.copyWith(
      retryCount: pending.retryCount + 1,
      lastAttemptAt: now,
      nextRetryAt: null,
      state: hasAttachment ? MessageDeliveryState.uploading : MessageDeliveryState.pending,
      errorMessage: null,
    );
    await _pending.save(marked);
    _setLocalState(pending.clientMessageId, marked.state);
    if (marked.attachmentUploadDraft case final draft?) {
      _attachments.trackDraft(marked.clientMessageId, draft,
          phase: AttachmentTransferPhase.preparing, canRetry: false, canCancel: true);
    }

    try {
      if (hasAttachment) {
        marked = await _attachments.prepare(marked);
        await _pending.save(marked);
        _setLocalState(marked.clientMessageId, MessageDeliveryState.pending);
        _attachments.forget(marked.clientMessageId);
      }

      final groupEpoch = GroupSenderKeyCoordinator.epochOf(marked.envelope);
      // Read per send: the token may be refreshed while the queue drains.
      final response = await _apiClient.sendMessage(_session.requireAuthed().accessToken, {
        'conversationId': marked.conversationId,
        'clientMessageId': marked.clientMessageId,
        'envelope': _mapper.encodeEnvelope(marked.envelope),
        if (groupEpoch != null) 'groupEpoch': groupEpoch,
      });
      final serverMessage = _mapper.message(response['message'], localDeviceId: _session.deviceId) ??
          (throw StateError('Unexpected response shape'));
      if (serverMessage.isLocalNotice) throw const FormatException('The relay acknowledged a local notice id.');
      // The ack decides which relayed id our own text is shown under, so it
      // must be the message just sent: ours, in this conversation.
      if (serverMessage.clientMessageId != marked.clientMessageId ||
          serverMessage.envelope.conversationId != marked.conversationId ||
          !serverMessage.isMine) {
        throw const FormatException('The relay acknowledged a different message.');
      }
      await _pending.remove(marked.clientMessageId);
      final content = await _contents.acknowledge(
        clientMessageId: marked.clientMessageId,
        serverMessageId: serverMessage.id,
      );
      _store.mergeMessages(marked.conversationId, [withInnerExpiry(serverMessage, content?.innerExpiresAt)]);
      _attachments.forget(marked.clientMessageId);
    } catch (error) {
      await _ops.handleSecurityException(error);
      // prepare() saves each step it completes (the sealed draft, its
      // ticket). Building on the copy taken before it ran would drop the
      // sealed reference, and the retry would try to re-seal a staging file
      // that was deleted once sealed.
      final latest = _pending[marked.clientMessageId] ?? marked;
      final isTransient = shouldRetryAutomatically(error, latest.retryCount);
      final failed = latest.copyWith(
        state: !isTransient
            ? MessageDeliveryState.failed
            : latest.attachmentUploadDraft == null
                ? MessageDeliveryState.pending
                : MessageDeliveryState.uploading,
        nextRetryAt: isTransient ? now.add(retryDelayForAttempt(latest.retryCount)) : null,
        errorMessage: formatUserFacingError(error),
      );
      await _pending.save(failed);
      _setLocalState(marked.clientMessageId, failed.state, errorMessage: failed.errorMessage);
      if (failed.attachmentUploadDraft case final draft?) {
        _attachments.trackDraft(
          failed.clientMessageId,
          draft,
          phase: extractVeilApiErrorCode(error) == 'attachment_upload_canceled'
              ? AttachmentTransferPhase.canceled
              : AttachmentTransferPhase.failed,
          errorMessage: failed.errorMessage,
          canRetry: true,
          canCancel: false,
        );
      }
      // An identity change or a held account is the conversation's issue,
      // not a global one.
      if (error is! IdentityChangedException && error is! PeerAccountHeldException) {
        _ops.showMessage(failed.errorMessage!);
      }
    }
  }

  // Stores the plaintext before encrypting so the sender can always show
  // its own message: the sender cannot decrypt what it sealed.
  Future<CryptoEnvelope> _encryptOutbound({
    required ConversationPreview conversation,
    required String senderDeviceId,
    required String clientMessageId,
    required String body,
    required MessageKind messageKind,
    DateTime? expiresAt,
  }) async {
    await _contents.storeOutbound(
      conversationId: conversation.id,
      clientMessageId: clientMessageId,
      senderDeviceId: senderDeviceId,
      body: body,
      kind: messageKind,
      expiresAt: expiresAt,
    );
    try {
      return await _crypto.encrypt(
        conversation: conversation,
        senderDeviceId: senderDeviceId,
        body: body,
        messageKind: messageKind,
        expiresAt: expiresAt,
      );
    } catch (_) {
      // Never queued, so never shown: do not keep its plaintext at rest.
      await _contents.discardOutbound(clientMessageId);
      rethrow;
    }
  }

  Future<void> _enqueue({
    required ConversationPreview conversation,
    required String senderDeviceId,
    required String clientMessageId,
    required CryptoEnvelope envelope,
    AttachmentUploadDraft? draft,
  }) async {
    final pending = PendingMessageRecord(
      clientMessageId: clientMessageId,
      conversationId: conversation.id,
      senderDeviceId: senderDeviceId,
      recipientUserId: envelope.recipientUserId,
      envelope: envelope,
      createdAt: DateTime.now(),
      state: draft == null ? MessageDeliveryState.pending : MessageDeliveryState.uploading,
      attachmentUploadDraft: draft,
    );
    final saving = _pending.save(pending);
    _store.mergeMessages(conversation.id, [_optimisticMessage(pending)]);
    if (draft != null) {
      _attachments.trackDraft(clientMessageId, draft,
          phase: AttachmentTransferPhase.staged, canRetry: false, canCancel: true);
    }
    await saving;
  }

  ChatMessage _optimisticMessage(PendingMessageRecord pending) => ChatMessage(
        id: 'local-${pending.clientMessageId}',
        clientMessageId: pending.clientMessageId,
        senderDeviceId: pending.senderDeviceId,
        sentAt: pending.createdAt,
        envelope: pending.envelope,
        deliveryState: pending.state,
        expiresAt: pending.envelope.expiresAt,
        isMine: pending.senderDeviceId == _session.deviceId,
      );

  // Updates the delivery state of the message [clientMessageId] shows as;
  // a failure on a shown message becomes the messenger's error line.
  void _setLocalState(String clientMessageId, MessageDeliveryState state, {String? errorMessage}) {
    final updated = _store.updateMessagesWhere(
      (message) => message.clientMessageId == clientMessageId,
      (message) => message.copyWith(deliveryState: state),
    );
    if (updated && errorMessage != null) _ops.showMessage(errorMessage);
  }

  String _nextClientMessageId() {
    final entropy = _random.nextInt(1 << 32).toRadixString(36);
    return 'msg-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$entropy';
  }
}
