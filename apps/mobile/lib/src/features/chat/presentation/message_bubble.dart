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

/// One message as a bubble on its sender's side: who of a group wrote it
/// (the first bubble of a run, in the sender's tint), the decrypted text or
/// the line for a message that did not open, any attachment, and the meta
/// at its end: the time, the ticks of the user's own messages ("Read" in
/// words once read) and the time left on a disappearing one.
///
/// A send that failed is a grey bubble with "Not sent. Tap to retry." under
/// it, and a tap on it retries. A message from an older version, whose
/// sender is not proven, says so in a line under the bubble.
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
    required this.expiryNow,
    this.onRetryMessage,
    this.senderName,
    this.senderSeed,
    this.position = VeilBubblePosition.single,
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
  final DateTime Function() expiryNow;
  final VoidCallback? onRetryMessage;

  /// Who of a group wrote the message, shown above it; null in a 1:1, on
  /// the user's own messages, and under another message of the same run.
  final String? senderName;

  /// What the sender's name tint is drawn from (their handle); the name
  /// itself when null.
  final String? senderSeed;

  /// Where the bubble sits in its run of bubbles from the same sender.
  final VeilBubblePosition position;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final failed = message.hasFailed;
    // The colours VeilBubble fills with: own bubbles are the brand fill,
    // everything else (theirs, failed, a search hit) a grey or raised one.
    final onBrand = message.isMine && !failed && !highlighted;
    final textColor = onBrand ? Colors.white : palette.text;
    final metaColor = onBrand ? palette.outgoingMeta : palette.textMuted;
    final metaStyle = theme.textTheme.labelSmall?.copyWith(color: metaColor);
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(color: textColor);

    final content = FutureBuilder<DecryptedMessage>(
      future: decryptFuture,
      builder: (context, snapshot) {
        final decrypted = snapshot.data;
        final status = decrypted?.status;
        // Attachment metadata comes only from the authenticated payload;
        // the envelope carries a bare pointer.
        final attachment = decrypted?.attachment;
        final attachmentId = attachment?.attachmentId;
        final body = switch (status) {
          null => Text(l10n.chatDecryptingEnvelope, style: bodyStyle?.copyWith(color: metaColor)),
          DecryptStatus.ok ||
          DecryptStatus.legacyUnauthenticated =>
            decrypted!.body.isEmpty && attachment != null ? null : Text(decrypted.body, style: bodyStyle),
          _ => DecryptFailureLine(status: status, color: metaColor),
        };
        final bubble = VeilBubble(
          isMine: message.isMine,
          highlighted: highlighted,
          position: position,
          failed: failed,
          failedText: failed ? l10n.chatNotSentTapToRetry : null,
          // As wide as its widest line, so the meta can sit at the end.
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (senderName != null) ...[
                  Text(
                    senderName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: VeilAvatar.nameTint(context, senderSeed ?? senderName!),
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                if (body != null) body,
                if (transferSnapshot != null) ...[
                  const SizedBox(height: VeilSpace.xs),
                  AttachmentTransferPanel(
                    snapshot: transferSnapshot!,
                    color: textColor,
                    mutedColor: metaColor,
                    onRetry: onRetryMessage,
                    onCancel: transferSnapshot!.canCancel ? onCancelAttachment : null,
                  ),
                ],
                if (attachment != null) ...[
                  if (body != null) const SizedBox(height: VeilSpace.xs),
                  MessageAttachmentCard(
                    attachment: attachment,
                    resolving: attachmentId != null && isResolvingAttachment(attachmentId),
                    downloadError: attachmentId == null ? null : attachmentDownloadError(attachmentId),
                    onResolve: kAttachmentsEnabled ? () => onResolveAttachment(attachment.attachmentId) : null,
                    framed: onBrand,
                  ),
                ],
                const SizedBox(height: VeilSpace.xxs),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _Meta(message: message, sentAtFormat: sentAtFormat, expiryNow: expiryNow, style: metaStyle),
                ),
              ],
            ),
          ),
        );
        if (status != DecryptStatus.legacyUnauthenticated) return bubble;
        return Column(
          crossAxisAlignment: message.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            bubble,
            Padding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.sm, VeilSpace.xxs, VeilSpace.sm, 0),
              child: Text(
                l10n.chatLegacySenderLine,
                style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ),
          ],
        );
      },
    );

    final retry = onRetryMessage;
    return Semantics(
      label: messageBubbleSemanticsLabel(l10n, message),
      onTapHint: failed && retry != null ? l10n.chatRetrySend : null,
      child: Align(
        alignment: message.isMine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: failed && retry != null
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  VeilHaptics.light();
                  retry();
                },
                child: content,
              )
            : content,
      ),
    );
  }
}

/// The meta at the end of a bubble: the time, then on the user's own
/// messages how far it got (a tick when sent, two when delivered, two and
/// the word "Read" once read), then the time left on a disappearing one.
/// The words "Sent" and "Delivered" are not written: a screen reader hears
/// them from messageBubbleSemanticsLabel.
class _Meta extends StatelessWidget {
  const _Meta({required this.message, required this.sentAtFormat, required this.expiryNow, required this.style});

  final ChatMessage message;
  final DateFormat sentAtFormat;
  final DateTime Function() expiryNow;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = style?.color;
    final state = message.deliveryState;
    final IconData? tick = !message.isMine
        ? null
        : switch (state) {
            MessageDeliveryState.pending => Icons.schedule,
            MessageDeliveryState.uploading => Icons.upload,
            MessageDeliveryState.failed => null,
            MessageDeliveryState.sent => Icons.done,
            MessageDeliveryState.delivered || MessageDeliveryState.read => Icons.done_all,
          };
    final items = <Widget>[
      Text(sentAtFormat.format(message.sentAt), style: style),
      if (tick != null) Icon(tick, size: 16, color: color),
      if (message.isMine && state == MessageDeliveryState.read)
        Text(l10n.chatDeliveryRead, style: style?.copyWith(fontWeight: FontWeight.w600)),
      if (message.expiresAt != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: VeilIconSize.xs, color: color),
            const SizedBox(width: 2),
            Flexible(child: MessageExpiryLabel(expiresAt: message.expiresAt!, now: expiryNow, style: style)),
          ],
        ),
    ];
    // One line, wrapping only when the bubble cannot be that wide. The gap
    // is padding on each item rather than the Wrap's spacing: the bubble
    // takes the meta's intrinsic width, and a Wrap leaves its spacing out
    // of that, so a short message ("ok") would wrap its own meta.
    return Wrap(
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (index, item) in items.indexed)
          index == 0
              ? item
              : Padding(padding: const EdgeInsetsDirectional.only(start: VeilSpace.xxs), child: item),
      ],
    );
  }
}
