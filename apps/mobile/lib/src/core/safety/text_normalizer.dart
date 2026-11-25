// Normalisation for the scam checker: the common ways of writing a word so a
// plain word list misses it (zero-width characters, full-width letters,
// Cyrillic look-alikes, loose Hangul jamo, s p a c e d letters) are undone
// before any rule reads the text. Pure Dart, nothing leaves the phone.

/// One word of the spaced view, with its edge punctuation taken off.
class TextToken {
  const TextToken(this.text, {required this.sentenceEnd});

  final String text;

  /// The token ends a sentence: it is the last one, or a full stop, question
  /// mark, exclamation mark or line break follows it.
  final bool sentenceEnd;

  @override
  String toString() => sentenceEnd ? '$text|' : text;
}

/// The views of one message that the rules read.
class NormalizedText {
  NormalizedText._(this.folded, this.spaced, this.looseSpaced, this.compact)
      : tokens = _tokensOf(spaced),
        looseTokens = looseSpaced == spaced ? _tokensOf(spaced) : _tokensOf(looseSpaced);

  /// After steps 1 to 4 (invisible characters out, folds, Hangul composed),
  /// lower case.
  final String folded;

  /// Words separated by one space: letters, digits, Hangul syllables and
  /// `. , ! ? : ; ' " - / @ £ $ ₩ %` kept, everything else (symbols, emoji,
  /// loose jamo such as ㅋㅋ) a space. Runs of single letters are joined.
  final String spaced;

  /// The spaced view without joining runs of single letters ("돈 좀 줘" stays
  /// three words here, while [spaced] reads it as one).
  final String looseSpaced;

  /// Letters, digits and Hangul syllables only.
  final String compact;

  final List<TextToken> tokens;
  final List<TextToken> looseTokens;
}

/// The longest text the checker reads, in UTF-16 code units.
const maxCheckedLength = 4000;

/// Every view of [text] (only its first [maxCheckedLength] units).
NormalizedText normalizeText(String text) {
  final limited = text.length > maxCheckedLength ? text.substring(0, maxCheckedLength) : text;
  final folded = composeHangul(foldLookalikes(foldWidth(limited)));
  final joined = joinSpacedLetters(folded);
  return NormalizedText._(folded, _spacedView(joined), _spacedView(folded), _compactView(joined));
}

// Step 1: characters that show nothing.
const _invisibleSingles = <int>{
  0x00AD, 0x034F, 0x061C, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x180E, 0x3164, 0xFEFF, 0xFFA0, //
};

bool isInvisibleCharacter(int c) =>
    _invisibleSingles.contains(c) ||
    (c >= 0x200B && c <= 0x200F) ||
    (c >= 0x202A && c <= 0x202E) ||
    (c >= 0x2060 && c <= 0x2064) ||
    (c >= 0x2066 && c <= 0x2069);

