import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// A block is not silent. No notice goes to the blocked account, but from the
// moment of the block the server refuses what it sends in the 1:1
// (peer_unreachable, or a key lookup that answers like an unknown handle),
// and both apps show that failure: safety_phone_test ("a send to someone who
// blocked the user is refused and shown as not sent"), safety_relay_test, and
// the web's e2e/characterization/blocking.spec.ts. So the dialog that
// confirms a block says first that their messages will show as not sent,
// and never lets "they won't be told" stand on its own.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  test('the block dialog says that direct messages from the blocked side fail', () {
    expect(en.blockConfirmBody, startsWith('Their messages to you will show as not sent'));
    // "They won't be told" never stands alone: the sentence before it says
    // what they will see.
    expect(en.blockConfirmBody, isNot(startsWith("They won't be told")));
    expect(en.blockConfirmBody, isNot(contains("and they won't be told.")));
  });

  // apps/web-demo sits next to apps/mobile in this repository, and CI checks
  // out the whole of it.
  test('the web demo confirms a block in the same words', () {
    final file = File(p.normalize(p.join(Directory.current.path, '..', 'web-demo', 'i18n', 'en.json')));
    final web = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(web['safety.blockBody'], en.blockConfirmBody);
  });
}
