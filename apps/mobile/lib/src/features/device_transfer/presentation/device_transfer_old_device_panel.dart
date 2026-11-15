import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/device_transfer_controller.dart';
import 'device_transfer_code.dart';
import 'device_transfer_labels.dart';
import 'device_transfer_step.dart';
import 'step_row.dart';

/// The old device's half of a transfer, as three steps: issue a transfer
/// code, give it to the new device, approve the claim the new device then
/// shows. Under the steps are the controls of the step in hand: before a
/// code is issued the button that issues one; once one is, the code with
/// its copy button and the field for the new phone's code with Approve.
class TransferOldDevicePanel extends StatelessWidget {
  const TransferOldDevicePanel({
    super.key,
    required this.isAuthenticated,
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
    required this.onClear,
    required this.now,
    required this.stepsFooter,
  });

  final bool isAuthenticated;
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
  final VoidCallback onClear;
  final DateTime now;

  /// Said once under the steps: what a missing old phone means.
  final String stepsFooter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    if (!isAuthenticated) {
      return Padding(
        padding: const EdgeInsets.only(top: VeilSpace.md),
        child: VeilEmptyState(
          title: l10n.deviceTransferOldRequiredTitle,
          body: l10n.deviceTransferOldRequiredBody,
          icon: Icons.phonelink_lock_outlined,
        ),
      );
    }

    // A session that ran out is issued again from the first step.
    final live = transferSessionId != null && !transferExpired;
    final statusLabel = transferStatusLabel(l10n, status);
    final aboutIssuing = status is TransferNeedsApi || status is TransferTokenReady;
    // A failure is one line by the control that was used: issuing fails
    // before a session is open, approving after.
    final failure = errorMessage == null
        ? null
        : TransferStepResult(message: veilErrorText(l10n, errorMessage!), tone: VeilTone.danger);
    final approved = live && status is TransferClaimApproved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One step is in hand at a time: handing the code over until the
        // new phone's code is typed in, approving it from then on. An
        // approval finishes this phone's part.
        ListenableBuilder(
          listenable: claimIdController,
          builder: (context, _) {
            final approving = live && (approved || claimIdController.text.trim().isNotEmpty);
            return VeilGroup(
              inset: StepRow.groupInset,
              footer: stepsFooter,
              children: [
                StepRow(
                  number: 1,
                  title: l10n.deviceTransferOldIssueTitle,
                  state: live ? StepRowState.done : StepRowState.current,
                  body: transferExpired
                      ? l10n.deviceTransferOldIssueExpiredBody
                      : aboutIssuing
                          ? statusLabel
                          : live
                              ? null
                              : l10n.deviceTransferOldIssueBody,
                  status: transferExpired ? l10n.deviceTransferStatusExpired : null,
                  statusTone: VeilTone.warn,
                ),
                StepRow(
                  number: 2,
                  title: l10n.deviceTransferOldHandTitle,
                  state: !live
                      ? StepRowState.upcoming
                      : approving
                          ? StepRowState.done
                          : StepRowState.current,
                  // A step whose turn has not come is its title: the line
                  // about it comes with its controls.
                  body: live
                      ? l10n.deviceTransferStep1BodyExpires(formatTransferExpiry(transferExpiresAt!, now, l10n))
                      : null,
                ),
                StepRow(
                  number: 3,
                  title: l10n.deviceTransferOldApproveTitle,
                  state: approved
                      ? StepRowState.done
                      : approving
                          ? StepRowState.current
                          : StepRowState.upcoming,
                ),
              ],
            );
          },
        ),
        if (!live)
          TransferControls(
            children: [
              if (failure != null) failure,
              VeilButton(
                // A build with no server answers the same way every time.
                onPressed: isBusy || status is TransferNeedsApi ? null : onIssue,
                label: isBusy ? l10n.deviceTransferIssuingToken : l10n.deviceTransferIssueToken,
              ),
            ],
          )
        else ...[
          // The code the new phone takes, with the button that copies it.
          VeilGroup(
            children: [
              VeilRow.field(
                field: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: SelectableText(
                    transferCode ?? '',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.35, color: palette.text),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: VeilIconSize.md),
                  tooltip: l10n.deviceTransferCopyPayload,
                  onPressed: onCopyCode,
                ),
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          // The code the new phone shows; which code to approve and what
          // the move leads to are said under it, above the button.
          VeilGroup(
            footer: l10n.deviceTransferApproveFooter,
            children: [
              VeilRow.field(
                field: TextField(
                  controller: claimIdController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(hintText: l10n.deviceTransferClaimInputLabel),
                ),
              ),
            ],
          ),
          TransferControls(
            children: [
              VeilButton(onPressed: isBusy ? null : onApprove, label: l10n.deviceTransferApproveClaim),
              VeilButton(
                onPressed: isBusy ? null : onClear,
                tone: VeilButtonTone.ghost,
                label: l10n.deviceTransferClear,
              ),
            ],
          ),
        ],
        // What the approval came to, under the button that asked for it:
        // why it failed, or else what the server answered.
        if (live && failure != null)
          TransferControls(children: [failure])
        else if (!aboutIssuing && statusLabel != null)
          TransferControls(
            children: [
              TransferStepResult(
                message: statusLabel,
                tone: status is TransferClaimApproved ? VeilTone.good : VeilTone.info,
              ),
            ],
          ),
      ],
    );
  }
}
