import '../../core/errors/user_facing_error.dart';
import '../../l10n/generated/app_localizations.dart';

/// [message], an error a controller reports, in the user's language.
///
/// Controllers report errors as text (formatUserFacingError): for the
/// failures the app has words of its own for, a sentence or a wire code
/// that names one, shown from the ARB file by its code. Any other text is
/// something the app did not write (a server's own message, already
/// redacted) and is shown as it is.
String veilErrorText(AppLocalizations l10n, String message) => switch (userFacingErrorCodeOf(message)) {
      UserFacingErrorCode.sessionRequired => l10n.errorSessionRequired,
      UserFacingErrorCode.transferNeedsApi => l10n.errorTransferNeedsApi,
      UserFacingErrorCode.claimBeforeCompletion => l10n.errorClaimBeforeCompletion,
      UserFacingErrorCode.unexpectedResponse => l10n.errorUnexpectedResponse,
      UserFacingErrorCode.uploadFailed => l10n.errorUploadFailed,
      UserFacingErrorCode.sessionInvalid => l10n.errorSessionInvalid,
      UserFacingErrorCode.notAllowed => l10n.errorNotAllowed,
      UserFacingErrorCode.notFound => l10n.errorNotFound,
      UserFacingErrorCode.conflict => l10n.errorConflict,
      UserFacingErrorCode.rejected => l10n.errorRejected,
      UserFacingErrorCode.relayFailed => l10n.errorRelayFailed,
      UserFacingErrorCode.apiNeedsTls => l10n.errorApiNeedsTls,
      UserFacingErrorCode.realtimeNeedsTls => l10n.errorRealtimeNeedsTls,
      UserFacingErrorCode.networkTimeout => l10n.errorNetworkTimeout,
      UserFacingErrorCode.networkUnavailable => l10n.errorNetworkUnavailable,
      UserFacingErrorCode.tlsPinMismatch => l10n.errorTlsPinMismatch,
      UserFacingErrorCode.challengeInvalid => l10n.errorChallengeInvalid,
      UserFacingErrorCode.deviceNotActive => l10n.errorDeviceNotActive,
      UserFacingErrorCode.deviceSignatureInvalid => l10n.errorDeviceSignatureInvalid,
      UserFacingErrorCode.handleTaken => l10n.errorHandleTaken,
      UserFacingErrorCode.transferInactive => l10n.errorTransferInactive,
      UserFacingErrorCode.transferCodeInvalid => l10n.errorTransferCodeInvalid,
      UserFacingErrorCode.transferClaimRequired => l10n.errorTransferClaimRequired,
      UserFacingErrorCode.transferApprovalRequired => l10n.errorTransferApprovalRequired,
      UserFacingErrorCode.transferCompletionInvalid => l10n.errorTransferCompletionInvalid,
      UserFacingErrorCode.attachmentCanceled => l10n.errorAttachmentCanceled,
      UserFacingErrorCode.attachmentRejected => l10n.errorAttachmentRejected,
      UserFacingErrorCode.peerUnreachable => l10n.errorPeerUnreachable,
      null => message,
    };
