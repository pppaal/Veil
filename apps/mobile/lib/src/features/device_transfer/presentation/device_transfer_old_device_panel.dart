import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../chat/presentation/message_time.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/device_transfer_controller.dart';
import 'device_transfer_code.dart';
import 'device_transfer_labels.dart';
import 'device_transfer_step.dart';

/// The old phone's half of a move, as Signal's transfer instructions: a
/// start screen with three numbered lines and "Get code"; once a code is
/// issued, the code with "Copy code" and how long it holds, then the field
/// for the new phone's code and "Approve", which asks in a dialog first.
class TransferOldDevicePanel extends StatelessWidget {
  const TransferOldDevicePanel({
    super.key,
    required this.isBusy,
    required this.transferSessionId,
    required this.transferCode,
    required this.status,
    required this.transferExpiresAt,
    required this.transferExpired,
    required this.errorMessage,
    required this.claimIdController,
    required this.onIssue,
    required this.onApprove,
    required this.onCopyCode,
    required this.now,
  });

  final bool isBusy;
  final String? transferSessionId;

  /// What the new device pastes; null until a session is open.
  final String? transferCode;

  /// What the last step on this device came to.
  final TransferStatus? status;
  final DateTime? transferExpiresAt;
  final bool transferExpired;
  final String? errorMessage;
  final TextEditingController claimIdController;
  final VoidCallback onIssue;
  final VoidCallback onApprove;
  final VoidCallback? onCopyCode;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    // A session that ran out is issued again from the start screen.
    final live = transferSessionId != null && !transferExpired;
    final statusLabel = transferStatusLabel(l10n, status);
    // A failure is one line by the button that was used.
    final failure = errorMessage == null
        ? null
        : TransferStepResult(message: veilErrorText(l10n, errorMessage!), tone: VeilTone.danger);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted);

    if (!live) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.xs, VeilSpace.md, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Plain numbered lines, not steps with a state.
            for (final line in [l10n.deviceTransferOldStep1, l10n.deviceTransferOldStep2, l10n.deviceTransferOldStep3])
              Padding(
                padding: const EdgeInsets.only(bottom: VeilSpace.sm),
                child: Text(line, style: theme.textTheme.bodyLarge),
              ),
            const SizedBox(height: VeilSpace.sm),
            if (transferExpired) ...[
              TransferStepResult(message: l10n.deviceTransferOldIssueExpiredBody, tone: VeilTone.warn),
              const SizedBox(height: VeilSpace.sm),
            ],
            if (status is TransferNeedsApi) ...[
              TransferStepResult(message: statusLabel!),
              const SizedBox(height: VeilSpace.sm),
            ],
            if (failure != null) ...[failure, const SizedBox(height: VeilSpace.sm)],
            VeilButton(
              // A build with no server answers the same way every time.
              onPressed: isBusy || status is TransferNeedsApi ? null : onIssue,
              label: isBusy ? l10n.deviceTransferIssuingToken : l10n.deviceTransferIssueToken,
            ),
          ],
        ),
      );
    }

    final approved = status is TransferClaimApproved;
    return Padding(
      padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.xs, VeilSpace.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.deviceTransferOldHandTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: VeilSpace.sm),
          // The code the new phone takes, whole, in the body's own type:
          // the session on one line and the token on the next, each a UUID
          // that fits a phone's width, so neither breaks where it is read
          // off and typed in; a long press selects it. "Copy code" copies
          // all of it. It leaves out the prefix the copied code starts
          // with, which the new phone takes with or without, and the new
          // phone reads it with the line break or spaces typed in.
          SelectableText(
            transferCodeForDisplay(transferCode ?? ''),
            key: const ValueKey('transfer-code'),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilButton(
            tone: VeilButtonTone.secondary,
            onPressed: onCopyCode,
            label: l10n.deviceTransferCopyPayload,
          ),
          const SizedBox(height: VeilSpace.xs),
          Text(l10n.deviceTransferExpires(formatTransferExpiry(transferExpiresAt!, now, l10n, timeFormat: MessageTimeFormat.of(context))), style: muted),
          const SizedBox(height: VeilSpace.lg),
          TextField(
            controller: claimIdController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l10n.deviceTransferClaimInputLabel),
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilButton(
            onPressed: isBusy || approved ? null : onApprove,
            label: l10n.deviceTransferApproveClaim,
          ),
          // What the approval came to, under the button that asked for it:
          // why it failed, or else what the server answered.
          if (failure != null) ...[
            const SizedBox(height: VeilSpace.sm),
            failure,
          ] else if (statusLabel != null) ...[
            const SizedBox(height: VeilSpace.sm),
            TransferStepResult(message: statusLabel, tone: approved ? VeilTone.good : VeilTone.info),
          ],
        ],
      ),
    );
  }
}

/// Asks before the old phone approves the new one: the key fingerprint the
/// new phone shows, and that this phone is then signed out and the
/// messages stay behind. True when the user chose to move the account.
Future<bool> confirmTransferApproval(BuildContext context, {required String fingerprint}) async {
  final l10n = AppLocalizations.of(context);
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(l10n.deviceTransferApproveTitle),
      content: Text(l10n.deviceTransferApproveBody(fingerprint)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
        TextButton(
          key: const ValueKey('transfer-approve-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.deviceTransferApproveAction),
        ),
      ],
    ),
  );
  return approved ?? false;
}
