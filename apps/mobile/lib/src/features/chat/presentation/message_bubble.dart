import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../attachments/domain/attachment_rules.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/attachment_media_service.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import '../../conversations/presentation/conversation_list_logic.dart';
import 'chat_room_labels.dart';
import 'decrypt_status_view.dart';
import 'message_attachment_views.dart';
import 'message_expiration.dart';
import 'message_file_card.dart';
import 'message_photo.dart';
import 'message_time.dart';
import 'message_read_glyph.dart';

/// One message as a bubble on its sender's side: who of a group wrote it
/// (the first bubble of a run, in the sender's tint), the decrypted text or
/// the line for a message that did not open, any attachment, and the meta
/// at its end: the time, a status glyph on the user's own messages and a
/// timer glyph on a disappearing one. Words for them are a screen reader's.
/// [reactions] overlap the bubble's foot on the side away from its tail.
///
/// A send that failed keeps its bubble, with a red glyph beside it and
/// "Not sent. Tap to retry." under it, and a tap on it retries. A message
/// from an older version, whose sender is not proven, says so in a line
/// under the bubble.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.conversationId,
    required this.highlighted,
    required this.sentAtFormat,
    required this.decryptFuture,
    required this.onCancelAttachment,
    required this.transferSnapshot,
    required this.expiryNow,
    this.onRetryMessage,
    this.authorName,
    this.senderName,
    this.senderSeed,
    this.position = VeilBubblePosition.single,
    this.reactions,
    this.searchQuery,
    this.heldAccount = false,
  });

  final ChatMessage message;

  /// The conversation the message is in, which its attachment belongs to.
  final String conversationId;
  final bool highlighted;

  /// How the time it was sent is written.
  final MessageTimeFormat sentAtFormat;
  final Future<DecryptedMessage> decryptFuture;
  final VoidCallback? onCancelAttachment;
  final AttachmentTransferSnapshot? transferSnapshot;
  final DateTime Function() expiryNow;
  final VoidCallback? onRetryMessage;

  /// Who wrote the message as the chat names them, on every message of
  /// someone else (a viewer's title says it); null on the user's own.
  final String? authorName;

  /// Who of a group wrote the message, shown above it; null in a 1:1, on
  /// the user's own messages, and under another message of the same run.
  final String? senderName;

  /// What the sender's name tint is drawn from (their handle); the name
  /// itself when null.
  final String? senderSeed;

  /// Where the bubble sits in its run of bubbles from the same sender.
  final VeilBubblePosition position;

  /// The reactions on the message (ReactionChipsRow), if any.
  final Widget? reactions;

  /// A chat search's query, drawn in bold where the text holds it.
  final String? searchQuery;

  /// The chat is held for its handle until the user confirms the account
  /// (see DecryptFailureLine.heldAccount).
  final bool heldAccount;

  /// How far the reactions overlap the bubble's foot.
  static const double reactionOverlap = 6;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final failed = message.hasFailed;
    // The colours VeilBubble fills with: own bubbles are the brand fill,
    // everything else (theirs, a search hit) a grey or raised one.
    final onBrand = message.isMine && !highlighted;
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
        // the envelope carries a bare pointer. The kind the payload names
        // decides photo or file, and only a pointer this version opens is
        // shown as one (D31, D34); any other is the card that says so.
        final attachment = decrypted?.attachment;
        final opened = status == DecryptStatus.ok || status == DecryptStatus.legacyUnauthenticated;
        final opens = opened && attachment != null && AttachmentMediaService.opens(attachment);
        final photo = opens && decrypted!.messageKind == MessageKind.image;
        final file = opens && decrypted!.messageKind == MessageKind.file;
        final query = searchQuery?.trim() ?? '';
        final body = switch (status) {
          null => Text(l10n.chatDecryptingEnvelope, style: bodyStyle?.copyWith(color: metaColor)),
          // An attachment's text is its name, which the card holds.
          DecryptStatus.ok || DecryptStatus.legacyUnauthenticated when attachment != null => null,
          DecryptStatus.ok || DecryptStatus.legacyUnauthenticated when query.isNotEmpty => Text.rich(
              TextSpan(
                children: buildSearchHighlightTextSpans(
                  text: decrypted!.body,
                  query: query,
                  baseStyle: bodyStyle,
                  highlightStyle: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          DecryptStatus.ok || DecryptStatus.legacyUnauthenticated => Text(decrypted!.body, style: bodyStyle),
          _ => DecryptFailureLine(status: status, heldAccount: heldAccount, color: metaColor),
        };
        final meta = _Meta(
          message: message,
          sentAtFormat: sentAtFormat,
          expiryNow: expiryNow,
          style: metaStyle,
          bubbleFill: VeilBubble.fillOf(palette, isMine: message.isMine, highlighted: highlighted),
        );
        Widget padded({required bool asCard}) => VeilBubble(
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
                    if (attachment != null) ...[
                      if (body != null) const SizedBox(height: VeilSpace.xs),
                      if (file && !asCard)
                        MessageFileCard(
                          conversationId: conversationId,
                          message: message,
                          attachment: attachment,
                          name: decrypted.body,
                          authorName: authorName,
                          transferSnapshot: transferSnapshot,
                          onCancelAttachment: onCancelAttachment,
                        )
                      else
                        MessageAttachmentCard(
                          attachment: attachment,
                          // Sanitized as the file card's is (D27): no bidi
                          // override shows as sent.
                          name: sanitizeFileName(decrypted!.body, fallback: ''),
                          onBrand: onBrand,
                          voice: decrypted.messageKind == MessageKind.voice,
                        ),
                    ],
                    const SizedBox(height: VeilSpace.xxs),
                    Align(alignment: AlignmentDirectional.centerEnd, child: meta),
                  ],
                ),
              ),
            );
        final bubble = photo
            ? MessagePhoto(
                conversationId: conversationId,
                message: message,
                attachment: attachment,
                meta: meta,
                unsupported: padded(asCard: true),
                position: position,
                highlighted: highlighted,
                senderName: senderName,
                senderSeed: senderSeed,
                authorName: authorName,
                transferSnapshot: transferSnapshot,
                onCancelAttachment: onCancelAttachment,
              )
            : padded(asCard: false);
        final reactions = this.reactions;
        // The chips' 44 px tap row moves up so the chip drawn in its middle
        // overlaps the bubble by 6, as WhatsApp's do, on the side away from
        // the tail; the whole row still takes the tap.
        final withReactions = reactions == null
            ? bubble
            : Column(
                crossAxisAlignment: message.isMine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  bubble,
                  Transform.translate(
                    offset: const Offset(0, -(44 - 28) / 2 - reactionOverlap),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xs),
                      child: reactions,
                    ),
                  ),
                ],
              );
        if (status != DecryptStatus.legacyUnauthenticated) return withReactions;
        return Column(
          crossAxisAlignment: message.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            withReactions,
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
    final expiresAt = message.expiresAt;
    return Semantics(
      // The words the glyphs stand for: how far it got, when it goes.
      label: [
        messageBubbleSemanticsLabel(l10n, message),
        if (expiresAt != null) formatMessageExpiry(l10n, expiresAt, now: expiryNow()),
      ].join(' '),
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
/// messages how far it got (Signal's glyphs: a clock while it waits, one
/// outlined check circle when sent, two when delivered, two filled once
/// read), then a timer glyph on a disappearing one. No words: a screen
/// reader hears them from the bubble's label.
class _Meta extends StatelessWidget {
  const _Meta({
    required this.message,
    required this.sentAtFormat,
    required this.expiryNow,
    required this.style,
    required this.bubbleFill,
  });

  final ChatMessage message;
  final MessageTimeFormat sentAtFormat;
  final DateTime Function() expiryNow;
  final TextStyle? style;

  /// The bubble's fill, which the read glyph's checks are cut out in.
  final Color bubbleFill;

  @override
  Widget build(BuildContext context) {
    final color = style?.color;
    final state = message.deliveryState;
    final Widget? status = !message.isMine
        ? null
        : switch (state) {
            MessageDeliveryState.pending ||
            MessageDeliveryState.uploading =>
              Icon(Icons.schedule, size: VeilIconSize.xs, color: color),
            MessageDeliveryState.failed => null,
            MessageDeliveryState.sent => Icon(Icons.check_circle_outline, size: VeilIconSize.xs, color: color),
            MessageDeliveryState.delivered => _TwoOutlinedCircles(color: color),
            MessageDeliveryState.read => MessageReadGlyph(color: color ?? Colors.white, cutColor: bubbleFill),
          };
    final items = <Widget>[
      Text(sentAtFormat.timeOfDay(message.sentAt), style: style),
      if (message.expiresAt != null) Icon(Icons.timer_outlined, size: VeilIconSize.xs, color: color),
      if (status != null) status,
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

/// Two outlined check circles, the second overlapping the first: delivered.
class _TwoOutlinedCircles extends StatelessWidget {
  const _TwoOutlinedCircles({required this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: VeilIconSize.xs + 6,
      height: VeilIconSize.xs,
      child: Stack(
        children: [
          Icon(Icons.check_circle_outline, size: VeilIconSize.xs, color: color),
          Positioned(left: 6, child: Icon(Icons.check_circle_outline, size: VeilIconSize.xs, color: color)),
        ],
      ),
    );
  }
}
