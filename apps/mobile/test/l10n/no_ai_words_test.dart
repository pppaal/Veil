import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The checks the app runs on a phone are rules, not a model, and the app
// says so by never calling them anything else: no string in app_en.arb
// says AI (as a word, in capitals: "email", "again" and "failed" are fine),
// artificial intelligence, machine learning or smart detection.

final _ai = RegExp(r'\bAI\b');
final _phrases = RegExp(r'artificial intelligence|machine learning|smart detection', caseSensitive: false);

Iterable<(String, String)> _strings(String key, Object? value) sync* {
  if (value is String) {
    yield (key, value);
  } else if (value is Map) {
    for (final MapEntry(key: inner, :value) in value.entries) {
      yield* _strings('$key.$inner', value);
    }
  }
}

void main() {
  test('no string calls the checks AI', () {
    final arb = json.decode(File('lib/src/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
    final offending = [
      for (final MapEntry(:key, :value) in arb.entries)
        for (final (path, text) in _strings(key, value))
          if (_ai.hasMatch(text) || _phrases.hasMatch(text)) '$path: $text',
    ];
    expect(offending, isEmpty);
    // The rule itself bites.
    expect(_ai.hasMatch('Checked by AI'), isTrue);
    expect(_ai.hasMatch('Couldn\'t send the email again'), isFalse);
    expect(_phrases.hasMatch('Smart Detection on'), isTrue);
  });
}
