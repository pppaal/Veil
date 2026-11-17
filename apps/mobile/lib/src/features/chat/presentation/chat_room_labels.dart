import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/presentation/peer_names.dart';

// The words and formats the chat screen shows for who a chat is with,
// delivery, timers and attachments. Pure functions of their arguments.

/// What a conversation is called. A 1:1 by the nickname the user gave its
/// peer on this phone, or their handle when there is none (see PeerNames:
/// the server keeps no names). A group by its name, which the relay's
/// conversation list leaves out and the sync asks for once per group; until
/// that answer comes, or when it fails, by its other members. [localUserId]
/// is this user, who is left out of that list of names.
String conversationTitle(
  AppLocalizations l10n,
  ConversationPreview conversation,
  PeerNames names, {
  required String? localUserId,
}) {
  if (conversation.type == ConversationType.direct) {
    return names.peerName(conversation) ?? '@${conversation.peerHandle}';
  }
  final name = (conversation.groupMeta?.name ?? conversation.channelMeta?.name)?.trim();
  if (name != null && name.isNotEmpty) return name;
  final others = [
    for (final member in conversation.members)
      if (member.userId != localUserId) names.memberTitle(member),
  ];
  return others.isEmpty ? l10n.conversationsGroupMark : others.join(', ');
}

/// What a group calls the member typing under [handle], as its bubbles call
/// them: their nickname, or the handle with its "@". The member is the
/// account [userId] the typing event named; with none, the one listed under
/// [handle] whatever its case (or "@handle" when none is). Null for an
/// account the group does not list: no member is typing, and nothing shows.
String? typingMemberTitle(ConversationPreview group, String handle, PeerNames names, {String userId = ''}) {
  for (final member in group.members) {
    final typing = userId.isNotEmpty ? member.userId == userId : member.handle.toLowerCase() == handle.toLowerCase();
    if (typing) return names.memberTitle(member);
  }
  return userId.isEmpty ? '@$handle' : null;
}

String messageDeliveryLabel(AppLocalizations l10n, ChatMessage message) {
  switch (message.deliveryState) {
    case MessageDeliveryState.pending:
      return l10n.chatDeliveryQueued;
    case MessageDeliveryState.uploading:
      return l10n.chatDeliveryUploading;
    case MessageDeliveryState.failed:
      return l10n.chatDeliveryFailed;
    case MessageDeliveryState.sent:
      return l10n.chatDeliverySent;
    case MessageDeliveryState.delivered:
      return l10n.chatDeliveryDelivered;
    case MessageDeliveryState.read:
      return l10n.chatDeliveryRead;
  }
}

VeilTone messageDeliveryTone(ChatMessage message) {
  switch (message.deliveryState) {
    case MessageDeliveryState.pending:
    case MessageDeliveryState.uploading:
      return VeilTone.warn;
    case MessageDeliveryState.failed:
      return VeilTone.danger;
    case MessageDeliveryState.sent:
      return VeilTone.info;
    case MessageDeliveryState.delivered:
    case MessageDeliveryState.read:
      return VeilTone.good;
  }
}

String messageBubbleSemanticsLabel(AppLocalizations l10n, ChatMessage message) {
  final direction =
      message.isMine ? l10n.chatSemanticsSent : l10n.chatSemanticsReceived;
  final stateSegment = message.isMine
      ? l10n.chatSemanticsStateSegment(messageDeliveryLabel(l10n, message))
      : '';
  return l10n.chatSemanticsBubble(direction, stateSegment);
}

String formatDurationLabel(AppLocalizations l10n, Duration duration) {
  if (duration.inDays > 0) return l10n.chatDurationDays(duration.inDays);
  if (duration.inHours > 0) return l10n.chatDurationHours(duration.inHours);
  if (duration.inMinutes > 0) return l10n.chatDurationMinutes(duration.inMinutes);
  return l10n.chatDurationSeconds(duration.inSeconds);
}

IconData attachmentIcon(String contentType) {
  if (contentType.startsWith('image/')) return Icons.image_outlined;
  if (contentType.startsWith('video/')) return Icons.videocam_outlined;
  if (contentType.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (contentType.contains('pdf')) return Icons.picture_as_pdf_outlined;
  return Icons.insert_drive_file_outlined;
}

/// What kind of file an attachment is, by its type: "Photo", "File".
String attachmentLabel(AppLocalizations l10n, String contentType) {
  if (contentType.startsWith('image/')) return l10n.chatAttachmentKindPhoto;
  if (contentType.startsWith('video/')) return l10n.chatAttachmentKindVideo;
  if (contentType.startsWith('audio/')) return l10n.chatAttachmentKindAudio;
  return l10n.chatAttachmentKindFile;
}

/// The type of an attachment as a file card names it: "PDF" for a PDF (its
/// subtype, as WhatsApp's card says it), otherwise the kind of file.
String attachmentTypeLabel(AppLocalizations l10n, String contentType) {
  if (contentType.contains('pdf')) return contentType.split('/').last.toUpperCase();
  return attachmentLabel(l10n, contentType);
}

/// A file's size as WhatsApp and Signal write it: whole bytes and
/// kilobytes ("56 KB"), and megabytes and gigabytes to one place, without
/// a trailing ".0" ("2.3 MB", "5 GB").
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  String onePlace(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  if (bytes < 1024 * 1024 * 1024) return '${onePlace(bytes / (1024 * 1024))} MB';
  return '${onePlace(bytes / (1024 * 1024 * 1024))} GB';
}
