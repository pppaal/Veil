import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Where an attachment comes from.
enum AttachSource { photos, file }

/// What the composer's plus offers: Photos (the system photo picker) and
/// File (the system document picker), each a row with its outlined icon.
/// No title and no Cancel row: the handle and a tap outside close it.
/// Completes with the choice, or null when the sheet was closed.
Future<AttachSource?> showAttachSheet(BuildContext context) {
  return showModalBottomSheet<AttachSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      final palette = sheetContext.veilPalette;
      Widget row(AttachSource source, IconData icon, String title) => VeilRow(
            key: ValueKey('attach-${source.name}'),
            leading: Icon(icon, size: 22, color: palette.textMuted),
            title: title,
            trailing: const SizedBox.shrink(),
            onTap: () => Navigator.of(sheetContext).pop(source),
          );
      // As tall as its two rows, no taller.
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VeilGroup(
              inset: 56,
              children: [
                row(AttachSource.photos, Icons.photo_library_outlined, l10n.chatAttachPhotos),
                row(AttachSource.file, Icons.insert_drive_file_outlined, l10n.chatAttachFile),
              ],
            ),
            const SizedBox(height: VeilSpace.xs),
          ],
        ),
      );
    },
  );
}
