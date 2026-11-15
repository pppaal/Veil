import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/errors/user_facing_error.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_error_text.dart';

// The messenger reports an error as one line of text. For the failures the
// app has words of its own for, that line is English (logs, callers without
// a locale), and a screen shows it in the user's language by its code.

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

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ko = lookupAppLocalizations(const Locale('ko'));

  test('formatUserFacingError reports each known failure in the words it always had', () {
    for (final MapEntry(key: raw, value: sentence) in _reported.entries) {
      expect(formatUserFacingError(raw), sentence, reason: raw);
    }
    expect(_reported.values.toSet(), {for (final code in UserFacingErrorCode.values) code.sentence},
        reason: 'every code is reachable, and nothing else is');
  });

  test('every known failure has a code, and words in both languages', () {
    final english = <String>{};
    final korean = <String>{};
    for (final raw in _reported.keys) {
      final reported = formatUserFacingError(raw);
      expect(userFacingErrorCodeOf(reported), isNotNull, reason: raw);
      english.add(veilErrorText(en, reported));
      final translated = veilErrorText(ko, reported);
      korean.add(translated);
      expect(translated, isNot(reported), reason: 'Korean for "$reported"');
      expect(translated, matches(RegExp('[가-힣]')), reason: translated);
      // Names stay as they are written; nothing else of the sentence is Latin.
      expect(translated.replaceAll(RegExp('VEIL|API|TLS'), ''), isNot(matches(RegExp('[A-Za-z]'))), reason: translated);
    }
    expect(english, hasLength(UserFacingErrorCode.values.length), reason: 'one sentence per code');
    expect(korean, hasLength(UserFacingErrorCode.values.length), reason: 'one sentence per code');
  });

  test('what the app did not write is shown as it is, redacted, in any language', () {
    const relayText = 'handle_not_found';
    expect(formatUserFacingError(Exception(relayText)), relayText);
    expect(userFacingErrorCodeOf(relayText), isNull);
    expect(veilErrorText(ko, relayText), relayText);
    expect(veilErrorText(en, relayText), relayText);
  });
}
