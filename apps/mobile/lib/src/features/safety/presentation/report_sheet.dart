import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/abuse_reports.dart';
import '../data/safety_providers.dart';
import 'block_actions.dart';

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
/// holds. The report goes once the sheet is closed with Report; the screen
/// behind it says how that went, with a retry if it did not.
Future<void> showReportSheet(BuildContext context, WidgetRef ref, ReportTarget target) async {
  VeilHaptics.selection();
  final offerBlock = target.offerBlock && !ref.read(blockedAccountsProvider).isBlocked(target.userId);
  final choice = await showModalBottomSheet<_ReportChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(target: target, offerBlock: offerBlock),
  );
  if (choice == null || !context.mounted) return;
  await _fileReport(context, ref, target, choice);
}

Future<void> _fileReport(BuildContext context, WidgetRef ref, ReportTarget target, _ReportChoice choice) async {
  final l10n = AppLocalizations.of(context);
  final sent = await ref.read(abuseReportsProvider).file(target, choice.reason);
  if (!context.mounted) return;
  if (!sent) {
    showVeilToast(
      context,
      l10n.reportFailed,
      tone: VeilTone.warn,
      actionLabel: l10n.commonRetry,
      onAction: () {
        if (context.mounted) _fileReport(context, ref, target, choice);
      },
    );
    return;
  }
  if (!choice.alsoBlock) {
    showVeilToast(context, l10n.reportSent, tone: VeilTone.good);
    return;
  }
  final blocked = await ref.read(blockedAccountsProvider).block(target.userId, handle: target.handle);
  if (!context.mounted) return;
  if (blocked) {
    showVeilToast(context, l10n.reportSentAndBlocked(target.handle), tone: VeilTone.good);
  } else {
    showVeilToast(
      context,
      l10n.reportSentBlockFailed(target.handle),
      tone: VeilTone.warn,
      actionLabel: l10n.commonRetry,
      onAction: () {
        if (context.mounted) blockAccount(context, ref, userId: target.userId, handle: target.handle, announce: true);
      },
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
            if (widget.offerBlock)
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
