import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';

// The words and formats the chat screen shows for delivery, history,
// timers and attachments. Pure functions of their arguments.

String networkRecoveryMessage({
  required AppLocalizations l10n,
  required int failedCount,
  required int queuedCount,
  required int uploadingCount,
  required DateTime? nextRetryAt,
}) {
  final retryLabel = nextRetryAt == null
      ? l10n.chatRetryResumes
      : l10n.chatRetryNextIn(formatRetryCountdown(nextRetryAt));
  if (failedCount > 0) {
    return l10n.chatNetworkRecoveryFailed(failedCount, retryLabel);
  }
  if (uploadingCount > 0) {
    return l10n.chatNetworkRecoveryUploading(uploadingCount, retryLabel);
  }
  return l10n.chatNetworkRecoveryQueued(queuedCount, retryLabel);
}

String historyWindowLabel({
  required AppLocalizations l10n,
  required bool isLoadingHistory,
  required bool hasMoreHistory,
}) {
  if (isLoadingHistory) {
    return l10n.chatMetricHistoryLoading;
  }
  if (hasMoreHistory) {
    return l10n.chatMetricHistoryPaged;
  }
  return l10n.chatMetricHistoryComplete;
}

HistoryWindowBannerSpec? historyWindowBannerSpec({
  required AppLocalizations l10n,
  required bool isLoadingHistory,
  required bool hasMoreHistory,
}) {
  if (isLoadingHistory) {
    return HistoryWindowBannerSpec(
      title: l10n.chatBannerHistoryLoadingTitle,
      message: l10n.chatBannerHistoryLoadingBody,
      tone: VeilBannerTone.info,
      icon: Icons.history_toggle_off_rounded,
    );
  }
  if (!hasMoreHistory) {
    return HistoryWindowBannerSpec(
      title: l10n.chatBannerHistoryCompleteTitle,
      message: l10n.chatBannerHistoryCompleteBody,
      tone: VeilBannerTone.info,
      icon: Icons.done_all_rounded,
    );
  }
  return null;
}

class HistoryWindowBannerSpec {
  const HistoryWindowBannerSpec({
    required this.title,
    required this.message,
    required this.tone,
    required this.icon,
  });

  final String title;
  final String message;
  final VeilBannerTone tone;
  final IconData icon;
}

String formatRetryCountdown(DateTime nextRetryAt) {
  final difference = nextRetryAt.difference(DateTime.now());
  if (difference.inSeconds <= 0) {
    return '0s';
  }
  if (difference.inSeconds < 60) {
    return '${difference.inSeconds}s';
  }
  final minutes = difference.inMinutes;
  final seconds = difference.inSeconds - (minutes * 60);
  if (seconds <= 0) {
    return '${minutes}m';
  }
  return '${minutes}m ${seconds}s';
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

VeilBannerTone messageDeliveryTone(ChatMessage message) {
  switch (message.deliveryState) {
    case MessageDeliveryState.pending:
    case MessageDeliveryState.uploading:
      return VeilBannerTone.warn;
    case MessageDeliveryState.failed:
      return VeilBannerTone.danger;
    case MessageDeliveryState.sent:
      return VeilBannerTone.info;
    case MessageDeliveryState.delivered:
    case MessageDeliveryState.read:
      return VeilBannerTone.good;
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
  if (contentType.startsWith('image/')) return Icons.image_rounded;
  if (contentType.startsWith('video/')) return Icons.videocam_rounded;
  if (contentType.startsWith('audio/')) return Icons.audiotrack_rounded;
  if (contentType.contains('pdf')) return Icons.picture_as_pdf_rounded;
  return Icons.insert_drive_file_rounded;
}

String attachmentLabel(AppLocalizations l10n, String contentType) {
  if (contentType.startsWith('image/')) return l10n.chatAttachmentEncryptedImage;
  if (contentType.startsWith('video/')) return l10n.chatAttachmentEncryptedVideo;
  if (contentType.startsWith('audio/')) return l10n.chatAttachmentEncryptedAudio;
  if (contentType.contains('pdf')) return l10n.chatAttachmentEncryptedDocument;
  return l10n.chatAttachmentEncryptedFile;
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
