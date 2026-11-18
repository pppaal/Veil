import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../conversation_models.dart';
import 'conversation_crypto_router.dart';
import 'message_content_service.dart';
import 'messenger_state_store.dart';
import 'pending_messages.dart';

/// Seals the texts the outbox queues. A text is sealed when it is queued,
/// its disappearing expiry stamped then, unless it has a timer and has to
/// wait behind another message of its chat (D20 keeps a chat's order, so it
/// waits for that message's upload or send). Such a text is sealed, and its
/// expiry stamped from the relay's clock, only when it is posted, as an
/// attachment's is after its upload (D18): a stamp taken when it was queued
/// could pass while it waits, take the text out of the chat and send an
/// expiry the relay refuses. Until it is sealed it carries a placeholder
/// frame (empty ciphertext, never posted) and no expiry anywhere: not on its
/// record, its stored text or its bubble, so the expiry sweeps of the chat,
/// the stored contents and the cache leave it alone however long it waits.
class OutboundTextSealer {
  OutboundTextSealer({
    required MessengerStateStore store,
    required ConversationCryptoRouter crypto,
    required MessageContentService contents,
    required PendingMessages pending,
    required DateTime Function() expiryClock,
  })  : _store = store,
        _crypto = crypto,
        _contents = contents,
        _pending = pending,
        _expiryClock = expiryClock;

  final MessengerStateStore _store;
  final ConversationCryptoRouter _crypto;
  final MessageContentService _contents;
  final PendingMessages _pending;
  final DateTime Function() _expiryClock;

  /// Whether [pending] is a text still waiting to be sealed and stamped.
  static bool waitsForStamp(PendingMessageRecord pending) =>
      pending.disappearAfterSeconds != null &&
      pending.attachmentUploadDraft == null &&
      pending.envelope.attachment == null &&
      pending.envelope.ciphertext.isEmpty;

  /// Seals [body] now, with [expiresAt] in it. The plaintext is stored
  /// first so the sender can always show its own message (it cannot open
  /// what it sealed), and dropped again when sealing fails.
  Future<CryptoEnvelope> sealNow({
    required ConversationPreview conversation,
    required String senderDeviceId,
    required String clientMessageId,
    required String body,
    required MessageKind kind,
    DateTime? expiresAt,
  }) async {
    await _storeText(conversation.id, clientMessageId, senderDeviceId, body, kind, expiresAt);
    try {
      return await _crypto.encrypt(
        conversation: conversation,
        senderDeviceId: senderDeviceId,
        body: body,
        messageKind: kind,
        expiresAt: expiresAt,
      );
    } catch (_) {
      // Never queued, so never shown: do not keep its plaintext at rest.
      await _contents.discardOutbound(clientMessageId);
      rethrow;
    }
  }

  /// Stores [body] with no expiry and returns the placeholder frame the
  /// text waits with; its record carries the timer. A conversation held for
  /// an identity change or an account throws here, as sealing would.
  Future<CryptoEnvelope> holdForStamp({
    required ConversationPreview conversation,
    required String senderDeviceId,
    required String clientMessageId,
    required String body,
    required MessageKind kind,
  }) async {
    await _crypto.checkAttachmentSend(conversation);
    await _storeText(conversation.id, clientMessageId, senderDeviceId, body, kind, null);
    return CryptoEnvelope(
      version: '',
      conversationId: conversation.id,
      senderDeviceId: senderDeviceId,
      recipientUserId: conversation.type == ConversationType.group ? '' : conversation.recipientBundle.userId,
      ciphertext: '',
      nonce: '',
      messageKind: kind,
    );
  }

  /// Seals the waiting text [pending] now, its expiry stamped from the
  /// relay's clock, and saves the sealed record, which a retry then sends
  /// as it is. Then its stored text and its bubble take the same expiry.
  Future<PendingMessageRecord> stampAndSeal(PendingMessageRecord pending) async {
    final id = pending.clientMessageId;
    final conversation = _store.conversationById(pending.conversationId) ??
        (throw StateError('The target conversation is no longer available.'));
    final echo = ChatMessage(
      id: 'local-$id',
      clientMessageId: id,
      senderDeviceId: pending.senderDeviceId,
      sentAt: pending.createdAt,
      envelope: pending.envelope,
    );
    final content = (await _contents.storedFor([echo]))[echo.id] ??
        (throw StateError('The text of a queued message is no longer on this phone.'));
    final expiresAt = _expiryClock().add(Duration(seconds: pending.disappearAfterSeconds!));
    final envelope = await _crypto.encrypt(
      conversation: conversation,
      senderDeviceId: pending.senderDeviceId,
      body: content.body,
      messageKind: content.kind,
      expiresAt: expiresAt,
    );
    // The record first: a crash after it sends this frame, and a stored
    // text without its expiry still goes with its message.
    final sealed = pending.copyWith(envelope: envelope, disappearAfterSeconds: null);
    await _pending.save(sealed);
    await _storeText(conversation.id, id, pending.senderDeviceId, content.body, content.kind, expiresAt);
    _store.updateMessagesWhere(
      (message) => message.clientMessageId == id,
      (message) => message.copyWith(expiresAt: expiresAt),
      inConversation: conversation.id,
    );
    return sealed;
  }

  Future<void> _storeText(
    String conversationId,
    String clientMessageId,
    String senderDeviceId,
    String body,
    MessageKind kind,
    DateTime? expiresAt,
  ) =>
      _contents.storeOutbound(
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        senderDeviceId: senderDeviceId,
        body: body,
        kind: kind,
        expiresAt: expiresAt,
      );
}
