import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The word joiner the shared components put inside Korean words so that a
/// line breaks between words (veilKeepWordsWhole, VeilCopy).
const wordJoiner = '⁠';

/// [text] as a person reads it: without the joiners it is drawn with.
String plainCopy(String text) => text.replaceAll(wordJoiner, '');

/// Finds a text by what it says, however it is drawn. `find.text` compares
/// the characters a widget draws, and Korean copy in the shared components
/// is drawn with word joiners; this compares what the text says.
Finder findCopy(String text, {bool skipOffstage = true}) => find.byWidgetPredicate(
      (widget) => switch (widget) {
        Text(:final data?) => plainCopy(data) == text,
        Text(:final textSpan?) => plainCopy(textSpan.toPlainText()) == text,
        _ => false,
      },
      description: 'text saying "$text"',
      skipOffstage: skipOffstage,
    );

/// Like [findCopy], for a text that has [part] in it.
Finder findCopyContaining(String part, {bool skipOffstage = true}) => find.byWidgetPredicate(
      (widget) => switch (widget) {
        Text(:final data?) => plainCopy(data).contains(part),
        Text(:final textSpan?) => plainCopy(textSpan.toPlainText()).contains(part),
        _ => false,
      },
      description: 'text containing "$part"',
      skipOffstage: skipOffstage,
    );
