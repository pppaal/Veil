import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../attachments/attachments_feature.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';
import 'decrypt_status_view.dart';
import 'message_attachment_views.dart';
import 'message_expiry_label.dart';

/// One message as a bubble on its sender's side: the decrypted text, or
/// the chip for a message that did not open, any attachment and its
/// transfer, and the time, delivery state and expiry. Swiping it primes a
/// reply. A bubble takes at most 340 px and, on a narrow screen, 82% of the
/// width, so the side it sits on still tells who wrote it.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.highlighted,
    required this.sentAtFormat,
    required this.decryptFuture,
    required this.onResolveAttachment,
    required this.onCancelAttachment,
    required this.isResolvingAttachment,
    required this.attachmentDownloadError,
    required this.transferSnapshot,
    required this.onReplyGesture,
    required this.expiryNow,
    this.onRetryMessage,
  });

  final ChatMessage message;
  final bool highlighted;
  final DateFormat sentAtFormat;
  final Future<DecryptedMessage> decryptFuture;
  final Future<void> Function(String attachmentId) onResolveAttachment;
  final VoidCallback? onCancelAttachment;
  final bool Function(String attachmentId) isResolvingAttachment;
  final String? Function(String attachmentId) attachmentDownloadError;
  final AttachmentTransferSnapshot? transferSnapshot;
  final VoidCallback onReplyGesture;
  final DateTime Function() expiryNow;
  final VoidCallback? onRetryMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final alignment =
        message.isMine ? Alignment.centerRight : Alignment.centerLeft;
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    // On the violet of the user's own bubbles the palette's status colours
    // do not read: what is written there is white.
    final metaColor = message.isMine ? Colors.white.withValues(alpha: 0.82) : palette.textMuted;
    final metaStyle = theme.textTheme.bodySmall?.copyWith(color: metaColor, fontSize: 11.5, height: 1.2);
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.38);

    final bubble = Semantics(
      label: messageBubbleSemanticsLabel(l10n, message),
      child: AnimatedContainer(
        duration: VeilMotion.normal,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VeilRadius.lg + 2),
          border: highlighted
              ? Border.all(color: context.veilPalette.primary, width: 1.2)
              : null,
          color: highlighted ? context.veilPalette.primarySoft : Colors.transparent,
        ),
        child: Dismissible(
          key: ValueKey('reply-${message.id}'),
          direction: DismissDirection.startToEnd,
          confirmDismiss: (_) async {
            onReplyGesture();
            return false;
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VeilRadius.lg),
              color: context.veilPalette.primarySoft,
              border: Border.all(color: context.veilPalette.strokeStrong),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.reply_rounded),
                const SizedBox(width: VeilSpace.xs),
                Text(l10n.chatReplyLocally),
              ],
            ),
          ),
          child: VeilMessageBubbleCard(
            isMine: message.isMine,
            highlighted: highlighted,
            child: FutureBuilder<DecryptedMessage>(
              future: decryptFuture,
              builder: (context, snapshot) {
                final decrypted = snapshot.data;
                final status = decrypted?.status;
                // Attachment metadata comes only from the authenticated
                // payload; the envelope carries a bare pointer.
                final attachment = decrypted?.attachment;
                final attachmentId = attachment?.attachmentId;
                final attachmentResolving =
                    attachmentId != null && isResolvingAttachment(attachmentId);
                final downloadError =
                    attachmentId == null ? null : attachmentDownloadError(attachmentId);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    switch (status) {
                      null => Text(l10n.chatDecryptingEnvelope, style: bodyStyle),
                      DecryptStatus.ok => Text(decrypted!.body, style: bodyStyle),
                      DecryptStatus.legacyUnauthenticated => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(decrypted!.body, style: bodyStyle),
                            const SizedBox(height: VeilSpace.xs),
                            VeilStatusPill(label: l10n.chatLegacyUnverifiedBadge, tone: VeilBannerTone.warn),
                          ],
                        ),
                      _ => DecryptFailureChip(status: status),
                    },
                    if (transferSnapshot != null) ...[
                      const SizedBox(height: 12),
                      AttachmentTransferPanel(
                        snapshot: transferSnapshot!,
                        onRetry: onRetryMessage,
                        onCancel: transferSnapshot!.canCancel
                            ? onCancelAttachment
                            : null,
                      ),
                    ],
                    if (attachment != null) ...[
                      const SizedBox(height: 12),
                      MessageAttachmentCard(
                        attachment: attachment,
                        resolving: attachmentResolving,
                        downloadError: downloadError,
                        onResolve:
                            kAttachmentsEnabled ? () => onResolveAttachment(attachment.attachmentId) : null,
                        onRetry: message.hasFailed ? onRetryMessage : null,
                      ),
                    ],
                    if (message.hasFailed &&
                        attachment == null &&
                        onRetryMessage != null) ...[
                      const SizedBox(height: VeilSpace.xs),
                      _BubbleRetryButton(label: l10n.chatRetrySend, onPressed: onRetryMessage!),
                    ],
                    const SizedBox(height: VeilSpace.xxs + 2),
                    // Wraps instead of cutting a word short when the time,
                    // the delivery state and the expiry do not fit one line.
                    Wrap(
                      spacing: VeilSpace.xs,
                      runSpacing: VeilSpace.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(sentAtFormat.format(message.sentAt), style: metaStyle),
                        if (message.isMine) _DeliveryMark(message: message, style: metaStyle),
                        if (message.expiresAt != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined, size: 12, color: metaColor),
                              const SizedBox(width: 2),
                              Flexible(
                                child: MessageExpiryLabel(
                                  expiresAt: message.expiresAt!,
                                  now: expiryNow,
                                  style: metaStyle,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.min(344, constraints.maxWidth * 0.82)),
          child: bubble,
        ),
      ),
    );
  }
}

/// How far one of the user's own messages got, as an icon and a word. A
/// failed send is set apart on a dark chip.
class _DeliveryMark extends StatelessWidget {
  const _DeliveryMark({required this.message, required this.style});

  final ChatMessage message;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final failed = message.deliveryState == MessageDeliveryState.failed;
    final icon = switch (message.deliveryState) {
      MessageDeliveryState.pending => Icons.schedule_rounded,
      MessageDeliveryState.uploading => Icons.upload_rounded,
      MessageDeliveryState.failed => Icons.error_outline_rounded,
      MessageDeliveryState.sent => Icons.done_rounded,
      MessageDeliveryState.delivered || MessageDeliveryState.read => Icons.done_all_rounded,
    };
    final read = message.deliveryState == MessageDeliveryState.read;
    final color = failed || read ? Colors.white : style?.color;
    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            messageDeliveryLabel(AppLocalizations.of(context), message),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(color: color, fontWeight: failed || read ? FontWeight.w700 : null),
          ),
        ),
      ],
    );
    if (!failed) return mark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xs, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(VeilRadius.pill),
      ),
      child: mark,
    );
  }
}

/// Retry for a failed send, readable on the violet of the user's own bubble.
class _BubbleRetryButton extends StatelessWidget {
  const _BubbleRetryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.28),
        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
      ),
      onPressed: () {
        VeilHaptics.light();
        onPressed();
      },
      icon: const Icon(Icons.refresh_rounded, size: VeilIconSize.sm),
      label: Text(label),
    );
  }
}
