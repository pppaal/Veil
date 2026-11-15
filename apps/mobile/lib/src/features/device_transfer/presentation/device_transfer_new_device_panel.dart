import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
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
  final Future<void> Function() onClaim;
  final Future<void> Function() onComplete;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasClaim = claimId != null;
    final claimLive = hasClaim && !claimExpired;
    final pasting = !hasCode || editingCode;
    // Where the notice goes: its own step, or else the one in hand.
    final noticeStep = notice?.step ?? (claimLive ? 3 : (hasCode ? 2 : 1));
    List<Widget> noticeFor(int step) => [
          if (notice != null && noticeStep == step) ...[
            VeilInlineBanner(
              dense: true,
              title: notice!.isError ? l10n.deviceTransferFailedTitle : l10n.deviceTransferStatusTitle,
              message: notice!.message,
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
          body: pasting ? l10n.deviceTransferNewCodeBody : null,
          trailing: pasting
              ? null
              : TextButton(onPressed: onEditCode, child: Text(l10n.deviceTransferNewCodeChange)),
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
                tone: hasCode ? VeilButtonTone.secondary : VeilButtonTone.primary,
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
          state: !hasCode
              ? TransferStepState.upcoming
              : claimLive
                  ? TransferStepState.done
                  : TransferStepState.current,
          body: claimLive ? null : l10n.deviceTransferNewDeviceCaption,
          status: hasClaim && claimExpired ? l10n.deviceTransferClaimExpiredPill : null,
          statusTone: VeilBannerTone.danger,
          children: [
            if (hasCode && !claimLive) ...[
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
          body: hasClaim ? l10n.deviceTransferNewCompleteBody : l10n.deviceTransferNewCompleteBodyUpcoming,
          children: [
            // A claim that ran out keeps its code and its button on screen,
            // the button switched off: registering again replaces it.
            if (hasClaim) ...[
              ...noticeFor(3),
              SelectableText(l10n.deviceTransferClaimCode(claimId!), style: theme.textTheme.titleMedium),
              const SizedBox(height: VeilSpace.xxs),
              TransferStepNote(
                l10n.deviceTransferClaimFingerprint(claimFingerprint ?? l10n.deviceTransferFingerprintUnavailable),
              ),
              if (claimExpiresAt != null)
                TransferStepNote(l10n.deviceTransferExpires(formatTransferExpiry(claimExpiresAt!, now, l10n))),
              const SizedBox(height: VeilSpace.sm),
              VeilButton(
                onPressed: isCompleting || claimExpired ? null : onComplete,
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
