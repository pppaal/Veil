import '../../../l10n/generated/app_localizations.dart';
import '../data/device_transfer_controller.dart';

/// What the old device's last transfer step came to, in the app's language;
/// null while there is nothing to say.
String? transferStatusLabel(AppLocalizations l10n, TransferStatus? status) => switch (status) {
      null => null,
      TransferNeedsApi() => l10n.deviceTransferStatusNeedsApi,
      TransferTokenReady() => l10n.deviceTransferStatusTokenReady,
      TransferNotStarted() => l10n.deviceTransferStatusNotStarted,
      TransferClaimCodeMissing() => l10n.deviceTransferStatusClaimCodeMissing,
      TransferClaimNotWaiting(:final claimId) => l10n.deviceTransferStatusClaimNotWaiting(claimId),
      TransferClaimApproved(:final claimId, :final fingerprint) =>
        l10n.deviceTransferStatusClaimApproved(claimId, fingerprint),
    };
