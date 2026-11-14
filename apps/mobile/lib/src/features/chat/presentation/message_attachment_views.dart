import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';

/// The attachment a message carries, from its authenticated payload: what
/// kind of file and how large, the button that asks for a download
/// ticket, and a retry when the message did not send.
class MessageAttachmentCard extends StatelessWidget {
  const MessageAttachmentCard({
    super.key,
    required this.attachment,
    required this.resolving,
    required this.downloadError,
    required this.onResolve,
    this.onRetry,
  });

  final AttachmentReference attachment;
  final bool resolving;
  final String? downloadError;
  final VoidCallback onResolve;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.24),
        border: Border.all(
            color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                attachmentIcon(attachment.contentType),
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachmentLabel(l10n, attachment.contentType),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatFileSize(attachment.sizeBytes)} · ${attachment.contentType}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (downloadError != null) ...[
            const SizedBox(height: 10),
            VeilInlineBanner(
              title: l10n.chatAttachmentTicketFailed,
              message: downloadError!,
              tone: VeilBannerTone.warn,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilButton(
                expanded: false,
                tone: VeilButtonTone.secondary,
                onPressed: resolving ? null : onResolve,
                label: resolving
                    ? l10n.chatAttachmentResolvingAction
                    : l10n.chatAttachmentResolveAction,
              ),
              if (onRetry != null)
                VeilButton(
                  expanded: false,
                  tone: VeilButtonTone.secondary,
                  onPressed: onRetry,
                  label: l10n.chatRetrySend,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How far an attachment this device is sending has got, with retry and
/// cancel where the transfer allows them.
class AttachmentTransferPanel extends StatelessWidget {
  const AttachmentTransferPanel({
    super.key,
    required this.snapshot,
    this.onRetry,
    this.onCancel,
  });

  final AttachmentTransferSnapshot snapshot;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final progressLabel = '${(snapshot.progress * 100).round()}%';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                attachmentIcon(snapshot.contentType ?? 'application/octet-stream'),
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  snapshot.filename ?? attachmentLabel(l10n, snapshot.contentType ?? 'application/octet-stream'),
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _phaseDescription(l10n, snapshot),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: switch (snapshot.phase) {
              AttachmentTransferPhase.staged => 0,
              AttachmentTransferPhase.preparing => null,
              AttachmentTransferPhase.uploading => snapshot.progress,
              AttachmentTransferPhase.finalizing => null,
              AttachmentTransferPhase.failed => snapshot.progress.clamp(0, 1),
              AttachmentTransferPhase.canceled => snapshot.progress.clamp(0, 1),
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(
                label: _phaseLabel(l10n, snapshot.phase),
                tone: switch (snapshot.phase) {
                  AttachmentTransferPhase.failed ||
                  AttachmentTransferPhase.canceled =>
                    VeilBannerTone.warn,
                  AttachmentTransferPhase.finalizing => VeilBannerTone.good,
                  _ => VeilBannerTone.info,
                },
              ),
              VeilStatusPill(
                label: progressLabel,
                tone: VeilBannerTone.info,
              ),
            ],
          ),
          if (snapshot.errorMessage != null) ...[
            const SizedBox(height: 10),
            VeilInlineBanner(
              title: l10n.chatAttachmentStateBanner,
              message: snapshot.errorMessage!,
              tone: VeilBannerTone.warn,
            ),
          ],
          if (onRetry != null || onCancel != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
              if (onRetry != null)
                  VeilButton(
                    expanded: false,
                    tone: VeilButtonTone.secondary,
                    onPressed: onRetry,
                    label: l10n.chatRetryUpload,
                  ),
                if (onCancel != null)
                  VeilButton(
                    expanded: false,
                    tone: VeilButtonTone.ghost,
                    onPressed: onCancel,
                    label: l10n.chatCancelAction,
                  ),
              ],
            ),
          ],
        ],
      ),
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

  String _phaseDescription(
      AppLocalizations l10n, AttachmentTransferSnapshot snapshot) {
    final sizeLabel = snapshot.sizeBytes == null
        ? ''
        : l10n.chatAttachmentSizeBytes(snapshot.sizeBytes!);
    return switch (snapshot.phase) {
      AttachmentTransferPhase.staged =>
        l10n.chatPhaseDescStaged(sizeLabel),
      AttachmentTransferPhase.preparing => l10n.chatPhaseDescPreparing,
      AttachmentTransferPhase.uploading => l10n.chatPhaseDescUploading,
      AttachmentTransferPhase.finalizing => l10n.chatPhaseDescFinalizing,
      AttachmentTransferPhase.failed =>
        snapshot.errorMessage ?? l10n.chatPhaseDescFailed,
      AttachmentTransferPhase.canceled => l10n.chatPhaseDescCanceled,
    };
  }
}
