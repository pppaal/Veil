import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'device_transfer_code.dart';
import 'device_transfer_step.dart';
import 'step_row.dart';

/// What the screen has to say about the step in hand: that the last action
/// went through, or why it did not.
class TransferNotice {
  const TransferNotice(this.message, {this.isError = false, this.step});

  final String message;
  final bool isError;

  /// The step the notice belongs to (1 to 3); the step in hand when null.
  final int? step;
}

/// The new device's half of a transfer, as three steps: paste the transfer
/// code, register this device, and finish once the old device approved.
/// Under the steps are only the controls of the step in hand, so the
/// control to use next is the first one after them.
///
/// A claim that ran out goes back to the first step. Its transfer session
/// ran out with it (they share one window), so nothing can be registered or
/// finished on the code this device holds: the first step says so and takes
/// the new code, and the other two wait for it.
class TransferNewDevicePanel extends StatelessWidget {
  const TransferNewDevicePanel({
    super.key,
    required this.codeController,
    required this.deviceNameController,
    required this.hasCode,
    required this.editingCode,
    required this.isClaiming,
    required this.isCompleting,
    required this.claimId,
    required this.claimFingerprint,
    required this.claimExpiresAt,
    required this.claimExpired,
    required this.notice,
    required this.onUseCode,
    required this.onEditCode,
    required this.onKeepCode,
    required this.onClaim,
    required this.onComplete,
    required this.now,
    required this.stepsFooter,
  });

  final TextEditingController codeController;
  final TextEditingController deviceNameController;

  /// Whether a transfer code was read.
  final bool hasCode;

  /// Whether the user reopened the first step to paste another code.
  final bool editingCode;
  final bool isClaiming;
  final bool isCompleting;
  final String? claimId;
  final String? claimFingerprint;

  /// When the claim's window closes; null when the window no longer decides
  /// (the relay may have committed the transfer).
  final DateTime? claimExpiresAt;
  final bool claimExpired;
  final TransferNotice? notice;
  final VoidCallback onUseCode;
  final VoidCallback onEditCode;

  /// Closes the reopened first step again, keeping the code that was read.
  final VoidCallback onKeepCode;
  final Future<void> Function() onClaim;
  final Future<void> Function() onComplete;
  final DateTime now;

  /// Said once under the steps: what a missing old phone means.
  final String stepsFooter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final claimLive = claimId != null && !claimExpired;
    // The code this device holds went with the claim made on it.
    final expired = claimId != null && claimExpired;
    final codeRead = hasCode && !expired;
    final pasting = !codeRead || editingCode;
    // Where the notice goes: under the button of its own step, or else of
    // the one in hand. The field and the button stay where they were.
    final noticeStep = notice?.step ?? (claimLive ? 3 : (codeRead ? 2 : 1));
    List<Widget> noticeFor(int step) => [
          if (notice != null && noticeStep == step)
            TransferStepResult(
              message: veilErrorText(l10n, notice!.message),
              tone: notice!.isError ? VeilTone.danger : VeilTone.good,
            ),
        ];
    final muted = theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VeilGroup(
          inset: StepRow.groupInset,
          footer: stepsFooter,
          children: [
            StepRow(
              number: 1,
              title: l10n.deviceTransferNewCodeTitle,
              state: pasting ? StepRowState.current : StepRowState.done,
              body: expired
                  ? l10n.deviceTransferNewCodeExpiredBody
                  : pasting
                      ? l10n.deviceTransferNewCodeBody
                      : null,
              status: expired ? l10n.deviceTransferStatusExpired : null,
              statusTone: VeilTone.warn,
              // A finished step can be opened again to paste another code.
              trailing: pasting ? null : TextButton(onPressed: onEditCode, child: Text(l10n.deviceTransferNewCodeChange)),
            ),
            StepRow(
              number: 2,
              title: l10n.deviceTransferNewRegisterTitle,
              state: !codeRead
                  ? StepRowState.upcoming
                  : claimLive
                      ? StepRowState.done
                      : StepRowState.current,
              // A step whose turn has not come is its title: the line
              // about it comes with its controls.
              body: codeRead && !claimLive ? l10n.deviceTransferNewDeviceCaption : null,
            ),
            StepRow(
              number: 3,
              title: l10n.deviceTransferNewCompleteTitle,
              state: claimLive ? StepRowState.current : StepRowState.upcoming,
              body: claimLive ? l10n.deviceTransferNewCompleteBody : null,
            ),
          ],
        ),
        // The controls of the step in hand, first on the screen after the
        // steps: the code to paste, the phone's name, or the claim's code
        // and Finish.
        if (pasting) ...[
          VeilGroup(
            children: [
              VeilRow.field(
                field: TextField(
                  controller: codeController,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(hintText: l10n.deviceTransferPayloadInputLabel),
                ),
              ),
            ],
          ),
          TransferControls(
            children: [
              VeilButton(
                tone: codeRead ? VeilButtonTone.secondary : VeilButtonTone.primary,
                onPressed: onUseCode,
                label: l10n.deviceTransferImportPayload,
              ),
              // A step reopened over a code that still holds can be closed
              // again, keeping that code.
              if (codeRead) VeilButton(tone: VeilButtonTone.ghost, onPressed: onKeepCode, label: l10n.commonCancel),
              ...noticeFor(1),
            ],
          ),
        ],
        if (codeRead && !claimLive) ...[
          if (pasting) const SizedBox(height: VeilSpace.md),
          VeilGroup(
            children: [
              VeilRow.field(
                title: l10n.deviceTransferDeviceNameLabel,
                field: TextField(controller: deviceNameController, textInputAction: TextInputAction.done),
              ),
            ],
          ),
          TransferControls(
            children: [
              VeilButton(
                onPressed: isClaiming ? null : onClaim,
                label: isClaiming ? l10n.deviceTransferRegisteringClaim : l10n.deviceTransferRegisterNewDevice,
              ),
              ...noticeFor(2),
            ],
          ),
        ],
        // Only a claim that can still be approved shows its code and the
        // button that finishes it: what the user reads off this screen
        // first, with the key it stands for and how long it holds, then
        // what finishing leads to, then the button.
        if (claimLive) ...[
          VeilGroup(
            footer: l10n.deviceTransferNewCompleteNote,
            children: [
              VeilRow.field(
                field: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(l10n.deviceTransferClaimCode(claimId!), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        l10n.deviceTransferClaimFingerprint(claimFingerprint ?? l10n.deviceTransferFingerprintUnavailable),
                        style: muted,
                      ),
                      if (claimExpiresAt != null)
                        Text(l10n.deviceTransferExpires(formatTransferExpiry(claimExpiresAt!, now, l10n)), style: muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
          TransferControls(
            children: [
              VeilButton(
                onPressed: isCompleting ? null : onComplete,
                label: isCompleting ? l10n.deviceTransferCompleting : l10n.deviceTransferCompleteOnDevice,
              ),
              ...noticeFor(3),
            ],
          ),
        ],
      ],
    );
  }
}
