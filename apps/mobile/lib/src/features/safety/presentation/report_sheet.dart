import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/abuse_reports.dart';
import '../data/safety_providers.dart';
import 'block_actions.dart';
import 'safety_feedback.dart';

/// What the user chose in the report sheet.
typedef _ReportChoice = ({ReportReason reason, bool alsoBlock});

String reportReasonLabel(AppLocalizations l10n, ReportReason reason) => switch (reason) {
      ReportReason.spam => l10n.reportReasonSpam,
      ReportReason.harassment => l10n.reportReasonHarassment,
      ReportReason.impersonation => l10n.reportReasonImpersonation,
      ReportReason.csam => l10n.reportReasonCsam,
      ReportReason.violence => l10n.reportReasonViolence,
      ReportReason.scam => l10n.reportReasonScam,
      ReportReason.other => l10n.reportReasonOther,
    };

/// The reasons in the order the sheet lists them: the common ones first.
const reportReasonOrder = [
  ReportReason.spam,
  ReportReason.scam,
  ReportReason.harassment,
  ReportReason.impersonation,
  ReportReason.violence,
  ReportReason.csam,
  ReportReason.other,
];

/// Reports [target]: a sheet of reasons, where a tap closes it and asks in
/// a small dialog what the report holds, with "Also block" ticked where a
/// block does something (Telegram's reasons, then WhatsApp's and Threema's
/// confirm). The report goes once the dialog is closed with Report; a toast
/// says how that went, with a retry if it did not.
Future<void> showReportSheet(BuildContext context, ReportTarget target) async {
  VeilHaptics.selection();
  final feedback = SafetyFeedback.of(context);
  final offerBlock = target.offerBlock && !feedback.read(blockedAccountsProvider).isBlocked(target.userId);
  final reason = await showModalBottomSheet<ReportReason>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(target: target),
  );
  if (reason == null || !context.mounted) return;
  final alsoBlock = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _ReportDialog(target: target, offerBlock: offerBlock),
  );
  if (alsoBlock == null) return;
  await _fileReport(feedback, target, (reason: reason, alsoBlock: offerBlock && alsoBlock));
}

Future<void> _fileReport(SafetyFeedback feedback, ReportTarget target, _ReportChoice choice) async {
  final l10n = feedback.l10n;
  final sent = await feedback.read(abuseReportsProvider).file(target, choice.reason);
  if (!sent) {
    feedback.say(l10n.reportFailed, retry: () => _fileReport(feedback, target, choice));
    return;
  }
  if (!choice.alsoBlock) {
    feedback.say(l10n.reportSent);
    return;
  }
  final blocked = await feedback.read(blockedAccountsProvider).block(target.userId, handle: target.handle);
  if (blocked) {
    feedback.say(l10n.reportSentAndBlocked(target.handle));
  } else {
    feedback.say(
      l10n.reportSentBlockFailed(target.handle),
      retry: () => blockAccount(feedback, userId: target.userId, handle: target.handle, announce: true),
    );
  }
}

/// The reasons, one row each; a tap chooses and closes the sheet.
class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.target});

  final ReportTarget target;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: VeilSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.md, 0, VeilSpace.md, VeilSpace.xs),
              // A handle is its owner's word: drawn as typed.
              child: Text(l10n.reportTitle(target.handle), style: theme.textTheme.titleLarge),
            ),
            VeilGroup(
              children: [
                for (final option in reportReasonOrder)
                  VeilRow(
                    key: ValueKey('report-reason-${option.wire}'),
                    title: reportReasonLabel(l10n, option),
                    trailing: const SizedBox.shrink(),
                    onTap: () => Navigator.of(context).pop<ReportReason>(option),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Report @sam?": what the report holds and that they are not told, and
/// "Also block @sam", ticked, where a block does something. Pops with
/// whether to block too; null on Cancel.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.target, required this.offerBlock});

  final ReportTarget target;
  final bool offerBlock;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  bool _alsoBlock = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final target = widget.target;
    // What fileAbuseReport sends from here, and nothing more, plus the
    // reporter: the server records whose session filed it.
    final body = target.messageId != null
        ? l10n.reportFooterMessage
        : target.conversationId != null
            ? l10n.reportFooterChat
            : l10n.reportFooterAccount;
    return AlertDialog(
      title: Text(l10n.reportConfirmTitle(target.handle)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body),
          if (widget.offerBlock) ...[
            const SizedBox(height: VeilSpace.xs),
            CheckboxListTile(
              key: const ValueKey('report-also-block'),
              value: _alsoBlock,
              onChanged: (value) => setState(() => _alsoBlock = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.reportAlsoBlock(target.handle), style: theme.textTheme.bodyMedium),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
        TextButton(
          key: const ValueKey('report-confirm'),
          onPressed: () => Navigator.of(context).pop<bool>(_alsoBlock),
          child: Text(l10n.reportAction),
        ),
      ],
    );
  }
}
