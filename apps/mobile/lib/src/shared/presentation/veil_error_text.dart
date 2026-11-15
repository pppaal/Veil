import '../../core/errors/user_facing_error.dart';
import '../../l10n/generated/app_localizations.dart';

/// [message], an error a controller reports, in the user's language.
///
/// Controllers report errors as text (formatUserFacingError), English for
/// the failures the app has words of its own for. Those are shown from the
/// ARB files by their code. Any other text is something the app did not
/// write (a relay's own message, already redacted) and is shown as it is.
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
      null => message,
    };
