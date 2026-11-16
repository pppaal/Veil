import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_runs.dart' show chatDayLabel, sameChatRun;
import 'package:veil_mobile/src/features/chat/presentation/chat_room_labels.dart' show conversationTitle;
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/presentation/peer_names.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';

void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  test('messageDeliveryLabel maps send states to clear user-facing copy', () {
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.pending)), 'Waiting');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.uploading)), 'Uploading');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.failed)), 'Not sent');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.sent)), 'Sent');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.delivered)), 'Delivered');
    expect(messageDeliveryLabel(l10n, _message(MessageDeliveryState.read)), 'Read');
  });

  test('a day divider says today, yesterday, a weekday within the week, then the date', () async {
    // The app's localizations load the date names; a bare test loads them.
    await initializeDateFormatting('en');
    final now = DateTime(2026, 11, 15, 10);
    expect(chatDayLabel(l10n, DateTime(2026, 11, 15, 0, 5), now: now), 'Today');
    expect(chatDayLabel(l10n, DateTime(2026, 11, 14, 23, 50), now: now), 'Yesterday');
    expect(chatDayLabel(l10n, DateTime(2026, 11, 11, 9), now: now), 'Wednesday');
    expect(chatDayLabel(l10n, DateTime(2026, 4, 7, 9), now: now), 'April 7');
    expect(chatDayLabel(l10n, DateTime(2025, 12, 31, 9), now: now), 'December 31, 2025');
    // Stamped by a server ahead of this phone's clock: today, as its Chats
    // row shows its time, not tomorrow's date.
    expect(chatDayLabel(l10n, DateTime(2026, 11, 16, 0, 5), now: now), 'Today');
  });

  test('a run follows the day dividers: one stamped after the phone\'s midnight runs on from today\'s', () {
    // Three minutes apart across midnight, seen while this phone reads
    // 11:59 PM: both sit under the one "Today" divider (sameChatDay), so
    // they are one run.
    final before = _message(MessageDeliveryState.sent, sentAt: DateTime(2026, 4, 6, 23, 58));
    final after = _message(MessageDeliveryState.sent, sentAt: DateTime(2026, 4, 7, 0, 1));
    expect(sameChatRun(before, after, now: DateTime(2026, 4, 6, 23, 59)), isTrue);
    // Seen the next morning, they are on two days with a divider between.
    expect(sameChatRun(before, after, now: DateTime(2026, 4, 7, 9)), isFalse);
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

  group('conversationTitle', () {
    ConversationPreview conversation({
      ConversationType type = ConversationType.direct,
      List<GroupMember> members = const [],
    }) =>
        ConversationPreview(
          id: 'conv-1',
          peerHandle: 'selene',
          peerDisplayName: null,
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
      GroupMember(userId: 'user-atlas', handle: 'atlas'),
      GroupMember(userId: 'user-selene', handle: 'selene'),
      GroupMember(userId: 'user-jiwoo', handle: 'jiwoo'),
    ];
    // The names are the nicknames this phone gave the handles: the server
    // keeps none. Each names the account listed under its handle.
    final names = PeerNames(const {
      'atlas': ContactNickname('Atlas Moreau', userId: 'user-atlas'),
      'selene': ContactNickname('Selene Park', userId: 'user-selene'),
    });

    test('a 1:1 is called by the nickname of the peer\'s handle, or by the handle when it has none', () {
      expect(conversationTitle(l10n, conversation(), names, localUserId: 'user-atlas'), 'Selene Park');
      expect(conversationTitle(l10n, conversation(), PeerNames(const {}), localUserId: 'user-atlas'), '@selene');
    });

    test('a group is called by its other members, never by one of them alone, and never by the user', () {
      final group = conversation(type: ConversationType.group, members: members);
      expect(conversationTitle(l10n, group, names, localUserId: 'user-atlas'), 'Selene Park, @jiwoo');
      // A group this device knows no member of is still called something.
      expect(conversationTitle(l10n, conversation(type: ConversationType.group), names, localUserId: 'user-atlas'), 'Group');
    });
  });

  test('counts read as counts: no "(s)"', () {
    expect(l10n.chatGroupMemberCount(1), '1 member');
    expect(l10n.chatGroupMemberCount(4), '4 members');
    expect(l10n.conversationsQueued(1), '1 message waiting to be sent');
    expect(l10n.conversationsQueued(3), '3 messages waiting to be sent');
    expect(l10n.conversationsNotSent(1), "1 message wasn't sent");
    expect(l10n.conversationsNotSent(3), "3 messages weren't sent");
    expect(l10n.chatDurationMinutes(1), '1 minute');
    expect(l10n.chatDurationMinutes(5), '5 minutes');
    for (final text in [
      l10n.chatDurationDays(2),
      l10n.chatDurationHours(2),
      l10n.chatDurationSeconds(2),
    ]) {
      expect(text, isNot(contains('(s)')), reason: text);
    }
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

  test('messageBubbleSemanticsLabel omits delivery state for received messages', () {
    final received = _message(MessageDeliveryState.read).copyWith(isMine: false);
    expect(
      messageBubbleSemanticsLabel(l10n, received),
      'Received message bubble.',
    );
  });
}

ChatMessage _message(MessageDeliveryState state, {DateTime? sentAt}) {
  return ChatMessage(
    id: 'msg-1',
    clientMessageId: 'client-1',
    senderDeviceId: 'device-1',
    sentAt: sentAt ?? DateTime.utc(2026, 4, 7, 10),
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
