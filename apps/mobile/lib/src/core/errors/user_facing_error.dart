import '../network/veil_api_exception.dart';
import '../security/sensitive_text_redactor.dart';

// What Dart puts before the message of the errors the app throws.
final _errorTypePrefix = RegExp(r'^(?:Bad state|Exception|StateError): ');

/// The failures the app has words of its own for. [sentence] is what
/// [formatUserFacingError] returns for one, and what logs and stored rows
/// keep: an English sentence for the codes that had one before screens
/// translated them (rows saved then still hold it), and for every later
/// code the wire code the failure came with. A screen shows either in the
/// user's language by its code (see [userFacingErrorCodeOf]); none is ever
/// shown as it is.
enum UserFacingErrorCode {
  sessionRequired('This device no longer has a trusted VEIL session.'),
  transferNeedsApi('Device transfer is available only while connected to the VEIL API.'),
  claimBeforeCompletion('Register this new device first, then wait for approval from the old device.'),
  unexpectedResponse('The relay returned an unexpected response. Try again.'),
  uploadFailed('Opaque blob upload failed. Check the relay and try again.'),
  sessionInvalid('This session is no longer valid on this device.'),
  notAllowed('This action is not allowed on the current device.'),
  notFound('The requested VEIL resource was not found.'),
  conflict('This request conflicts with the current VEIL state. Refresh and try again.'),
  rejected('The submitted values were rejected. Review the form and try again.'),
  relayFailed('The VEIL relay failed to complete the request. Try again shortly.'),
  apiNeedsTls('The VEIL API endpoint must use TLS outside local development.'),
  realtimeNeedsTls('The VEIL realtime endpoint must use TLS outside local development.'),

  // Below HTTP (TransportErrorCode): no answer, no connection, a server
  // certificate the build does not pin.
  networkTimeout('network_timeout', wire: true),
  networkUnavailable('network_unavailable', wire: true),
  tlsPinMismatch('tls_pin_mismatch', wire: true),

  // The server's own error codes the app has words for.
  challengeInvalid('challenge_invalid', wire: true),
  deviceNotActive('device_not_active', wire: true),
  deviceSignatureInvalid('invalid_device_signature', wire: true),
  handleTaken('handle_taken', wire: true),
  transferInactive('transfer_session_inactive', wire: true),
  transferCodeInvalid('transfer_token_invalid', wire: true),
  transferClaimRequired('transfer_claim_required', wire: true),
  transferApprovalRequired('transfer_approval_required', wire: true),
  transferCompletionInvalid('transfer_completion_invalid', wire: true),
  attachmentCanceled('attachment_upload_canceled', wire: true),
  attachmentRejected('attachment_upload_invalid', wire: true);

  const UserFacingErrorCode(this.sentence, {this.wire = false});

  final String sentence;

  /// Whether [sentence] is the wire code the failure arrives with.
  final bool wire;
}

/// Which of the app's own failures [message] is, when it is a text
/// [formatUserFacingError] returned for one; null for any other text (a
/// relay's own message, say), which has no translation.
UserFacingErrorCode? userFacingErrorCodeOf(String message) {
  for (final code in UserFacingErrorCode.values) {
    if (code.sentence == message) return code;
  }
  return null;
}

String formatUserFacingError(Object error) {
  final byWireCode = error is VeilApiException ? _wireCodeOf(error.code) : null;
  if (byWireCode != null) return byWireCode.sentence;
  final normalized = error.toString().trim().replaceFirst(_errorTypePrefix, '').trim();
  return _codeOf(normalized)?.sentence ?? redactSensitiveText(normalized);
}

/// The code for a failure that came with the wire code [code] (a transport
/// failure's, or the server's), when the app has words for it. The codes
/// that report an English sentence are found by their text instead.
UserFacingErrorCode? _wireCodeOf(String? code) {
  if (code == null) return null;
  for (final candidate in UserFacingErrorCode.values) {
    if (candidate.wire && candidate.sentence == code) return candidate;
  }
  return null;
}

UserFacingErrorCode? _codeOf(String normalized) {
  switch (normalized) {
    case 'Authenticated API session required.':
      return UserFacingErrorCode.sessionRequired;
    case 'API mode is required for device transfer.':
      return UserFacingErrorCode.transferNeedsApi;
    case 'Claim this new device before completion.':
      return UserFacingErrorCode.claimBeforeCompletion;
    case 'Unexpected response shape':
      return UserFacingErrorCode.unexpectedResponse;
    case 'API endpoint must use TLS outside local development.':
      return UserFacingErrorCode.apiNeedsTls;
    case 'Realtime endpoint must use TLS outside local development.':
      return UserFacingErrorCode.realtimeNeedsTls;
  }
  if (normalized.startsWith('Attachment upload failed:')) return UserFacingErrorCode.uploadFailed;
  if (normalized.startsWith('Request failed: HTTP 401')) return UserFacingErrorCode.sessionInvalid;
  if (normalized.startsWith('Request failed: HTTP 403')) return UserFacingErrorCode.notAllowed;
  if (normalized.startsWith('Request failed: HTTP 404')) return UserFacingErrorCode.notFound;
  if (normalized.startsWith('Request failed: HTTP 409')) return UserFacingErrorCode.conflict;
  if (normalized.startsWith('Request failed: HTTP 422')) return UserFacingErrorCode.rejected;
  if (normalized.startsWith('Request failed: HTTP 5')) return UserFacingErrorCode.relayFailed;
  return null;
}
