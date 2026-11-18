import 'dart:async';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/errors/user_facing_error.dart';
import '../../../../core/network/veil_api_client.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../../../../core/util/uuid_v4.dart';
import '../../../attachments/data/media_blob_store.dart';
import '../../../attachments/domain/outgoing_attachment.dart';
import '../conversation_models.dart';
import '../group_sender_key_coordinator.dart';
import 'attachment_sealer.dart';
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

/// Messages on their way to the relay. A message is encrypted (an
/// attachment sealed) and queued at once, shown as pending, and sent oldest
/// first within its conversation; conversations drain on their own, so one
/// chat's upload never holds back another chat's texts (D20). A send that
/// fails is retried on a schedule (see retry_policy.dart) or left for the
/// user.
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
    MediaBlobStore? blobs,
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
        _sealer = AttachmentSealer(blobs: blobs, contents: contents),
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
  final AttachmentSealer _sealer;
  final MessengerOperationRunner _ops;
  // The relay-corrected clock disappearing expiries are stamped on: the
  // relay refuses an expiry already past by its clock, and recipients
  // retire messages by theirs.
  final DateTime Function() _expiryClock;
  late final Timer _retrySweep;
  // The conversations draining now, and the send of each message under way.
  final Set<String> _draining = {};
  final Map<String, Future<void>> _inFlight = {};

  bool get hasPendingWork => !_pending.isEmpty;

  Iterable<String> get pendingConversationIds => _pending.all.map((pending) => pending.conversationId);

  /// The attachment id of every queued attachment, lower-cased: blobs no
  /// cleanup may take while their message waits to go.
  Set<String> get pendingAttachmentIds => {
        for (final pending in _pending.all)
          if (blobIdOf(pending) case final id? when id.isNotEmpty) id.toLowerCase(),
      };

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

  /// Seals [attachment] and queues it as a photo or file message, its staged
  /// plaintext deleted either way; false when that failed (a held chat says
  /// why in its banner). Its frame is encrypted after the upload, with the
  /// timer [disappearAfter] stamped then (D18).
  Future<bool> sendAttachment({
    required String conversationId,
    required OutgoingAttachment attachment,
    Duration? disappearAfter,
  }) async {
    var queued = false;
    await _ops.run(() async {
      late final AuthedSession session;
      late final ConversationPreview conversation;
      final clientMessageId = _nextClientMessageId();
      final sealed = await _sealer.sealAndStore(
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        attachment: attachment,
        senderDeviceId: () => session.deviceId,
        precheck: () async {
          session = _session.requireAuthed();
          conversation = _store.requireConversation(conversationId);
          await _crypto.checkAttachmentSend(conversation);
        },
      );
      await _enqueue(
        conversation: conversation,
        senderDeviceId: session.deviceId,
        clientMessageId: clientMessageId,
        envelope: placeholderEnvelope(
          conversation: conversation,
          senderDeviceId: session.deviceId,
          kind: messageKindOf(attachment),
          attachmentId: sealed.reference.attachmentId,
        ),
        draft: sealedDraft(attachment, sealed, disappearAfter: disappearAfter),
      );
      queued = true;
      unawaited(drain(conversationId: conversationId));
    });
    return queued;
  }

  /// Retries queued messages now, failed ones included.
  Future<void> retry([String? conversationId]) =>
      drain(conversationId: conversationId, markFailuresAsRetrying: true, ignoreRetrySchedule: true);

  /// Sends what is due: [conversationId]'s messages, or with none every
  /// conversation's, each conversation on its own and oldest first. A
  /// conversation already draining is left to that drain. A failure is
  /// recorded on its message and the drain moves on, so one stalled send
  /// never holds back the ones after it.
  Future<void> drain({
    String? conversationId,
    bool markFailuresAsRetrying = false,
    bool ignoreRetrySchedule = false,
  }) async {
    if (_session.isClosed || _session.authed == null) return;
    final conversationIds = conversationId != null ? {conversationId} : pendingConversationIds.toSet();
    final drains = [
      for (final id in conversationIds)
        if (_draining.add(id))
          _drainConversation(id, markFailuresAsRetrying: markFailuresAsRetrying, ignoreRetrySchedule: ignoreRetrySchedule),
    ];
    try {
      await Future.wait(drains);
    } finally {
      _store.changed();
    }
  }

  // One message at a time, the oldest due first, taking in what is queued
  // while it drains; each message is tried at most once per drain.
  Future<void> _drainConversation(
    String conversationId, {
    required bool markFailuresAsRetrying,
    required bool ignoreRetrySchedule,
  }) async {
    final tried = <String>{};
    try {
      while (!_session.isClosed && _session.authed != null) {
        final now = DateTime.now();
        final due = _pending.all
            .where((item) => item.conversationId == conversationId && !tried.contains(item.clientMessageId))
            .where((item) => markFailuresAsRetrying || item.state != MessageDeliveryState.failed)
            .where((item) => ignoreRetrySchedule || item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (due.isEmpty) return;
        tried.add(due.first.clientMessageId);
        await _sendOne(due.first, now);
      }
    } finally {
      _draining.remove(conversationId);
    }
  }

  /// Cancels [clientMessageId]'s attachment, which removes the message
  /// (D19). The cancel wins every race: the send settling meanwhile writes
  /// nothing back, and only then is anything deleted (see discard).
  Future<void> cancelAttachment(String clientMessageId) async {
    final pending = _pending[clientMessageId];
    if (pending == null || _pending.isCanceled(clientMessageId) || !isAttachmentRecord(pending)) return;
    _pending.cancel(clientMessageId);
    _attachments.cancelUpload(clientMessageId);
    await _inFlight[clientMessageId];
    await _attachments.discard(clientMessageId);
  }

  /// Takes back the queue the cache held and shows each queued message.
  /// Returns the staging files still in use: none (D39), so hydrate's
  /// cleanup empties staging. A draft an older build queued fails for good.
  Set<String> restore(List<PendingMessageRecord> records) {
    final restored = [for (final record in records) isOldFormatDraft(record) ? failedOldDraft(record) : withBlobPointer(record)];
    _pending.restore(restored);
    for (final pending in restored) {
      if (isOldFormatDraft(pending) && pending.state == MessageDeliveryState.failed) _pending.save(pending).ignore();
      _attachments.trackRecord(pending);
      _store.setMessages(
        pending.conversationId,
        mergeMessageCollections(_store.messagesOf(pending.conversationId), [_optimisticMessage(pending)]),
      );
    }
    return const <String>{};
  }

  void clear() {
    _pending.clear();
    _inFlight.clear();
  }

  void dispose() => _retrySweep.cancel();

  // Keeps its send under way where cancelAttachment can wait for it.
  Future<void> _sendOne(PendingMessageRecord pending, DateTime now) {
    final id = pending.clientMessageId;
    final sending = _send(pending, now);
    _inFlight[id] = sending;
    return sending.whenComplete(() {
      if (identical(_inFlight[id], sending)) _inFlight.remove(id);
    });
  }

  Future<void> _send(PendingMessageRecord pending, DateTime now) async {
    if (_pending.isCanceled(pending.clientMessageId)) return;
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
      // A placeholder frame is never posted, and a cancelled message is
      // not posted once cancelled.
      if (marked.envelope.ciphertext.isEmpty) throw StateError('A queued attachment was about to go unsealed.');
      if (_pending.isCanceled(marked.clientMessageId)) {
        throw VeilApiException('Attachment upload canceled.', code: 'attachment_upload_canceled');
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
      final content = await _contents.acknowledge(
        clientMessageId: marked.clientMessageId,
        serverMessageId: serverMessage.id,
      );
      _store.mergeMessages(marked.conversationId, [withInnerExpiry(serverMessage, content?.innerExpiresAt)]);
      // Only now, with the relayed copy in the state, does the outbox
      // record go: remove() writes that copy to the cache first.
      await _pending.remove(marked.clientMessageId);
      _attachments.forget(marked.clientMessageId);
    } catch (error) {
      // Stopped by the messenger closing, the record stays as it was saved,
      // for the next start; cancelled meanwhile, cancelAttachment removes
      // it, and nothing here may bring it back as "Not sent".
      if (_session.isClosed || _pending.isCanceled(marked.clientMessageId)) return;
      await _ops.handleSecurityException(error);
      // prepare() saves each step it completes (its ticket). Building on
      // the copy taken before it ran would drop it.
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
      _attachments.trackRecord(failed, afterFailure: true);
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

  // Random, nothing else: the relay keeps this id with the message and
  // shows it to every member, so a clock in it would tell them when the
  // message was written and how this device's clock is set. Drawn once per
  // message; every retry of the send reuses it, which is what lets the
  // relay recognise a retry of a send it already took.
  String _nextClientMessageId() => randomUuidV4();
}
