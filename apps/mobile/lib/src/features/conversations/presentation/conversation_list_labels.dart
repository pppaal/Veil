import 'package:intl/intl.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../chat/presentation/chat_room_labels.dart';
import '../../chat/presentation/decrypt_status_view.dart';
import '../../chat/presentation/disappearing_timer_sheet.dart';
import '../../chat/presentation/message_expiration.dart';
import '../data/conversation_models.dart';
import '../data/veil_messenger_controller.dart';

// The words the conversation list shows for a conversation, for its last
// message, and for a message found by the local search.

/// The name on a conversation's row: a 1:1 by its peer's name or handle (the
/// row draws the handle's first letter as the avatar, so without its @), a
/// group as the chat titles it (see conversationTitle).
String conversationRowTitle(AppLocalizations l10n, ConversationPreview item, {required String? localUserId}) =>
    item.type == ConversationType.direct
        ? item.peerDisplayName ?? item.peerHandle
        : conversationTitle(l10n, item, localUserId: localUserId);

/// What a screen reader calls the row.
String conversationRowSemantics(AppLocalizations l10n, ConversationPreview item, {required String? localUserId}) {
  final title = conversationRowTitle(l10n, item, localUserId: localUserId);
  return item.type == ConversationType.direct
      ? l10n.conversationsRowSemantics(title)
      : l10n.conversationsGroupRowSemantics(title);
}

/// The line under a conversation's name: what was not sent or waits to be
/// sent, or the last message. Only a text this device decrypted is quoted,
/// and a system line by its own words; every other kind is named by its
/// decrypted kind, never by the envelope's unauthenticated one. In a group
/// the text is led by who wrote it: "You: …", or [groupSender] when this
/// device knows the member.
String conversationPreviewLine(
  AppLocalizations l10n,
  ConversationPreview item,
  VeilMessengerController controller, {
  String? groupSender,
}) {
  final pendingCount = controller.pendingCountFor(item.id);
  if (pendingCount > 0) {
    final failedCount = controller.messagesFor(item.id).where((message) => message.hasFailed).length;
    return failedCount > 0 ? l10n.conversationsNotSent(failedCount) : l10n.conversationsQueued(pendingCount);
  }

  final envelope = item.lastEnvelope;
  if (envelope == null) {
    return l10n.conversationsPreviewEmpty;
  }

  if (isMessageExpired(envelope.expiresAt, now: controller.expiryNow())) {
    return l10n.conversationsPreviewExpired;
  }

  final last = controller.messagesFor(item.id).lastOrNull;
  final kind = controller.lastMessageKindFor(item.id) ?? MessageKind.text;
  if (kind == MessageKind.system && last != null) {
    final body = controller.lastMessageBodyFor(item.id);
    if (body != null) return systemNoticeText(l10n, last, body);
  }
  final text = controller.lastMessagePreviewFor(item.id) ?? _kindPreview(l10n, kind);
  if (item.type != ConversationType.group || last == null || last.isLocalNotice || kind == MessageKind.system) {
    return text;
  }
  if (last.isMine) return l10n.conversationsPreviewYou(text);
  return groupSender == null ? text : l10n.conversationsPreviewSender(groupSender, text);
}

String _kindPreview(AppLocalizations l10n, MessageKind kind) {
  return switch (kind) {
    MessageKind.image => l10n.conversationsPreviewImage,
    MessageKind.file => l10n.conversationsPreviewAttachment,
    // A system line whose words did not open.
    MessageKind.system => l10n.conversationsPreviewMessage,
    MessageKind.text => l10n.conversationsPreviewMessage,
    MessageKind.voice => l10n.conversationsPreviewVoice,
    MessageKind.sticker => l10n.conversationsPreviewSticker,
    MessageKind.reaction => l10n.conversationsPreviewReaction,
    // Calls are not part of this app: such a message is named as any
    // other whose text this list does not quote.
    MessageKind.call => l10n.conversationsPreviewMessage,
  };
}

/// What a screen reader hears about a chat whose messages disappear, which
/// its row marks with the timer glyph: the chat's timer ("Disappearing: 1
/// day"), or when its last message disappears ("Expires in 5m"). Null when
/// nothing in it disappears.
String? conversationTimerLabel(AppLocalizations l10n, ConversationPreview item, VeilMessengerController controller) {
  final seconds = item.disappearingTimerSeconds;
  if (seconds != null) return l10n.chatTimerTooltip(disappearingTimerLabel(l10n, Duration(seconds: seconds)));
  return conversationExpiryLabel(l10n, item, controller);
}

/// "Expires in 5m" for a conversation whose last message disappears.
String? conversationExpiryLabel(
  AppLocalizations l10n,
  ConversationPreview item,
  VeilMessengerController controller,
) {
  final expiresAt = item.lastEnvelope?.expiresAt;
  return expiresAt == null ? null : formatMessageExpiry(l10n, expiresAt, now: controller.expiryNow());
}

/// The time of a message sent today, the day of an older one.
String messageDateLabel(DateTime sentAt, DateFormat timeFormat, String localeName) {
  final now = DateTime.now();
  if (sentAt.year == now.year && sentAt.month == now.month && sentAt.day == now.day) {
    return timeFormat.format(sentAt);
  }
  return DateFormat.MMMd(localeName).format(sentAt);
}
