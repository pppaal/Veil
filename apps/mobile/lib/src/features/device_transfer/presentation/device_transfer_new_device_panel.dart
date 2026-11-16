import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'device_transfer_code.dart';
import 'device_transfer_step.dart';

/// What the screen has to say about the stage in hand: that the last action
/// went through, or why it did not.
class TransferNotice {
  const TransferNotice(this.message, {this.isError = false, this.step});

  final String message;
  final bool isError;

  /// The stage the notice belongs to: 1 for the code, 2 for finishing; the
  /// stage in hand when null.
  final int? step;
}

/// The new phone's half of a move, one screen per stage as Signal's: first
/// the transfer code and this phone's name with one "Continue" that reads
/// the code and registers the phone; then "Approve on your old phone" with
/// the short code to enter there, large, and "Finish".
///
/// A claim that ran out goes back to the first stage. Its transfer session
/// ran out with it (they share one window), so nothing can be finished on
/// the code this phone holds: the first stage says so and takes a new code.
class TransferNewDevicePanel extends StatelessWidget {
  const TransferNewDevicePanel({
    super.key,
    required this.codeController,
    required this.deviceNameController,
    required this.editingCode,
    required this.isClaiming,
    required this.isCompleting,
    required this.claimId,
    required this.claimFingerprint,
    required this.claimExpiresAt,
    required this.claimExpired,
    required this.notice,
    required this.onContinue,
    required this.onEditCode,
    required this.onKeepCode,
    required this.onComplete,
    required this.now,
  });

  final TextEditingController codeController;
  final TextEditingController deviceNameController;

  /// Whether the user went back from the second stage to paste another code.
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
  final VoidCallback onContinue;
  final VoidCallback onEditCode;

  /// Back to the second stage, keeping the claim this phone holds.
  final VoidCallback onKeepCode;
  final Future<void> Function() onComplete;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final claimLive = claimId != null && !claimExpired;
    // The code this phone holds went with the claim made on it.
    final expired = claimId != null && claimExpired;
    final pasting = !claimLive || editingCode;
    final noticeStep = notice?.step ?? (pasting ? 1 : 2);
    Widget? noticeFor(int step) => notice == null || noticeStep != step
        ? null
        : TransferStepResult(
            message: veilErrorText(l10n, notice!.message),
            tone: notice!.isError ? VeilTone.danger : VeilTone.good,
          );
    final muted = theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted);

    if (pasting) {
      final result = noticeFor(1);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VeilGroup(
            children: [
              VeilRow.field(
                field: TextField(
                  controller: codeController,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l10n.deviceTransferPayloadInputLabel,
                    hintText: l10n.deviceTransferPayloadHint,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
              ),
              VeilRow.field(
                title: l10n.deviceTransferDeviceNameLabel,
                field: TextField(controller: deviceNameController, textInputAction: TextInputAction.done),
              ),
            ],
          ),
          TransferControls(
            children: [
              if (expired && result == null)
                TransferStepResult(message: l10n.deviceTransferNewCodeExpiredBody, tone: VeilTone.warn),
              VeilButton(
                onPressed: isClaiming ? null : onContinue,
                label: isClaiming ? l10n.deviceTransferRegisteringClaim : l10n.commonContinue,
              ),
              // Taken back to the claim this phone still holds.
              if (claimLive) VeilButton(tone: VeilButtonTone.ghost, onPressed: onKeepCode, label: l10n.commonCancel),
              if (result != null) result,
            ],
          ),
        ],
      );
    }

    // What the user reads off this screen first, the code to enter on the
    // old phone, then the key it stands for and how long it holds.
    final result = noticeFor(2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.xs, VeilSpace.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.deviceTransferNewCompleteTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: VeilSpace.xl),
          Center(
            child: SelectableText(
              claimId!,
              key: const ValueKey('transfer-claim-code'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          Text(l10n.deviceTransferNewCompleteBody, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: VeilSpace.xl),
          Text(
            l10n.deviceTransferClaimFingerprint(claimFingerprint ?? l10n.deviceTransferFingerprintUnavailable),
            style: muted,
          ),
          if (claimExpiresAt != null)
            Text(l10n.deviceTransferExpires(formatTransferExpiry(claimExpiresAt!, now, l10n)), style: muted),
          const SizedBox(height: VeilSpace.md),
          VeilButton(
            onPressed: isCompleting ? null : onComplete,
            label: isCompleting ? l10n.deviceTransferCompleting : l10n.deviceTransferCompleteOnDevice,
          ),
          const SizedBox(height: VeilSpace.xs),
          // Another code: back to the first stage.
          VeilButton(tone: VeilButtonTone.ghost, onPressed: onEditCode, label: l10n.deviceTransferNewCodeChange),
          if (result != null) ...[const SizedBox(height: VeilSpace.xs), result],
        ],
      ),
    );
  }
}
