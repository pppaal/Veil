import '../../../l10n/generated/app_localizations.dart';
import '../data/device_transfer_controller.dart';

/// What the old device's last transfer step came to, in the app's language;
/// null while there is nothing to say (the code on screen says it is ready,
/// and the approve dialog shows a claim that is waiting).
String? transferStatusLabel(AppLocalizations l10n, TransferStatus? status) => switch (status) {
      null || TransferTokenReady() || TransferClaimWaiting() => null,
      TransferNeedsApi() => l10n.deviceTransferStatusNeedsApi,
      TransferNotStarted() => l10n.deviceTransferStatusNotStarted,
      TransferClaimCodeMissing() => l10n.deviceTransferStatusClaimCodeMissing,
      TransferClaimNotWaiting(:final claimId) => l10n.deviceTransferStatusClaimNotWaiting(claimId),
      TransferClaimApproved() => l10n.deviceTransferStatusClaimApproved,
    };
