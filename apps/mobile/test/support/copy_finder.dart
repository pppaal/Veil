import 'package:flutter_test/flutter_test.dart';

/// Finds a text of the app's copy by what it says: `find.text`, under the
/// name the tests read it by.
Finder findCopy(String text, {bool skipOffstage = true}) => find.text(text, skipOffstage: skipOffstage);

/// Like [findCopy], for a text that has [part] in it.
Finder findCopyContaining(String part, {bool skipOffstage = true}) =>
    find.textContaining(part, skipOffstage: skipOffstage);
