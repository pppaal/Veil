import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/errors/user_facing_error.dart';
import 'package:veil_mobile/src/core/network/http_transport.dart';
import 'package:veil_mobile/src/core/network/veil_api_exception.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_error_text.dart';

// The messenger reports an error as one line of text. For the failures the
// app has words of its own for, that line is the formatter's sentence (logs,
// callers without a locale), and a screen shows the ARB's sentence for it,
// found by its code.

// What each failure the app knows was reported as before it had a code.
const _reported = <String, String>{
  'Bad state: Authenticated API session required.': 'This device no longer has a trusted VEIL session.',
  'Exception: API mode is required for device transfer.':
      'Device transfer is available only while connected to the VEIL API.',
  'StateError: Claim this new device before completion.':
      'Register this new device first, then wait for approval from the old device.',
  'Unexpected response shape': 'The relay returned an unexpected response. Try again.',
  'Attachment upload failed: 507': 'Opaque blob upload failed. Check the relay and try again.',
  'Request failed: HTTP 401': 'This session is no longer valid on this device.',
  'Request failed: HTTP 403 forbidden': 'This action is not allowed on the current device.',
  'Request failed: HTTP 404': 'The requested VEIL resource was not found.',
  'Request failed: HTTP 409': 'This request conflicts with the current VEIL state. Refresh and try again.',
  'Request failed: HTTP 422': 'The submitted values were rejected. Review the form and try again.',
  'Request failed: HTTP 503': 'The VEIL relay failed to complete the request. Try again shortly.',
  'API endpoint must use TLS outside local development.':
      'The VEIL API endpoint must use TLS outside local development.',
  'Realtime endpoint must use TLS outside local development.':
      'The VEIL realtime endpoint must use TLS outside local development.',
};

// The failures that arrive with a wire code (a transport failure's, or the
// server's) the app has words for, whatever English text came with them.
final _byWireCode = <VeilApiException, UserFacingErrorCode>{
  VeilApiException('The server did not respond in time.', code: TransportErrorCode.timeout):
      UserFacingErrorCode.networkTimeout,
  VeilApiException('The server is unreachable.', code: TransportErrorCode.unavailable):
      UserFacingErrorCode.networkUnavailable,
  VeilApiException('certificate', code: TransportErrorCode.pinMismatch): UserFacingErrorCode.tlsPinMismatch,
  VeilApiException('x', code: 'challenge_invalid', statusCode: 401): UserFacingErrorCode.challengeInvalid,
  VeilApiException('x', code: 'device_not_active', statusCode: 403): UserFacingErrorCode.deviceNotActive,
  VeilApiException('x', code: 'invalid_device_signature'): UserFacingErrorCode.deviceSignatureInvalid,
  VeilApiException('Handle is already taken', code: 'handle_taken', statusCode: 409): UserFacingErrorCode.handleTaken,
  VeilApiException('x', code: 'transfer_session_inactive'): UserFacingErrorCode.transferInactive,
  VeilApiException('x', code: 'transfer_token_invalid'): UserFacingErrorCode.transferCodeInvalid,
  VeilApiException('x', code: 'transfer_claim_required'): UserFacingErrorCode.transferClaimRequired,
  VeilApiException('x', code: 'transfer_approval_required'): UserFacingErrorCode.transferApprovalRequired,
  VeilApiException('x', code: 'transfer_completion_invalid'): UserFacingErrorCode.transferCompletionInvalid,
  VeilApiException('x', code: 'attachment_upload_canceled'): UserFacingErrorCode.attachmentCanceled,
  VeilApiException('x', code: 'attachment_upload_invalid'): UserFacingErrorCode.attachmentRejected,
  VeilApiException('Peer is unreachable', code: 'peer_unreachable', statusCode: 403): UserFacingErrorCode.peerUnreachable,
  // The relay's own reason (here a disappearing timer already past) is
  // never what the user reads.
  VeilApiException('expiresAt is in the past', code: 'validation_failed', statusCode: 400):
      UserFacingErrorCode.requestRejected,
};

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  test('formatUserFacingError reports each known failure in the words it always had', () {
    for (final MapEntry(key: raw, value: sentence) in _reported.entries) {
      expect(formatUserFacingError(raw), sentence, reason: raw);
    }
  });

  test('a failure with a wire code the app knows is reported by that code, whatever its text', () {
    for (final MapEntry(key: error, value: code) in _byWireCode.entries) {
      expect(formatUserFacingError(error), code.sentence, reason: error.code);
      expect(userFacingErrorCodeOf(formatUserFacingError(error)), code, reason: error.code);
    }
    // A wire code the app has no words for leaves the server's text as it is.
    expect(formatUserFacingError(VeilApiException('User not found', code: 'handle_not_found')), 'User not found');
  });

  test('every code is reachable, and nothing else is', () {
    expect(
      {..._reported.values.map(userFacingErrorCodeOf), ..._byWireCode.values},
      UserFacingErrorCode.values.toSet(),
    );
  });

  test('every known failure has a code, and a sentence of the ARB behind it', () {
    final english = <String>{};
    for (final reported in [..._reported.keys.map(formatUserFacingError), ..._byWireCode.keys.map(formatUserFacingError)]) {
      expect(userFacingErrorCodeOf(reported), isNotNull, reason: reported);
      english.add(veilErrorText(en, reported));
    }
    // One sentence per code, except the two failures the user can do
    // nothing about but try again, which say the same words.
    expect(en.errorRelayFailed, en.errorUnexpectedResponse);
    expect(english, hasLength(UserFacingErrorCode.values.length - 1), reason: 'one sentence per code');
    // What a screen shows never names the product in capitals or the old
    // vocabulary (spec 3.2, 10.4).
    for (final sentence in english) {
      expect(sentence, isNot(matches(RegExp(r'VEIL|\brelay\b|\btoken\b|\bclaim|\bopaque\b', caseSensitive: false))),
          reason: sentence);
    }
  });

  test('what the app did not write is shown as it is, redacted', () {
    const relayText = 'handle_not_found';
    expect(formatUserFacingError(Exception(relayText)), relayText);
    expect(userFacingErrorCodeOf(relayText), isNull);
    expect(veilErrorText(en, relayText), relayText);
  });
}
