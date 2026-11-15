import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_labels.dart' show conversationTitle;
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';

void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  test('messageDeliveryLabel maps send states to clear user-facing copy', () {
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.pending)), 'Queued');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.uploading)), 'Uploading');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.failed)), 'Retry required');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.sent)), 'Sent');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.delivered)), 'Delivered');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.read)), 'Read');
  });

  test('messageBubbleSemanticsLabel includes delivery state for sent messages', () {
    expect(
      messageBubbleSemanticsLabel(l10n, _message(MessageDeliveryState.delivered)),
      'Sent message bubble. Delivered.',
    );
    expect(
      messageBubbleSemanticsLabel(
        l10n,
        _message(MessageDeliveryState.sent).copyWith(isMine: false),
      ),
      'Received message bubble.',
    );
  });

  test('formatRetryCountdown emits compact retry windows', () {
    final soon = DateTime.now().add(const Duration(seconds: 9));
    final medium = DateTime.now().add(const Duration(minutes: 2, seconds: 5));

    expect(formatRetryCountdown(l10n, soon), matches(RegExp(r'^[0-9]+s$')));
    expect(formatRetryCountdown(l10n, medium), matches(RegExp(r'^2m [0-9]+s$')));
  });

  test('formatRetryCountdown counts in the language of the screen', () {
    final ko = lookupAppLocalizations(const Locale('ko'));
    final soon = DateTime.now().add(const Duration(seconds: 9));
    final medium = DateTime.now().add(const Duration(minutes: 2, seconds: 5));

    expect(formatRetryCountdown(ko, soon), matches(RegExp(r'^[0-9]+초$')));
    expect(formatRetryCountdown(ko, medium), matches(RegExp(r'^2분 [0-9]+초$')));
  });

  group('conversationTitle', () {
    ConversationPreview conversation({
      ConversationType type = ConversationType.direct,
      String? displayName,
      List<GroupMember> members = const [],
    }) =>
        ConversationPreview(
          id: 'conv-1',
          peerHandle: 'selene',
          peerDisplayName: displayName,
          recipientBundle: const KeyBundle(
            userId: 'user-selene',
            deviceId: 'dev-selene',
            handle: 'selene',
            identityPublicKey: 'ik',
            signedPrekeyBundle: 'spk',
          ),
          lastEnvelope: null,
          updatedAt: DateTime.utc(2026, 4, 7),
          type: type,
          members: members,
        );
    const members = [
      GroupMember(userId: 'user-atlas', handle: 'atlas', displayName: 'Atlas Moreau'),
      GroupMember(userId: 'user-selene', handle: 'selene', displayName: 'Selene Park'),
      GroupMember(userId: 'user-jiwoo', handle: 'jiwoo'),
    ];

    test('a 1:1 is called by the peer\'s name, or by their handle when they set none', () {
      expect(conversationTitle(l10n, conversation(displayName: 'Selene Park'), localUserId: 'user-atlas'), 'Selene Park');
      expect(conversationTitle(l10n, conversation(), localUserId: 'user-atlas'), '@selene');
    });

    test('a group is called by its other members, never by one of them alone, and never by the user', () {
      final group = conversation(type: ConversationType.group, displayName: 'Selene Park', members: members);
      expect(conversationTitle(l10n, group, localUserId: 'user-atlas'), 'Selene Park, @jiwoo');
      // A group this device knows no member of is still called something.
      expect(conversationTitle(l10n, conversation(type: ConversationType.group), localUserId: 'user-atlas'), 'Group');
    });
  });

  test('counts read as counts in both languages: no "(s)", and no "(으)"', () {
    final ko = lookupAppLocalizations(const Locale('ko'));
    expect(l10n.chatBannerFailedSends(1), startsWith('1 message was not sent.'));
    expect(l10n.chatBannerFailedSends(2), startsWith('2 messages were not sent.'));
    expect(l10n.chatGroupMemberCount(1), '1 member');
    expect(l10n.chatGroupMemberCount(4), '4 members');
    expect(l10n.conversationsQueued(1), '1 message waiting to be sent');
    expect(l10n.conversationsQueued(3), '3 messages waiting to be sent');
    expect(l10n.chatDurationMinutes(1), '1 minute');
    expect(l10n.chatDurationMinutes(5), '5 minutes');
    for (final text in [
      l10n.chatBannerFailedSends(2),
      l10n.chatBannerQueuedMessages(2),
      l10n.chatBannerUploadingAttachments(2),
      l10n.chatNetworkRecoveryFailed(2, ''),
      l10n.chatNetworkRecoveryUploading(2, ''),
      l10n.chatNetworkRecoveryQueued(2, ''),
      l10n.chatDurationDays(2),
      l10n.chatDurationHours(2),
      l10n.chatDurationSeconds(2),
      ko.chatBannerFailedSends(2),
      ko.chatAccountHoldOtherBody('selene'),
      ko.chatAccountHoldOwnBody('atlas'),
    ]) {
      expect(text, isNot(contains('(s)')), reason: text);
      expect(text, isNot(contains('(으)')), reason: text);
    }
    expect(ko.chatGroupMemberCount(4), '멤버 4명');
    expect(ko.conversationsQueued(3), '보내기 대기 중인 메시지 3개');
  });

  test('messageDeliveryLabel handles all delivery states exhaustively', () {
    for (final state in MessageDeliveryState.values) {
      expect(
        messageDeliveryLabel(l10n, _message(state)),
        isNotEmpty,
        reason: 'Missing label for $state',
      );
    }
  });

  test('formatRetryCountdown handles imminent and distant retries', () {
    final imminent = DateTime.now().add(const Duration(seconds: 1));
    final distant = DateTime.now().add(const Duration(minutes: 10, seconds: 30));
    final past = DateTime.now().subtract(const Duration(seconds: 5));

    expect(formatRetryCountdown(l10n, imminent), matches(RegExp(r'^[0-9]+s$')));
    expect(formatRetryCountdown(l10n, distant), matches(RegExp(r'^10m [0-9]+s$')));
    expect(formatRetryCountdown(l10n, past), matches(RegExp(r'^0s$')));
  });

  test('messageBubbleSemanticsLabel omits delivery state for received messages', () {
    final received = _message(MessageDeliveryState.read).copyWith(isMine: false);
    expect(
      messageBubbleSemanticsLabel(l10n, received),
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
