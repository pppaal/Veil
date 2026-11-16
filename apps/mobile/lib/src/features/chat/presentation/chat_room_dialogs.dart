import 'package:flutter/material.dart';

import '../../../core/security/sensitive_text_redactor.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
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
/// picked emoji to [onSelected]. With [onReport] (a message someone else
/// wrote) a Report row sits under the reactions. Without [onSelected] (a
/// message that did not open, or a 1:1 with someone blocked, where the
/// server refuses a reaction) the sheet holds the Report row alone.
Future<void> showReactionPickerSheet(
  BuildContext context, {
  ValueChanged<String>? onSelected,
  VoidCallback? onReport,
}) async {
  final l10n = AppLocalizations.of(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: VeilSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onSelected != null)
                Center(
                  heightFactor: 1,
                  child: ReactionPickerWidget(
                    onReactionSelected: (emoji) {
                      Navigator.of(sheetContext).pop();
                      onSelected(emoji);
                    },
                  ),
                ),
              if (onReport != null) ...[
                if (onSelected != null) const SizedBox(height: VeilSpace.xs),
                VeilGroup(
                  children: [
                    VeilRow(
                      key: const ValueKey('message-report'),
                      title: l10n.reportAction,
                      // It opens the report sheet in this one's place.
                      trailing: const SizedBox.shrink(),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onReport();
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
