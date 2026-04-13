import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

void main() {
  test('messageDeliveryLabel maps send states to clear user-facing copy', () {
    expect(messageDeliveryLabel(_message(MessageDeliveryState.pending)), 'Queued');
    expect(messageDeliveryLabel(_message(MessageDeliveryState.uploading)), 'Uploading');
    expect(messageDeliveryLabel(_message(MessageDeliveryState.failed)), 'Retry required');
    expect(messageDeliveryLabel(_message(MessageDeliveryState.sent)), 'Sent');
    expect(messageDeliveryLabel(_message(MessageDeliveryState.delivered)), 'Delivered');
    expect(messageDeliveryLabel(_message(MessageDeliveryState.read)), 'Read');
  });

  test('messageBubbleSemanticsLabel includes delivery state for sent messages', () {
    expect(
      messageBubbleSemanticsLabel(_message(MessageDeliveryState.delivered)),
      'Sent message bubble. Delivered.',
    );
    expect(
      messageBubbleSemanticsLabel(
        _message(MessageDeliveryState.sent).copyWith(isMine: false),
      ),
      'Received message bubble.',
    );
  });

  test('formatRetryCountdown emits compact retry windows', () {
    final soon = DateTime.now().add(const Duration(seconds: 9));
    final medium = DateTime.now().add(const Duration(minutes: 2, seconds: 5));

    expect(formatRetryCountdown(soon), matches(RegExp(r'^[0-9]+s$')));
    expect(formatRetryCountdown(medium), matches(RegExp(r'^2m [0-9]+s$')));
  });

  test('historyWindowLabel reflects paged and complete states clearly', () {
    expect(
      historyWindowLabel(isLoadingHistory: true, hasMoreHistory: true),
      'Loading older',
    );
    expect(
      historyWindowLabel(isLoadingHistory: false, hasMoreHistory: true),
      'Paged',
    );
    expect(
      historyWindowLabel(isLoadingHistory: false, hasMoreHistory: false),
      'Complete',
    );
  });

  test('historyWindowBannerSpec only appears for loading or complete windows', () {
    expect(
      historyWindowBannerSpec(isLoadingHistory: false, hasMoreHistory: true),
      isNull,
    );
    expect(
      historyWindowBannerSpec(isLoadingHistory: true, hasMoreHistory: true)?.title,
      'Syncing older history',
    );
    expect(
      historyWindowBannerSpec(isLoadingHistory: false, hasMoreHistory: false)?.title,
      'Conversation window complete',
    );
  });

  test('messageDeliveryLabel handles all delivery states exhaustively', () {
    for (final state in MessageDeliveryState.values) {
      expect(
        messageDeliveryLabel(_message(state)),
        isNotEmpty,
        reason: 'Missing label for $state',
      );
    }
  });

  test('formatRetryCountdown handles imminent and distant retries', () {
    final imminent = DateTime.now().add(const Duration(seconds: 1));
    final distant = DateTime.now().add(const Duration(minutes: 10, seconds: 30));
    final past = DateTime.now().subtract(const Duration(seconds: 5));

    expect(formatRetryCountdown(imminent), matches(RegExp(r'^[0-9]+s$')));
    expect(formatRetryCountdown(distant), matches(RegExp(r'^10m [0-9]+s$')));
    expect(formatRetryCountdown(past), matches(RegExp(r'^0s$')));
  });

  test('messageBubbleSemanticsLabel omits delivery state for received messages', () {
    final received = _message(MessageDeliveryState.read).copyWith(isMine: false);
    expect(
      messageBubbleSemanticsLabel(received),
      'Received message bubble.',
    );
  });
}

ChatMessage _message(MessageDeliveryState state) {
  return ChatMessage(
    id: 'msg-1',
    clientMessageId: 'client-1',
    senderDeviceId: 'device-1',
    sentAt: DateTime.utc(2026, 4, 7, 10),
    envelope: const CryptoEnvelope(
      version: 'dev-v1',
      conversationId: 'conv-1',
      senderDeviceId: 'device-1',
      recipientUserId: 'user-2',
      ciphertext: 'opaque',
      nonce: 'nonce-1',
      messageKind: MessageKind.text,
    ),
    deliveryState: state,
    isMine: true,
  );
}
