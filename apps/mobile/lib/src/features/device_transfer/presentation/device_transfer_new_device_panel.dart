import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'device_transfer_code.dart';
import 'device_transfer_step.dart';

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
/// Only the step in hand shows its controls, so the control to use next is
/// the first one on the screen; a finished step shrinks to its title.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final claimLive = claimId != null && !claimExpired;
    // The code this device holds went with the claim made on it.
    final expired = claimId != null && claimExpired;
    final codeRead = hasCode && !expired;
    final pasting = !codeRead || editingCode;
    // Where the notice goes: its own step, or else the one in hand.
    final noticeStep = notice?.step ?? (claimLive ? 3 : (codeRead ? 2 : 1));
    List<Widget> noticeFor(int step) => [
          if (notice != null && noticeStep == step) ...[
            TransferStepResult(
              title: notice!.isError ? l10n.deviceTransferFailedTitle : l10n.deviceTransferStatusTitle,
              message: veilErrorText(l10n, notice!.message),
              tone: notice!.isError ? VeilBannerTone.danger : VeilBannerTone.good,
            ),
            const SizedBox(height: VeilSpace.sm),
          ],
        ];

    return Column(
      children: [
        TransferStep(
          number: 1,
          title: l10n.deviceTransferNewCodeTitle,
          state: pasting ? TransferStepState.current : TransferStepState.done,
          body: expired
              ? l10n.deviceTransferNewCodeExpiredBody
              : pasting
                  ? l10n.deviceTransferNewCodeBody
                  : null,
          status: expired ? l10n.deviceTransferStatusExpired : null,
          statusTone: VeilBannerTone.danger,
          // A step reopened over a code that still holds can be closed
          // again; one that has no usable code stays open.
          trailing: !pasting
              ? TextButton(onPressed: onEditCode, child: Text(l10n.deviceTransferNewCodeChange))
              : codeRead
                  ? TextButton(onPressed: onKeepCode, child: Text(l10n.commonCancel))
                  : null,
          children: [
            if (pasting) ...[
              ...noticeFor(1),
              TextField(
                controller: codeController,
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: l10n.deviceTransferPayloadInputLabel),
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilButton(
                tone: codeRead ? VeilButtonTone.secondary : VeilButtonTone.primary,
                onPressed: onUseCode,
                label: l10n.deviceTransferImportPayload,
              ),
            ],
          ],
        ),
        const SizedBox(height: VeilSpace.sm),
        TransferStep(
          number: 2,
          title: l10n.deviceTransferNewRegisterTitle,
          state: !codeRead
              ? TransferStepState.upcoming
              : claimLive
                  ? TransferStepState.done
                  : TransferStepState.current,
          body: claimLive ? null : l10n.deviceTransferNewDeviceCaption,
          children: [
            if (codeRead && !claimLive) ...[
              ...noticeFor(2),
              TextField(
                controller: deviceNameController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: l10n.deviceTransferDeviceNameLabel),
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilButton(
                onPressed: isClaiming ? null : onClaim,
                label: isClaiming ? l10n.deviceTransferRegisteringClaim : l10n.deviceTransferRegisterNewDevice,
              ),
            ],
          ],
        ),
        const SizedBox(height: VeilSpace.sm),
        TransferStep(
          number: 3,
          title: l10n.deviceTransferNewCompleteTitle,
          state: claimLive ? TransferStepState.current : TransferStepState.upcoming,
          body: claimLive ? l10n.deviceTransferNewCompleteBody : l10n.deviceTransferNewCompleteBodyUpcoming,
          children: [
            // Only a claim that can still be approved shows its code and the
            // button that finishes it.
            if (claimLive) ...[
              ...noticeFor(3),
              // What the user reads off this screen comes first: the code,
              // with the key it stands for and how long it holds.
              TransferCodeBox(
                code: l10n.deviceTransferClaimCode(claimId!),
                codeStyle: theme.textTheme.titleMedium,
                notes: [
                  l10n.deviceTransferClaimFingerprint(claimFingerprint ?? l10n.deviceTransferFingerprintUnavailable),
                  if (claimExpiresAt != null)
                    l10n.deviceTransferExpires(formatTransferExpiry(claimExpiresAt!, now, l10n)),
                ],
              ),
              const SizedBox(height: VeilSpace.sm),
              // What finishing leads to, said above the button that does it.
              VeilInlineBanner(
                dense: true,
                tone: VeilBannerTone.warn,
                message: l10n.deviceTransferNewCompleteNote,
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilButton(
                onPressed: isCompleting ? null : onComplete,
                label: isCompleting ? l10n.deviceTransferCompleting : l10n.deviceTransferCompleteOnDevice,
                icon: Icons.arrow_forward_rounded,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
