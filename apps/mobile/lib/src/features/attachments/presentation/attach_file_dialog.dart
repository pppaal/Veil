import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../chat/presentation/chat_room_labels.dart';
import '../domain/attachment_rules.dart';

/// Asks before a picked file goes: 'Send "lease.pdf" to Sam?', its type
/// and size, and for a photo or a video picked as a file the line that it
/// keeps any location saved in it (D13), a warning that protects the user.
/// True when the user chose Send.
Future<bool> confirmSendFile(
  BuildContext context, {
  required String name,
  required String chat,
  required int sizeBytes,
  required bool keepsMetadata,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      final theme = Theme.of(dialogContext);
      final palette = dialogContext.veilPalette;
      return AlertDialog(
        // The name and the chat's title are drawn as their owners wrote
        // them; a long name keeps its real extension in sight, and the
        // chat's name wraps as one ("Sam Rivera", never "Sam / Rivera").
        title: Text(l10n.chatSendFileTitle(shortFileName(name), chat.replaceAll(' ', '\u00A0'))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.chatAttachmentTypeSize(fileTypeLabel(name) ?? l10n.chatAttachmentKindFile, formatFileSize(sizeBytes)),
              style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
            if (keepsMetadata) ...[
              const SizedBox(height: VeilSpace.sm),
              Text(l10n.chatSendFileKeepsMetadata, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.chatCancelAction),
          ),
          TextButton(
            key: const ValueKey('attach-file-send'),
            onPressed: () {
              VeilHaptics.light();
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(l10n.chatSendAction),
          ),
        ],
      );
    },
  );
  return sent ?? false;
}

/// [name] shortened in the middle when it is long, so the dialog's title
/// keeps its start and its real extension: "Lease agreement…final.pdf".
String shortFileName(String name, {int maxChars = 48}) {
  final chars = name.runes.toList();
  if (chars.length <= maxChars) return name;
  final extension = fileTypeLabel(name) == null ? '' : '.${name.substring(name.lastIndexOf('.') + 1)}';
  final tailLength = (maxChars ~/ 3).clamp(extension.length, maxChars - 1);
  final head = String.fromCharCodes(chars.take(maxChars - tailLength - 1)).trimRight();
  final tail = String.fromCharCodes(chars.skip(chars.length - tailLength)).trimLeft();
  return '$head\u2026$tail';
}
