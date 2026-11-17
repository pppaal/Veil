import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';

/// The attachment a received message carries, from its authenticated
/// payload: one tile with its [name], "PDF · 2.3 MB" ("Voice message ·
/// 56 KB" for a [voice] message), and the line that this version cannot
/// open it.
///
/// In a grey bubble the bubble is the tile; on the brand fill of the
/// user's own bubble ([framed]) the tile is drawn, so its text reads.
class MessageAttachmentCard extends StatelessWidget {
  const MessageAttachmentCard({
    super.key,
    required this.attachment,
    this.name = '',
    this.framed = false,
    this.voice = false,
  });

  final AttachmentReference attachment;

  /// The file's name, as the message's text gives it; empty when it has
  /// none.
  final String name;

  /// Whether to draw the tile's own grey fill.
  final bool framed;

  /// Whether the message is a voice message (its kind), which the tile
  /// names so, with a microphone, whatever type the recording's file is.
  final bool voice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              voice ? Icons.mic_none_outlined : attachmentIcon(attachment.contentType),
              size: VeilIconSize.md,
              color: palette.textMuted,
            ),
            const SizedBox(width: VeilSpace.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(color: palette.text),
                    ),
                  Text(
                    l10n.chatAttachmentTypeSize(
                      voice ? l10n.chatAttachmentKindVoice : attachmentTypeLabel(l10n, attachment.contentType),
                      formatFileSize(attachment.sizeBytes),
                    ),
                    style: name.isEmpty ? theme.textTheme.titleSmall?.copyWith(color: palette.text) : muted,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: VeilSpace.xs),
        Text(l10n.chatAttachmentCannotOpen, style: muted),
      ],
    );
    if (!framed) return content;
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.surfaceAlt, borderRadius: BorderRadius.circular(VeilRadius.md)),
      child: Padding(padding: const EdgeInsets.all(VeilSpace.sm), child: content),
    );
  }
}

/// How far an attachment this device is sending has got: its name, one line
/// on what is happening, a thin progress bar with the phase and the share
/// done in words under it, the error when there is one, and retry and
/// cancel where the transfer allows them. Drawn in [color] and [mutedColor],
/// the bubble's own text colours (the text colours of the page when null).
class AttachmentTransferPanel extends StatelessWidget {
  const AttachmentTransferPanel({
    super.key,
    required this.snapshot,
    this.color,
    this.mutedColor,
    this.onRetry,
    this.onCancel,
  });

  final AttachmentTransferSnapshot snapshot;
  final Color? color;
  final Color? mutedColor;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final color = this.color ?? palette.text;
    final mutedColor = this.mutedColor ?? palette.textMuted;
    final contentType = snapshot.contentType ?? 'application/octet-stream';
    final muted = theme.textTheme.bodySmall?.copyWith(color: mutedColor);
    final status = theme.textTheme.labelMedium?.copyWith(color: mutedColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(attachmentIcon(contentType), size: VeilIconSize.md, color: mutedColor),
            const SizedBox(width: VeilSpace.sm),
            Flexible(
              child: Text(
                snapshot.filename ?? attachmentLabel(l10n, contentType),
                style: theme.textTheme.titleSmall?.copyWith(color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: VeilSpace.xxs),
        Text(_phaseDescription(l10n, snapshot), style: muted),
        const SizedBox(height: VeilSpace.xs),
        LinearProgressIndicator(
          minHeight: 2,
          color: color,
          backgroundColor: mutedColor.withValues(alpha: 0.3),
          value: switch (snapshot.phase) {
            AttachmentTransferPhase.staged => 0,
            AttachmentTransferPhase.preparing => null,
            AttachmentTransferPhase.uploading => snapshot.progress,
            AttachmentTransferPhase.finalizing => null,
            AttachmentTransferPhase.failed => snapshot.progress.clamp(0, 1),
            AttachmentTransferPhase.canceled => snapshot.progress.clamp(0, 1),
          },
        ),
        const SizedBox(height: VeilSpace.xxs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_phaseLabel(l10n, snapshot.phase), style: status),
            const SizedBox(width: VeilSpace.xs),
            Text('${(snapshot.progress * 100).round()}%', style: status),
          ],
        ),
        // A cancel is said by the description above. The outbox's own
        // sentence for it has no translation and would only repeat it.
        if (snapshot.errorMessage != null && snapshot.phase != AttachmentTransferPhase.canceled) ...[
          const SizedBox(height: VeilSpace.xs),
          VeilNotice(
            title: l10n.chatAttachmentStateBanner,
            message: veilErrorText(l10n, snapshot.errorMessage!),
            tone: VeilTone.warn,
            margin: EdgeInsets.zero,
          ),
        ],
        // The gap is padding, not the Wrap's spacing: the bubble takes this
        // panel's intrinsic width, and a Wrap leaves its spacing out of it.
        if (onRetry != null || onCancel != null)
          Wrap(
            children: [
              if (onRetry != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: color),
                  onPressed: onRetry,
                  child: Text(l10n.chatRetryUpload),
                ),
              if (onCancel != null)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: onRetry != null ? VeilSpace.xs : 0),
                  child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: color),
                    onPressed: onCancel,
                    child: Text(l10n.chatCancelAction),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  String _phaseLabel(AppLocalizations l10n, AttachmentTransferPhase phase) {
    return switch (phase) {
      AttachmentTransferPhase.staged => l10n.chatPhaseStaged,
      AttachmentTransferPhase.preparing => l10n.chatPhasePreparing,
      AttachmentTransferPhase.uploading => l10n.chatPhaseUploading,
      AttachmentTransferPhase.finalizing => l10n.chatPhaseFinalizing,
      AttachmentTransferPhase.failed => l10n.chatPhaseFailed,
      AttachmentTransferPhase.canceled => l10n.chatPhaseCanceled,
    };
  }

  String _phaseDescription(AppLocalizations l10n, AttachmentTransferSnapshot snapshot) {
    final sizeLabel = snapshot.sizeBytes == null ? '' : l10n.chatAttachmentSizeBytes(snapshot.sizeBytes!);
    return switch (snapshot.phase) {
      AttachmentTransferPhase.staged => l10n.chatPhaseDescStaged(sizeLabel),
      AttachmentTransferPhase.preparing => l10n.chatPhaseDescPreparing,
      AttachmentTransferPhase.uploading => l10n.chatPhaseDescUploading,
      AttachmentTransferPhase.finalizing => l10n.chatPhaseDescFinalizing,
      AttachmentTransferPhase.failed =>
        snapshot.errorMessage == null ? l10n.chatPhaseDescFailed : veilErrorText(l10n, snapshot.errorMessage!),
      AttachmentTransferPhase.canceled => l10n.chatPhaseDescCanceled,
    };
  }
}
