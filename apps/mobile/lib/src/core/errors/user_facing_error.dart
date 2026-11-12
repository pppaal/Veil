import '../security/sensitive_text_redactor.dart';

String formatUserFacingError(Object error) {
  final raw = error.toString().trim();
  const prefixes = ['Bad state: ', 'Exception: ', 'StateError: '];
  var normalized = raw;
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      normalized = raw.substring(prefix.length).trim();
      break;
    }
  }

  switch (normalized) {
    case 'Authenticated API session required.':
      return 'This device no longer has a trusted VEIL session.';
    case 'API mode is required for device transfer.':
      return 'Device transfer is available only while connected to the VEIL API.';
    case 'Claim this new device before completion.':
      return 'Register this new device first, then wait for approval from the old device.';
    case 'Unexpected response shape':
      return 'The relay returned an unexpected response. Try again.';
  }

  if (normalized.startsWith('Attachment upload failed:')) {
    return 'Opaque blob upload failed. Check the relay and try again.';
  }
  if (normalized.startsWith('Request failed: HTTP 401')) {
    return 'This session is no longer valid on this device.';
  }
  if (normalized.startsWith('Request failed: HTTP 403')) {
    return 'This action is not allowed on the current device.';
  }
  if (normalized.startsWith('Request failed: HTTP 404')) {
    return 'The requested VEIL resource was not found.';
  }
  if (normalized.startsWith('Request failed: HTTP 409')) {
    return 'This request conflicts with the current VEIL state. Refresh and try again.';
  }
  if (normalized.startsWith('Request failed: HTTP 422')) {
    return 'The submitted values were rejected. Review the form and try again.';
  }
  if (normalized.startsWith('Request failed: HTTP 5')) {
    return 'The VEIL relay failed to complete the request. Try again shortly.';
  }
  if (normalized == 'API endpoint must use TLS outside local development.') {
    return 'The VEIL API endpoint must use TLS outside local development.';
  }
  if (normalized ==
      'Realtime endpoint must use TLS outside local development.') {
    return 'The VEIL realtime endpoint must use TLS outside local development.';
  }

  return redactSensitiveText(normalized);
}
