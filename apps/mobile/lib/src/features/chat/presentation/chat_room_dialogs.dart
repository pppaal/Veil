import 'package:flutter/material.dart';

import '../../../core/security/sensitive_text_redactor.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../reactions/presentation/reaction_picker_widget.dart';

/// Asks before a 1:1 is bound to another account listed under the user's
/// own handle, which no honest relay lists. True only when confirmed.
Future<bool> confirmOwnHandleHold(BuildContext context, String handle) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.chatAccountHoldOwnConfirmTitle(handle)),
      content: Text(l10n.chatAccountHoldOwnConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.chatAccountHoldAcknowledge),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Tells the user a download ticket was issued, showing only a redacted
/// summary of its [url], never the URL itself.
Future<void> showAttachmentTicketDialog(BuildContext context, String url) async {
  final ticketSummary = summarizeSensitiveUrl(url);
  final l10n = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.chatAttachmentTicketTitle),
      content: Text(l10n.chatAttachmentTicketBody(ticketSummary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
}

/// The reaction picker in a sheet, which closes on a pick and hands the
/// picked emoji to [onSelected].
Future<void> showReactionPickerSheet(
  BuildContext context, {
  required ValueChanged<String> onSelected,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(VeilSpace.md),
          child: ReactionPickerWidget(
            onReactionSelected: (emoji) {
              Navigator.of(sheetContext).pop();
              onSelected(emoji);
            },
          ),
        ),
      );
    },
  );
}
