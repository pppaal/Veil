import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_seed.dart';

// The language half of the layout gate: every text a rendered screen draws
// must be in the language of the run. A Korean run fails on a text with a
// Latin word and no Hangul; an English run fails on a text with Hangul.
//
// Only the app's own copy is held to that. What a screen shows of other
// people's words, or of data, is taken out of a text before it is judged;
// [notOwnCopy] is the whole list of what that is, with the reason for each.

/// Something a screen shows that the app did not write, and so does not
/// translate.
class NotOwnCopy {
  const NotOwnCopy(
    this.what,
    this.why, {
    this.pattern,
    this.texts = const [],
    this.names = const [],
    this.alone = const [],
  });

  final String what;
  final String why;

  /// Taken out wherever it matches.
  final RegExp? pattern;

  /// Taken out wherever one occurs whole.
  final List<String> texts;

  /// Like [texts]; a text that is only one word of a name, or its first
  /// letter (an avatar), is taken out too.
  final List<String> names;

  /// Taken out only where one is the whole text.
  final List<String> alone;
}

/// Everything the language check leaves out. Add to it only what is not the
/// app's own copy; a sentence the app wrote belongs in both ARB files.
final List<NotOwnCopy> notOwnCopy = [
  NotOwnCopy(
    'the brand name',
    'VEIL is the product name in every language',
    pattern: RegExp(r'\bVEIL\b'),
  ),
  NotOwnCopy(
    'names, handles and device names of the seeded fixtures',
    'what people call themselves and their devices is theirs, in whatever script',
    names: fixtureNames,
  ),
  NotOwnCopy(
    'message text, captions, ids and typed queries of the seeded fixtures',
    'a message is shown as its author wrote it; ids and codes are data',
    texts: fixtureTexts,
  ),
  const NotOwnCopy(
    'what a case types into a search field',
    'a query is the user\'s own words',
    alone: [conversationSearchQuery, chatSearchQuery],
  ),
  NotOwnCopy(
    'handles',
    'a handle is lower-case Latin by rule, with or without its @',
    pattern: RegExp(r'@[a-z0-9._]+'),
  ),
  NotOwnCopy(
    'the example handles in input hints',
    'a hint shows what a handle looks like, and handles are Latin by rule',
    pattern: RegExp(r'\b(?:cold\.operator|icarus|daedalus|minos)\b'),
  ),
  NotOwnCopy(
    'platform names',
    'Android, iPhone and the like are trademarks, written the same everywhere',
    pattern: RegExp(r'\b(?:Android|iPhone|iPad|iOS|macOS|Windows|Linux)\b'),
  ),
  NotOwnCopy(
    'PIN',
    'Korean interfaces write PIN in Latin letters',
    pattern: RegExp(r'\bPIN\b'),
  ),
  NotOwnCopy(
    'URLs',
    'an address is data',
    pattern: RegExp(r'https?://\S+'),
  ),
  NotOwnCopy(
    'file names',
    'a file keeps the name it was given',
    pattern: RegExp(r'\b[\w-]+\.(?:pdf|enc|png|jpe?g|webp|gif|mp4|mov|m4a|zip|txt)\b'),
  ),
  NotOwnCopy(
    'MIME types',
    'a content type is data from the message',
    pattern: RegExp(r'\b(?:application|image|video|audio|text)/[\w.+-]+'),
  ),
  NotOwnCopy(
    'the scheme of a transfer code',
    'a transfer code is read by a device, not by a person',
    pattern: RegExp(r'\bVEIL_TRANSFER::'),
  ),
  const NotOwnCopy(
    'the index letters of the contacts list',
    'the letter a contact is filed under comes from its name: the first consonant of a Korean one',
    alone: ['ㄱ', 'ㄴ', 'ㄷ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅅ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'],
  ),
];

final _hangul = RegExp(r'[ᄀ-ᇿ㄰-㆏가-힯]');
final _latinWord = RegExp(r'[A-Za-z]{3,}');
final _wordJoiner = RegExp('⁠');

// Longest first, so a name goes before a word of it does.
final List<String> _whole = [
  for (final entry in notOwnCopy) ...[...entry.texts, ...entry.names],
]..sort((a, b) => b.length.compareTo(a.length));

// One word of a fixture name ("Selene" of "Selene Park") or its first
// letter, as an avatar or a short greeting shows it; and what is left out
// only when it stands alone.
final Set<String> _nameParts = {
  for (final entry in notOwnCopy)
    for (final name in entry.names) ...[
      ...name.split(RegExp(r'[\s()]+')).where((word) => word.isNotEmpty),
      name.characters.first,
      name.characters.first.toUpperCase(),
    ],
  for (final entry in notOwnCopy) ...entry.alone,
};

/// What is left of [text] once everything in [notOwnCopy] is taken out: the
/// part the app wrote.
String ownCopyOf(String text) {
  var rest = text.replaceAll(_wordJoiner, '').trim();
  if (_nameParts.contains(rest)) return '';
  for (final whole in _whole) {
    rest = rest.replaceAll(whole, ' ');
  }
  for (final entry in notOwnCopy) {
    final pattern = entry.pattern;
    if (pattern != null) rest = rest.replaceAll(pattern, ' ');
  }
  return rest.trim();
}

/// Whether [text] has own copy in the language the [locale] run is not in.
bool isOtherLanguage(String text, String locale) {
  final own = ownCopyOf(text);
  return locale == 'ko' ? _latinWord.hasMatch(own) && !_hangul.hasMatch(own) : _hangul.hasMatch(own);
}

/// The texts on screen that are in the language the run is not in, each
/// cut to 80 characters.
Set<String> otherLanguageTextsOnScreen(WidgetTester tester, String locale) {
  final texts = <String>{
    for (final element in find.byType(RichText).evaluate())
      (element.widget as RichText).text.toPlainText().replaceAll(_wordJoiner, '').trim(),
    for (final element in find.byType(EditableText).evaluate())
      (element.widget as EditableText).controller.text.trim(),
  };
  return {
    for (final text in texts)
      if (isOtherLanguage(text, locale)) text.length > 80 ? '${text.substring(0, 80)}…' : text,
  };
}
