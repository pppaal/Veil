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

/// Reports [target]: a sheet with the reasons, the option to block them
/// too where a block does something, and one line saying what the report
/// holds. The report goes once the sheet is closed with Report; a toast
/// says how that went, with a retry if it did not.
Future<void> showReportSheet(BuildContext context, ReportTarget target) async {
  VeilHaptics.selection();
  final feedback = SafetyFeedback.of(context);
  final offerBlock = target.offerBlock && !feedback.read(blockedAccountsProvider).isBlocked(target.userId);
  final choice = await showModalBottomSheet<_ReportChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(target: target, offerBlock: offerBlock),
  );
  if (choice == null) return;
  await _fileReport(feedback, target, choice);
}

Future<void> _fileReport(SafetyFeedback feedback, ReportTarget target, _ReportChoice choice) async {
  final l10n = feedback.l10n;
  final sent = await feedback.read(abuseReportsProvider).file(target, choice.reason);
  if (!sent) {
    feedback.say(l10n.reportFailed, tone: VeilTone.warn, retry: () => _fileReport(feedback, target, choice));
    return;
  }
  if (!choice.alsoBlock) {
    feedback.say(l10n.reportSent, tone: VeilTone.good);
    return;
  }
  final blocked = await feedback.read(blockedAccountsProvider).block(target.userId, handle: target.handle);
  if (blocked) {
    feedback.say(l10n.reportSentAndBlocked(target.handle), tone: VeilTone.good);
  } else {
    feedback.say(
      l10n.reportSentBlockFailed(target.handle),
      tone: VeilTone.warn,
      retry: () => blockAccount(feedback, userId: target.userId, handle: target.handle, announce: true),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.target, required this.offerBlock});

  final ReportTarget target;
  final bool offerBlock;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  bool _alsoBlock = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final target = widget.target;
    // What fileAbuseReport sends from here, and nothing more.
    final footer = target.messageId != null
        ? l10n.reportFooterMessage
        : target.conversationId != null
            ? l10n.reportFooterChat
            : l10n.reportFooterAccount;
    final reason = _reason;

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
              footer: widget.offerBlock ? null : footer,
              children: [
                for (final option in ReportReason.values)
                  Semantics(
                    selected: option == reason,
                    child: VeilRow(
                      key: ValueKey('report-reason-${option.wire}'),
                      title: reportReasonLabel(l10n, option),
                      // The chosen reason is ticked; the others keep its room.
                      trailing: option == reason
                          ? Icon(Icons.check, size: 20, color: palette.text)
                          : const SizedBox(width: 20),
                      onTap: () => setState(() => _reason = option),
                    ),
                  ),
              ],
            ),
            if (widget.offerBlock) ...[
              const SizedBox(height: VeilSpace.xs),
              VeilGroup(
                footer: footer,
                children: [
                  VeilRow(
                    key: const ValueKey('report-also-block'),
                    title: l10n.reportAlsoBlock(target.handle),
                    switchValue: _alsoBlock,
                    onSwitch: (value) => setState(() => _alsoBlock = value),
                  ),
                ],
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
              child: VeilButton(
                label: l10n.reportAction,
                onPressed: reason == null
                    ? null
                    : () => Navigator.of(context).pop<_ReportChoice>(
                          (reason: reason, alsoBlock: widget.offerBlock && _alsoBlock),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
