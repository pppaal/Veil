import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';

/// The attachment a received message carries, from its authenticated
/// payload: a flat grey tile with what kind of file it is and how large,
/// and the line that this version cannot open it. Where a build can open
/// attachments ([onResolve]), a text button asks for the download instead.
///
/// In a grey bubble the bubble is the tile; on the brand fill of the
/// user's own bubble ([framed]) the tile is drawn, so its text reads.
class MessageAttachmentCard extends StatelessWidget {
  const MessageAttachmentCard({
    super.key,
    required this.attachment,
    required this.resolving,
    required this.downloadError,
    required this.onResolve,
    this.framed = false,
  });

  final AttachmentReference attachment;
  final bool resolving;
  final String? downloadError;

  /// Asks for the download; null when this build cannot open attachments.
  final VoidCallback? onResolve;

  /// Whether to draw the tile's own grey fill.
  final bool framed;

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
            Icon(attachmentIcon(attachment.contentType), size: VeilIconSize.md, color: palette.textMuted),
            const SizedBox(width: VeilSpace.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachmentLabel(l10n, attachment.contentType),
                    style: theme.textTheme.titleSmall?.copyWith(color: palette.text),
                  ),
                  Text(formatFileSize(attachment.sizeBytes), style: muted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: VeilSpace.xs),
        if (onResolve == null)
          Text(l10n.chatAttachmentCannotOpen, style: muted)
        else ...[
          if (downloadError != null) ...[
            Text(l10n.chatAttachmentTicketFailed, style: muted?.copyWith(color: palette.danger)),
            Text(veilErrorText(l10n, downloadError!), style: muted),
          ],
          TextButton(
            onPressed: resolving ? null : onResolve,
            child: Text(resolving ? l10n.chatAttachmentResolvingAction : l10n.chatAttachmentResolveAction),
          ),
        ],
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
        if (onRetry != null || onCancel != null)
          Wrap(
            spacing: VeilSpace.xs,
            children: [
              if (onRetry != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: color),
                  onPressed: onRetry,
                  child: Text(l10n.chatRetryUpload),
                ),
              if (onCancel != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: color),
                  onPressed: onCancel,
                  child: Text(l10n.chatCancelAction),
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
