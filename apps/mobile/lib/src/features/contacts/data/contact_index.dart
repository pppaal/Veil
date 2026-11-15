import 'contacts_providers.dart';

// What the contacts list decides without a widget: which contacts a query
// matches, and under which letter each is filed.

// The first consonant of a Hangul syllable, by its position in the block:
// a Korean list is indexed by consonant (ㄱ, ㄴ, ㄷ, …), a doubled one under
// its single form, never by whole syllable.
const _initialConsonants = [
  'ㄱ', 'ㄱ', 'ㄴ', 'ㄷ', 'ㄷ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅂ', 'ㅅ', //
  'ㅅ', 'ㅇ', 'ㅈ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];
const _firstSyllable = 0xAC00;
const _lastSyllable = 0xD7A3;
const _syllablesPerConsonant = 588;

final _letter = RegExp(r'\p{L}', unicode: true);

/// The letter a contact called [label] is filed under: the upper-case first
/// letter, the first consonant of a Hangul syllable, or `#` for a name that
/// starts with anything else (a digit, a symbol, nothing).
String contactIndexLetter(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return '#';
  final code = trimmed.runes.first;
  if (code >= _firstSyllable && code <= _lastSyllable) {
    return _initialConsonants[(code - _firstSyllable) ~/ _syllablesPerConsonant];
  }
  final first = String.fromCharCode(code);
  return _letter.hasMatch(first) ? first.toUpperCase() : '#';
}

/// The contacts whose name or handle contains [query], whatever its case.
List<ContactEntry> filterContacts(List<ContactEntry> contacts, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return contacts;
  return [
    for (final contact in contacts)
      if (contact.label.toLowerCase().contains(needle) || contact.handle.toLowerCase().contains(needle)) contact,
  ];
}

/// One letter of the list with the contacts filed under it.
typedef ContactSection = ({String letter, List<ContactEntry> contacts});

/// [contacts] by index letter, each section sorted by name. Latin letters
/// come before Hangul consonants, or after them with [hangulFirst] (a
/// Korean list starts at ㄱ); `#` is always last.
List<ContactSection> sectionContacts(List<ContactEntry> contacts, {bool hangulFirst = false}) {
  final byLetter = <String, List<ContactEntry>>{};
  for (final contact in contacts) {
    byLetter.putIfAbsent(contactIndexLetter(contact.label), () => []).add(contact);
  }
  int rank(String letter) {
    if (letter == '#') return 2;
    return _initialConsonants.contains(letter) == hangulFirst ? 0 : 1;
  }

  final letters = byLetter.keys.toList()
    ..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.compareTo(b));
  return [
    for (final letter in letters)
      (
        letter: letter,
        contacts: byLetter[letter]!..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
      ),
  ];
}
