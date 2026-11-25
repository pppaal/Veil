import 'package:flutter/material.dart' show IconData, Icons;

import '../../../core/crypto/crypto_engine.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../chat/presentation/chat_room_labels.dart';
import '../../chat/presentation/decrypt_status_view.dart';
import '../../chat/presentation/disappearing_timer_sheet.dart';
import '../../chat/presentation/message_expiration.dart';
import '../data/conversation_models.dart';
import '../data/veil_messenger_controller.dart';
import 'peer_names.dart';

// The words the conversation list shows for a conversation, for its last
// message, and for a message found by the local search.

/// The name on a conversation's row: a 1:1 by the nickname the user gave its
/// peer (see PeerNames), or else their handle (the row draws the handle's
/// first letter as the avatar, so without its @); a group as the chat
/// titles it (see conversationTitle).
String conversationRowTitle(
  AppLocalizations l10n,
  ConversationPreview item,
  PeerNames names, {
  required String? localUserId,
}) =>
    item.type == ConversationType.direct
        ? names.peerName(item) ?? item.peerHandle
        : conversationTitle(l10n, item, names, localUserId: localUserId);

/// What a screen reader calls the row.
String conversationRowSemantics(
  AppLocalizations l10n,
  ConversationPreview item,
  PeerNames names, {
  required String? localUserId,
}) {
  final title = conversationRowTitle(l10n, item, names, localUserId: localUserId);
  return item.type == ConversationType.direct
      ? l10n.conversationsRowSemantics(title)
      : l10n.conversationsGroupRowSemantics(title);
}

/// The line under a conversation's name: what was not sent or waits to be
/// sent, or the last message. Only a text this device decrypted is quoted,
/// a system line by its own words and a file by its sanitized name; every
/// other kind is named by its decrypted kind, never by the envelope's
/// unauthenticated one. In a group the text is led by who wrote it: "You:
/// …", or [groupSender] when this device knows the member. A message
/// [request] (a chat not accepted yet) quotes nothing: "Message request".
String conversationPreviewLine(
  AppLocalizations l10n,
  ConversationPreview item,
  VeilMessengerController controller, {
  String? groupSender,
  bool request = false,
}) =>
    conversationPreview(l10n, item, controller, groupSender: groupSender, request: request).text;

/// [conversationPreviewLine], with the glyph a photo or a file shows in it
/// ([icon], before the character at [iconAt]: after any "Omar: " that leads
/// the line), as Telegram and WhatsApp draw it.
({String text, IconData? icon, int iconAt}) conversationPreview(
  AppLocalizations l10n,
  ConversationPreview item,
  VeilMessengerController controller, {
  String? groupSender,
  bool request = false,
}) {
  ({String text, IconData? icon, int iconAt}) plain(String text) => (text: text, icon: null, iconAt: 0);
  // No word of a stranger's text outside the chat.
  if (request) return plain(l10n.conversationsRequestPreview);
  final pendingCount = controller.pendingCountFor(item.id);
  if (pendingCount > 0) {
    final failedCount = controller.messagesFor(item.id).where((message) => message.hasFailed).length;
    return plain(failedCount > 0 ? l10n.conversationsNotSent(failedCount) : l10n.conversationsQueued(pendingCount));
  }

  final envelope = item.lastEnvelope;
  if (envelope == null) {
    return plain(l10n.conversationsPreviewEmpty);
  }

  if (isMessageExpired(envelope.expiresAt, now: controller.expiryNow())) {
    return plain(l10n.conversationsPreviewExpired);
  }

  final last = controller.messagesFor(item.id).lastOrNull;
  final kind = controller.lastMessageKindFor(item.id) ?? MessageKind.text;
  if (kind == MessageKind.system && last != null) {
    final body = controller.lastMessageBodyFor(item.id);
    if (body != null) return plain(systemNoticeText(l10n, last, body));
  }
  final icon = switch (kind) {
    MessageKind.image => Icons.photo_outlined,
    MessageKind.file => Icons.insert_drive_file_outlined,
    _ => null,
  };
  final text = kind == MessageKind.file
      ? controller.lastMessageBodyFor(item.id) ?? l10n.conversationsPreviewAttachment
      : controller.lastMessagePreviewFor(item.id) ?? _kindPreview(l10n, kind);
  if (item.type != ConversationType.group || last == null || last.isLocalNotice || kind == MessageKind.system) {
    return (text: text, icon: icon, iconAt: 0);
  }
  final line = last.isMine
      ? l10n.conversationsPreviewYou(text)
      : groupSender == null
          ? text
          : l10n.conversationsPreviewSender(groupSender, text);
  return (text: line, icon: icon, iconAt: icon == null ? 0 : line.lastIndexOf(text).clamp(0, line.length));
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
