import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'chat_room_labels.dart';
import 'message_file_card.dart' show MiddleEllipsisText;
import 'message_photo.dart' show incomingInset;

/// An attachment this version cannot open, from its message's authenticated
/// payload (a voice message, an older pointer, or bytes that are not the
/// photo its kind says), drawn as a file card is (MessageFileCard): a 40 dp
/// circle with its kind's glyph, its [name] on one line cut in the middle,
/// "PDF · 2.3 MB" ("Voice message · 56 KB" for a [voice] message) under it,
/// and the muted line that this version cannot open it. No tap does
/// anything.
///
/// On the brand fill of the user's own bubble ([onBrand]) the circle is
/// white at 20% and the text white, as the file card's are.
class MessageAttachmentCard extends StatelessWidget {
  const MessageAttachmentCard({
    super.key,
    required this.attachment,
    this.name = '',
    this.onBrand = false,
    this.voice = false,
  });

  final AttachmentReference attachment;

  /// The file's name, as the message's text gives it; empty when it has
  /// none.
  final String name;

  /// Whether it sits on the brand fill of the user's own bubble.
  final bool onBrand;

  /// Whether the message is a voice message (its kind), which the card
  /// names so, with a microphone, whatever type the recording's file is.
  final bool voice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final muted = theme.textTheme.bodySmall?.copyWith(color: onBrand ? palette.outgoingMeta : palette.textMuted);
    final title = theme.textTheme.titleSmall?.copyWith(color: onBrand ? Colors.white : palette.text);
    final typeSize = l10n.chatAttachmentTypeSize(
      voice ? l10n.chatAttachmentKindVoice : attachmentTypeLabel(l10n, attachment.contentType),
      formatFileSize(attachment.sizeBytes),
    );
    // The file card's 40 dp circle in its 44 dp slot.
    final circle = SizedBox.square(
      dimension: 44,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: onBrand ? Colors.white.withValues(alpha: 0.2) : incomingInset(context),
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 40,
            child: Icon(
              voice ? Icons.mic_none_outlined : attachmentIcon(attachment.contentType),
              size: VeilIconSize.md,
              color: onBrand ? Colors.white : palette.textMuted,
            ),
          ),
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          circle,
          const SizedBox(width: VeilSpace.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name.isNotEmpty) ...[
                  MiddleEllipsisText(name, style: title),
                  Text(typeSize, style: muted, maxLines: 1),
                ] else
                  Text(typeSize, style: title, maxLines: 1),
                Text(l10n.chatAttachmentCannotOpen, style: muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
