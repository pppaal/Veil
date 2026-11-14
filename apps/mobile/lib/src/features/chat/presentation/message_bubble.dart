import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';
import 'decrypt_status_view.dart';
import 'message_attachment_views.dart';
import 'message_expiry_label.dart';

/// One message as a bubble on its sender's side: the decrypted text, or
/// the chip for a message that did not open, any attachment and its
/// transfer, and the time, delivery state and expiry. Swiping it primes a
/// reply.
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

    return Align(
      alignment: alignment,
      child: Semantics(
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
                        null => Text(l10n.chatDecryptingEnvelope),
                        DecryptStatus.ok => Text(decrypted!.body),
                        DecryptStatus.legacyUnauthenticated => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(decrypted!.body),
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
                          onResolve: () => onResolveAttachment(attachment.attachmentId),
                          onRetry: message.hasFailed ? onRetryMessage : null,
                        ),
                      ],
                      if (message.hasFailed &&
                          attachment == null &&
                          onRetryMessage != null) ...[
                        const SizedBox(height: VeilSpace.sm),
                        VeilButton(
                          expanded: false,
                          tone: VeilButtonTone.ghost,
                          onPressed: onRetryMessage,
                          label: l10n.chatRetrySend,
                        ),
                      ],
                      const SizedBox(height: VeilSpace.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            sentAtFormat.format(message.sentAt),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (message.isMine) ...[
                            const SizedBox(width: VeilSpace.xs),
                            Flexible(
                              child: VeilStatusPill(
                                label: messageDeliveryLabel(l10n, message),
                                tone: messageDeliveryTone(message),
                              ),
                            ),
                          ],
                          if (message.expiresAt != null) ...[
                            const SizedBox(width: VeilSpace.xs),
                            Flexible(
                              child: MessageExpiryLabel(
                                expiresAt: message.expiresAt!,
                                now: expiryNow,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
