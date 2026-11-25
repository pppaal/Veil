import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Every file of lib/src/core/safety/. The checker reads message text, so it
// must not be able to send it anywhere: its files import only dart:core,
// dart:collection, dart:math and each other (scripts/crypto-architecture-
// check.mjs holds the same rule for the build).
const _expected = [
  'handle_lookalike.dart',
  'link_brands.dart',
  'link_hosts.dart',
  'links.dart',
  'message_risk.dart',
  'rule_risk_checker.dart',
  'rules_en.dart',
  'rules_ko.dart',
  'signals.dart',
  'text_normalizer.dart',
  'thread_risk.dart',
];

const _allowedDartLibraries = {'dart:core', 'dart:collection', 'dart:math'};

void main() {
  test('the checker imports nothing that can reach the network', () {
    final dir = Directory('lib/src/core/safety');
    expect(dir.existsSync(), isTrue, reason: 'lib/src/core/safety is missing');
    final present = (dir.listSync(recursive: true).whereType<File>().map((f) => f.path.substring(dir.path.length + 1)).toList())..sort();
    for (final name in _expected) {
      expect(present, contains(name), reason: 'lib/src/core/safety/$name is missing');
    }
    expect(present, _expected, reason: 'a new file in lib/src/core/safety must be named here');

    // Every quoted URI of a directive counts, the conditional ones too
    // (import 'a.dart' if (dart.library.io) 'b.dart';).
    final directive = RegExp(r'''^\s*(import|export|part)\s+((?:[^;'"]|'[^']*'|"[^"]*")*);''', multiLine: true);
    final quoted = RegExp(r'''(['"])(.*?)\1''');
    for (final name in present) {
      final source = File('${dir.path}/$name').readAsStringSync();
      for (final m in directive.allMatches(source)) {
        for (final q in quoted.allMatches(m[2]!)) {
          final uri = q[2]!;
          final allowed = _allowedDartLibraries.contains(uri) ||
              (_expected.contains(uri)) ||
              (uri.startsWith('package:veil_mobile/src/core/safety/') &&
                  _expected.contains(uri.substring('package:veil_mobile/src/core/safety/'.length)));
          expect(allowed, isTrue, reason: '$name imports $uri');
        }
      }
      expect(source.contains('dart:io') || source.contains('dart:html') || source.contains('dart:ffi'), isFalse,
          reason: '$name names a platform library');
    }
  });
}
