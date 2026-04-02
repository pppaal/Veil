import 'dart:math';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/mock_crypto_engine.dart';
import 'conversation_models.dart';

class MockMessengerRepository {
  MockMessengerRepository({MessageCryptoEngine? cryptoEngine})
      : _cryptoEngine =
            cryptoEngine ?? createDefaultCryptoAdapter().messaging {
    _seed();
  }

  final MessageCryptoEngine _cryptoEngine;
  final _random = Random();
  final List<ConversationPreview> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};

  static const currentDeviceId = 'device-local-primary';

  List<ConversationPreview> listConversations() =>
      [..._conversations]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<ChatMessage> listMessages(String conversationId) {
    expireMessages();
    return [...(_messages[conversationId] ?? [])]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }

  Future<DecryptedMessage> decryptEnvelope(CryptoEnvelope envelope) {
    return _cryptoEngine.decryptMessage(envelope);
  }

  Future<void> sendText({
    required String conversationId,
    required String body,
    Duration? disappearAfter,
  }) async {
    final conversation = _conversations.firstWhere((item) => item.id == conversationId);
    final expiresAt = disappearAfter == null ? null : DateTime.now().add(disappearAfter);
    final envelope = await _cryptoEngine.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: currentDeviceId,
      recipientUserId: conversation.recipientBundle.userId,
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: conversation.recipientBundle,
      expiresAt: expiresAt,
    );

    _messages.putIfAbsent(conversationId, () => []);
    _messages[conversationId]!.add(
      ChatMessage(
        id: 'msg-${_random.nextInt(1 << 31)}',
        clientMessageId: 'client-${_random.nextInt(1 << 31)}',
        senderDeviceId: currentDeviceId,
        sentAt: DateTime.now(),
        envelope: envelope,
        conversationOrder: (_messages[conversationId]?.length ?? 0) + 1,
        expiresAt: expiresAt,
        isMine: true,
      ),
    );

    _replaceConversationPreview(
      conversation.copyWith(
        lastEnvelope: envelope,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> sendAttachment({
    required String conversationId,
    required String filename,
  }) async {
    final conversation = _conversations.firstWhere((item) => item.id == conversationId);
    final attachment = await _cryptoEngine.encryptAttachment(
      attachmentId: 'attachment-${_random.nextInt(1 << 31)}',
      storageKey: 'attachments/mock/$filename',
      contentType: 'application/octet-stream',
      sizeBytes: 2048,
      sha256: 'mock-sha256-$filename',
      recipientBundle: conversation.recipientBundle,
    );
    final envelope = await _cryptoEngine.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: currentDeviceId,
      recipientUserId: conversation.recipientBundle.userId,
      body: 'Encrypted attachment',
      messageKind: MessageKind.file,
      recipientBundle: conversation.recipientBundle,
      attachment: attachment,
    );

    _messages.putIfAbsent(conversationId, () => []);
    _messages[conversationId]!.add(
      ChatMessage(
        id: 'msg-${_random.nextInt(1 << 31)}',
        clientMessageId: 'client-${_random.nextInt(1 << 31)}',
        senderDeviceId: currentDeviceId,
        sentAt: DateTime.now(),
        envelope: envelope,
        conversationOrder: (_messages[conversationId]?.length ?? 0) + 1,
        isMine: true,
      ),
    );

    _replaceConversationPreview(
      conversation.copyWith(
        lastEnvelope: envelope,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> startConversation(String handle) async {
    final conversationId = 'conv-${_random.nextInt(1 << 31)}';
    _conversations.add(
      ConversationPreview(
        id: conversationId,
        peerHandle: handle,
        peerDisplayName: handle.toUpperCase(),
        recipientBundle: KeyBundle(
          userId: 'user-$handle',
          deviceId: 'device-$handle',
          handle: handle,
          identityPublicKey: 'mock-id-$handle',
          signedPrekeyBundle: 'mock-prekey-$handle',
        ),
        lastEnvelope: null,
        updatedAt: DateTime.now(),
      ),
    );
    _messages[conversationId] = [];
  }

  void expireMessages() {
    final now = DateTime.now();
    for (final entry in _messages.entries) {
      entry.value.removeWhere((message) => message.expiresAt != null && !message.expiresAt!.isAfter(now));

      final conversationIndex = _conversations.indexWhere((conversation) => conversation.id == entry.key);
      if (conversationIndex == -1) {
        continue;
      }

      final latestMessage = entry.value.isEmpty ? null : entry.value.last;
      final current = _conversations[conversationIndex];
      _conversations[conversationIndex] = current.copyWith(
        lastEnvelope: latestMessage?.envelope,
        updatedAt: latestMessage?.sentAt ?? current.updatedAt,
      );
    }
  }

  void _replaceConversationPreview(ConversationPreview conversation) {
    _conversations
      ..removeWhere((item) => item.id == conversation.id)
      ..add(conversation);
  }

  void _seed() {
    final bundle = KeyBundle(
      userId: 'user-icarus',
      deviceId: 'device-icarus',
      handle: 'icarus',
      identityPublicKey: 'mock-id-icarus',
      signedPrekeyBundle: 'mock-prekey-icarus',
    );
    _conversations.add(
      ConversationPreview(
        id: 'conv-icarus',
        peerHandle: 'icarus',
        peerDisplayName: 'Icarus',
        recipientBundle: bundle,
        lastEnvelope: null,
        updatedAt: DateTime.now().subtract(const Duration(minutes: 8)),
      ),
    );
    _messages['conv-icarus'] = [];
  }
}
