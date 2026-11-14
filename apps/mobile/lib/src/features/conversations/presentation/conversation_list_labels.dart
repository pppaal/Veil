import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../chat/presentation/message_expiration.dart';
import '../data/conversation_models.dart';
import '../data/veil_messenger_controller.dart';

// The words the conversation list shows for a conversation's last message
// and for a message found by the local search.

/// The line under a conversation's name: what waits to be sent, or the last
/// message. Only a text this device decrypted is quoted; every other kind is
/// named by its decrypted kind, never by the envelope's unauthenticated one.
String conversationPreviewLine(
  AppLocalizations l10n,
  ConversationPreview item,
  VeilMessengerController controller,
) {
  final pendingCount = controller.pendingCountFor(item.id);
  if (pendingCount > 0) {
    return pendingCount == 1 ? l10n.conversationsQueuedOne : l10n.conversationsQueuedMany(pendingCount);
  }

  final envelope = item.lastEnvelope;
  if (envelope == null) {
    return l10n.conversationsPreviewEmpty;
  }

  if (isMessageExpired(envelope.expiresAt, now: controller.expiryNow())) {
    return l10n.conversationsPreviewExpired;
  }

  final previewBody = controller.lastMessagePreviewFor(item.id);
  if (previewBody != null) {
    return previewBody;
  }

  return switch (controller.lastMessageKindFor(item.id) ?? MessageKind.text) {
    MessageKind.image => l10n.conversationsPreviewImage,
    MessageKind.file => l10n.conversationsPreviewAttachment,
    MessageKind.system => l10n.conversationsPreviewSystem,
    MessageKind.text => l10n.conversationsPreviewMessage,
    MessageKind.voice => l10n.conversationsPreviewVoice,
    MessageKind.sticker => l10n.conversationsPreviewSticker,
    MessageKind.reaction => l10n.conversationsPreviewReaction,
    MessageKind.call => l10n.conversationsPreviewCall,
  };
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

String messageKindLabel(AppLocalizations l10n, MessageKind kind) {
  return switch (kind) {
    MessageKind.text => l10n.conversationsFilterText,
    MessageKind.image => l10n.conversationsKindImage,
    MessageKind.file => l10n.conversationsKindAttachment,
    MessageKind.system => l10n.conversationsKindSystem,
    MessageKind.voice => l10n.conversationsKindVoice,
    MessageKind.sticker => l10n.conversationsKindSticker,
    MessageKind.reaction => l10n.conversationsKindReaction,
    MessageKind.call => l10n.conversationsKindCall,
  };
}

IconData messageKindIcon(MessageKind kind) {
  return switch (kind) {
    MessageKind.text => Icons.chat_bubble_outline_rounded,
    MessageKind.image => Icons.image_outlined,
    MessageKind.file => Icons.attach_file_rounded,
    MessageKind.system => Icons.info_outline_rounded,
    MessageKind.voice => Icons.mic_none_rounded,
    MessageKind.sticker => Icons.emoji_emotions_outlined,
    MessageKind.reaction => Icons.favorite_border_rounded,
    MessageKind.call => Icons.call_outlined,
  };
}

/// "You | Text", the sender and kind of a message the search found.
String messageResultOrigin(AppLocalizations l10n, MessageSearchResult result) {
  final sender = result.isMine ? l10n.conversationsResultFromYou : l10n.conversationsResultFromPeer;
  return '$sender | ${messageKindLabel(l10n, result.messageKind)}';
}

/// The time of a message sent today, the day of an older one.
String messageDateLabel(DateTime sentAt, DateFormat timeFormat, String localeName) {
  final now = DateTime.now();
  if (sentAt.year == now.year && sentAt.month == now.month && sentAt.day == now.day) {
    return timeFormat.format(sentAt);
  }
  return DateFormat.MMMd(localeName).format(sentAt);
}
