import '../security/sensitive_text_redactor.dart';

// What Dart puts before the message of the errors the app throws.
final _errorTypePrefix = RegExp(r'^(?:Bad state|Exception|StateError): ');

/// The failures the app has words of its own for. [sentence] is what
/// [formatUserFacingError] returns for one: the English text that logs and
/// callers without a locale get. A screen shows it in the user's language
/// by its code (see [userFacingErrorCodeOf]).
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
  realtimeNeedsTls('The VEIL realtime endpoint must use TLS outside local development.');

  const UserFacingErrorCode(this.sentence);

  final String sentence;
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
  final normalized = error.toString().trim().replaceFirst(_errorTypePrefix, '').trim();
  return _codeOf(normalized)?.sentence ?? redactSensitiveText(normalized);
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