/// Steps 1 and 2: invisible characters removed; full-width ASCII, the
/// ideographic space and circled or parenthesised numbers folded; curly
/// quotes made straight. Case and letters are kept, so links can still be
/// read from the result.
String foldWidth(String text) {
  final out = StringBuffer();
  for (final c in text.runes) {
    if (isInvisibleCharacter(c)) continue;
    if (c >= 0xFF01 && c <= 0xFF5E) {
      out.writeCharCode(c - 0xFEE0);
    } else if (c == 0x3000) {
      out.write(' ');
    } else if (c >= 0x2460 && c <= 0x2473) {
      out.write(c - 0x2460 + 1);
    } else if (c >= 0x2474 && c <= 0x2487) {
      out.write(c - 0x2474 + 1);
    } else if (c == 0x2018 || c == 0x2019 || c == 0x02BC) {
      out.write("'");
    } else if (c == 0x201C || c == 0x201D) {
      out.write('"');
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

// Step 3: Cyrillic and Greek letters that look like Latin ones.
const _lookalikes = <int, String>{
  // Cyrillic small: \u0430 \u0435 \u043e \u0440 \u0441 \u0443 \u0445 \u0456 \u0458 \u0455 \u0501 \u043a \u043c \u043d \u0442 \u0432
  0x0430: 'a', 0x0435: 'e', 0x043E: 'o', 0x0440: 'p', 0x0441: 'c', 0x0443: 'y', 0x0445: 'x',
  0x0456: 'i', 0x0458: 'j', 0x0455: 's', 0x0501: 'd', 0x043A: 'k', 0x043C: 'm', 0x043D: 'h',
  0x0442: 't', 0x0432: 'b',
  // Cyrillic capital
  0x0410: 'a', 0x0415: 'e', 0x041E: 'o', 0x0420: 'p', 0x0421: 'c', 0x0423: 'y', 0x0425: 'x',
  0x0406: 'i', 0x0408: 'j', 0x0405: 's', 0x0500: 'd', 0x041A: 'k', 0x041C: 'm', 0x041D: 'h',
  0x0422: 't', 0x0412: 'b',
  // Greek small: \u03bf \u03b1 \u03b5 \u03b9 \u03ba \u03bd \u03c1 \u03c4 \u03c5 \u03c7
  0x03BF: 'o', 0x03B1: 'a', 0x03B5: 'e', 0x03B9: 'i', 0x03BA: 'k', 0x03BD: 'v', 0x03C1: 'p',
  0x03C4: 't', 0x03C5: 'u', 0x03C7: 'x',
  // Greek capital
  0x039F: 'o', 0x0391: 'a', 0x0395: 'e', 0x0399: 'i', 0x039A: 'k', 0x039D: 'n', 0x03A1: 'p',
  0x03A4: 't', 0x03A5: 'y', 0x03A7: 'x',
};

/// Step 3: look-alike letters folded to Latin, then lower case.
String foldLookalikes(String text) {
  final out = StringBuffer();
  for (final c in text.runes) {
    final folded = _lookalikes[c];
    if (folded != null) {
      out.write(folded);
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString().toLowerCase();
}

// Step 4: Hangul.
const _sBase = 0xAC00;

bool isHangulSyllable(int c) => c >= 0xAC00 && c <= 0xD7A3;

/// Whether [c] is a loose jamo (compatibility or conjoining) that did not
/// become part of a syllable.
bool isLooseJamo(int c) => (c >= 0x3131 && c <= 0x318E) || (c >= 0x1100 && c <= 0x11FF);

// Compatibility consonants U+3131..U+314E: the initial index (-1 when the
// letter cannot start a syllable) and the final index (0 when it cannot end
// one).
const _compatInitial = [
  0, 1, -1, 2, -1, -1, 3, 4, 5, -1, -1, -1, -1, -1, -1, -1, //
  6, 7, 8, -1, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
];
const _compatFinal = [
  1, 2, 3, 4, 5, 6, 7, 0, 8, 9, 10, 11, 12, 13, 14, 15, //
  16, 17, 0, 18, 19, 20, 21, 22, 0, 23, 24, 25, 26, 27,
];
const _compoundVowels = {
  (8, 0): 9, (8, 1): 10, (8, 20): 11, (13, 4): 14, (13, 5): 15, (13, 20): 16, (18, 20): 19, //
};
const _compoundFinals = {
  (1, 19): 3, (4, 22): 5, (4, 27): 6, (8, 1): 9, (8, 16): 10, (8, 17): 11, (8, 19): 12, //
  (8, 25): 13, (8, 26): 14, (8, 27): 15, (17, 19): 18,
};

bool _isCompatConsonant(int c) => c >= 0x3131 && c <= 0x314E;
bool _isCompatVowel(int c) => c >= 0x314F && c <= 0x3163;

/// Step 4: conjoining jamo (L V T) and runs of compatibility jamo typed one
/// letter at a time become syllables; lone jamo (ㅋㅋ, ㅠㅠ) stay as they are.
String composeHangul(String text) {
  final r = text.runes.toList();
  final out = StringBuffer();
  var i = 0;
  while (i < r.length) {
    final c = r[i];
    // Conjoining jamo: L V (T).
    if (c >= 0x1100 && c <= 0x1112 && i + 1 < r.length && r[i + 1] >= 0x1161 && r[i + 1] <= 0x1175) {
      var t = 0;
      var next = i + 2;
      if (next < r.length && r[next] >= 0x11A8 && r[next] <= 0x11C2) {
        t = r[next] - 0x11A7;
        next++;
      }
      out.writeCharCode(_sBase + ((c - 0x1100) * 21 + (r[i + 1] - 0x1161)) * 28 + t);
      i = next;
      continue;
    }
    // Compatibility jamo: consonant + vowel (+ final if no vowel follows).
    if (_isCompatConsonant(c) && _compatInitial[c - 0x3131] >= 0 && i + 1 < r.length && _isCompatVowel(r[i + 1])) {
      var v = r[i + 1] - 0x314F;
      var j = i + 2;
      if (j < r.length && _isCompatVowel(r[j])) {
        final compound = _compoundVowels[(v, r[j] - 0x314F)];
        if (compound != null) {
          v = compound;
          j++;
        }
      }
      var t = 0;
      if (j < r.length && _isCompatConsonant(r[j]) && _compatFinal[r[j] - 0x3131] > 0) {
        final startsNext = j + 1 < r.length && _isCompatVowel(r[j + 1]);
        if (!startsNext) {
          t = _compatFinal[r[j] - 0x3131];
          j++;
          if (j < r.length && _isCompatConsonant(r[j])) {
            final compound = _compoundFinals[(t, _compatFinal[r[j] - 0x3131])];
            final secondStartsNext = j + 1 < r.length && _isCompatVowel(r[j + 1]);
            if (compound != null && !secondStartsNext) {
              t = compound;
              j++;
            }
          }
        }
      }
      out.writeCharCode(_sBase + (_compatInitial[c - 0x3131] * 21 + v) * 28 + t);
      i = j;
      continue;
    }
    out.writeCharCode(c);
    i++;
  }
  return out.toString();
}

// Step 5: "s e n d", "송 금 해", "1-2-3-4" read as one word.
final _spacedLetters = RegExp(
  r'(?<![\p{L}\p{N}])[\p{L}\p{N}](?:[ .\-][\p{L}\p{N}]){2,}(?![\p{L}\p{N}])',
  unicode: true,
);
final _letterSeparators = RegExp(r'[ .\-]');

/// Step 5: runs of three or more single letters or digits split by single
/// spaces, dots or hyphens are joined.
String joinSpacedLetters(String text) =>
    text.replaceAllMapped(_spacedLetters, (m) => m[0]!.replaceAll(_letterSeparators, ''));

// Step 6: views.
const _keptPunctuation = '.,!?:;\'"-/@£\$₩%';
final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isWordCharacter(int c) {
  if (isLooseJamo(c)) return false;
  if (isHangulSyllable(c)) return true;
  if (c < 0x80) {
    return (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);
  }
  return _letterOrDigit.hasMatch(String.fromCharCode(c));
}

String _spacedView(String text) {
  final out = StringBuffer();
  var lastSpace = true;
  for (final c in text.runes) {
    if (c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029) {
      // A line break ends a sentence.
      out.write(lastSpace ? '. ' : ' . ');
      lastSpace = true;
    } else if (_isWordCharacter(c) || _keptPunctuation.contains(String.fromCharCode(c))) {
      out.writeCharCode(c);
      lastSpace = false;
    } else if (!lastSpace) {
      out.write(' ');
      lastSpace = true;
    }
  }
  return out.toString().trim();
}

String _compactView(String text) {
  final out = StringBuffer();
  for (final c in text.runes) {
    if (_isWordCharacter(c)) out.writeCharCode(c);
  }
  return out.toString();
}

const _edgePunctuation = '.,!?:;\'"';
const _sentencePunctuation = '.!?';

List<TextToken> _tokensOf(String spaced) {
  if (spaced.isEmpty) return const [];
  final raw = spaced.split(' ');
  final tokens = <TextToken>[];
  for (var i = 0; i < raw.length; i++) {
    final word = raw[i];
    var start = 0;
    var end = word.length;
    while (start < end && _edgePunctuation.contains(word[start])) {
      start++;
    }
    var ends = false;
    while (end > start && _edgePunctuation.contains(word[end - 1])) {
      if (_sentencePunctuation.contains(word[end - 1])) ends = true;
      end--;
    }
    final text = word.substring(start, end);
    if (text.isEmpty) {
      // A lone mark: it ends the sentence of the word before it.
      if (word.split('').any(_sentencePunctuation.contains) && tokens.isNotEmpty) {
        final last = tokens.removeLast();
        tokens.add(TextToken(last.text, sentenceEnd: true));
      }
      continue;
    }
    tokens.add(TextToken(text, sentenceEnd: ends || i == raw.length - 1));
  }
  return tokens;
}
