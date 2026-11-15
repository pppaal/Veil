import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/device_transfer_controller.dart';
import 'device_transfer_code.dart';
import 'device_transfer_labels.dart';
import 'device_transfer_step.dart';

/// The old device's half of a transfer, as three steps: issue a transfer
/// code, give it to the new device, approve the claim the new device then
/// shows. Before a code is issued only the first step has a control; once
/// one is, the code and the approval take its place at the top.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!isAuthenticated) {
      return VeilEmptyState(
        title: l10n.deviceTransferOldRequiredTitle,
        body: l10n.deviceTransferOldRequiredBody,
        icon: Icons.phonelink_lock_outlined,
      );
    }

    // A session that ran out is issued again from the first step.
    final live = transferSessionId != null && !transferExpired;
    final statusLabel = transferStatusLabel(l10n, status);
    final aboutIssuing = status is TransferNeedsApi || status is TransferTokenReady;
    // A failure is said in the step that was acted on: issuing fails
    // before a session is open, approving after.
    final failure = errorMessage == null
        ? null
        : TransferStepResult(
            title: l10n.deviceTransferFailedTitle,
            message: veilErrorText(l10n, errorMessage!),
            tone: VeilBannerTone.danger,
          );

    return Column(
      children: [
        TransferStep(
          number: 1,
          title: l10n.deviceTransferOldIssueTitle,
          state: live ? TransferStepState.done : TransferStepState.current,
          body: transferExpired
              ? l10n.deviceTransferOldIssueExpiredBody
              : aboutIssuing
                  ? statusLabel
                  : live
                      ? null
                      : l10n.deviceTransferOldIssueBody,
          status: transferExpired ? l10n.deviceTransferStatusExpired : null,
          statusTone: VeilBannerTone.danger,
          children: [
            if (!live) ...[
              if (failure != null) ...[failure, const SizedBox(height: VeilSpace.sm)],
              VeilButton(
                // A build with no relay answers the same way every time.
                onPressed: isBusy || status is TransferNeedsApi ? null : onIssue,
                label: isBusy ? l10n.deviceTransferIssuingToken : l10n.deviceTransferIssueToken,
              ),
            ],
          ],
        ),
        const SizedBox(height: VeilSpace.sm),
        TransferStep(
          number: 2,
          title: l10n.deviceTransferOldHandTitle,
          state: live ? TransferStepState.current : TransferStepState.upcoming,
          body: live
              ? l10n.deviceTransferStep1BodyExpires(formatTransferExpiry(transferExpiresAt!, now, l10n))
              : l10n.deviceTransferOldHandBody,
          children: [
            if (live) ...[
              TransferCodeBox(code: transferCode ?? ''),
              const SizedBox(height: VeilSpace.sm),
              // The copy button takes the width that is left, so its label
              // stays on one line beside the short one.
              Row(
                children: [
                  Expanded(
                    child: VeilButton(
                      onPressed: onCopyCode,
                      tone: VeilButtonTone.secondary,
                      label: l10n.deviceTransferCopyPayload,
                      icon: Icons.copy_rounded,
                    ),
                  ),
                  const SizedBox(width: VeilSpace.xs),
                  VeilButton(
                    onPressed: isBusy ? null : onClear,
                    tone: VeilButtonTone.ghost,
                    label: l10n.deviceTransferClear,
                    expanded: false,
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: VeilSpace.sm),
        TransferStep(
          number: 3,
          title: l10n.deviceTransferOldApproveTitle,
          state: live ? TransferStepState.current : TransferStepState.upcoming,
          body: live ? null : l10n.deviceTransferOldApproveBody,
          children: [
            if (live) ...[
              TextField(
                controller: claimIdController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.deviceTransferClaimInputLabel,
                  hintText: l10n.deviceTransferClaimInputHint,
                ),
              ),
              const SizedBox(height: VeilSpace.sm),
              TransferStepNote(l10n.deviceTransferClaimFieldCaption),
              const SizedBox(height: VeilSpace.sm),
              // What approving leads to, said where it is decided: above
              // the button that decides it.
              VeilInlineBanner(
                dense: true,
                tone: VeilBannerTone.warn,
                message: l10n.deviceTransferCompleteOnNewNote,
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilButton(
                onPressed: isBusy ? null : onApprove,
                label: l10n.deviceTransferApproveClaim,
              ),
            ],
            // What the approval came to, under the button that asked for it:
            // why it failed, or else what the relay answered.
            if (live && failure != null) ...[
              const SizedBox(height: VeilSpace.sm),
              failure,
            ] else if (!aboutIssuing && statusLabel != null) ...[
              if (live) const SizedBox(height: VeilSpace.sm),
              TransferStepResult(
                title: l10n.deviceTransferStatusTitle,
                message: statusLabel,
                tone: status is TransferClaimApproved ? VeilBannerTone.good : VeilBannerTone.info,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
