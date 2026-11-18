import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'chat_room_labels.dart';

/// An attachment this version cannot open, from its message's authenticated
/// payload (a voice message, an older pointer, or bytes that are not the
/// photo its kind says): one tile with its [name], "PDF · 2.3 MB" ("Voice
/// message · 56 KB" for a [voice] message), and the line that this version
/// cannot open it.
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
