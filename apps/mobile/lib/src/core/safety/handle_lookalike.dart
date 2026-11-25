// Whether a handle imitates the handle of someone the user already trusts
// (a verified account, or one with a nickname saved for a week). Issued
// handles hold only a-z, 0-9, '.' and '_' (core/identity/issued_handle.dart),
// so the tricks left are look-alike characters, separators, suffixes and one
// changed letter.

import 'dart:math' as math;

/// An account a lookalike is checked against. The shape matches the records
/// ContactTrust.anchorsFor returns (records are structural).
typedef LookalikeAnchor = ({String userId, String handle, String? name, bool verified});

/// Which rule matched, strongest first (R0, R1, R4, R2, R3).
enum LookalikeRule {
  /// R0: the peer has the same nickname as another account.
  sameName,

  /// R1: the same handle once suffixes, digits and look-alike letters go.
  skeleton,

  /// R4: the anchor's nickname is a family word and the handle spells that
  /// family word in Latin letters (mom, eomma).
  kinName,

  /// R2: one edit away (two for a long handle).
  oneEdit,

  /// R3: the anchor's handle with up to four characters before or after it.
  affix,
}

class LookalikeMatch {
  const LookalikeMatch(this.anchor, this.rule, this.distance);

  final LookalikeAnchor anchor;
  final LookalikeRule rule;

  /// Edits between the two handles without separators.
  final int distance;

  @override
  String toString() => 'LookalikeMatch(${anchor.handle}, $rule, $distance)';
}

/// Lower case with '.' and '_' removed.
String normHandle(String handle) => handle.toLowerCase().replaceAll(RegExp(r'[._]'), '');

const _affixTokens = {
  'new', 'official', 'real', 'the', 'its', 'im', 'kr', 'korea', 'backup', 'temp', 'tmp', //
  'phone', 'mobile', 'app', 'mr', 'ms', 'me',
};
final _shortDigits = RegExp(r'^\d{1,4}$');
final _trailingDigits = RegExp(r'(?<!\d)\d{1,4}$');
const _gluedSuffixes = ['new', 'official', 'real'];
const _letterFolds = {
  '0': 'o', '1': 'l', 'i': 'l', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b', '9': 'g', //
};

/// The handle reduced to what a reader sees: affix words and short number
/// suffixes dropped, look-alike letters folded.
String handleSkeleton(String handle) {
  // 1. Lower case, split on separators.
  final tokens = handle.toLowerCase().split(RegExp(r'[._]')).where((t) => t.isNotEmpty).toList();
  // 2. Drop affix words at either end, and trailing short numbers.
  var changed = true;
  while (changed && tokens.length > 1) {
    changed = false;
    if (_affixTokens.contains(tokens.first)) {
      tokens.removeAt(0);
      changed = true;
    } else if (_affixTokens.contains(tokens.last) || _shortDigits.hasMatch(tokens.last)) {
      tokens.removeLast();
      changed = true;
    }
  }
  // 3. Join; strip a trailing digit run, then a glued new/official/real,
  // while three or more characters remain.
  var joined = tokens.join();
  final digits = _trailingDigits.firstMatch(joined);
  if (digits != null && digits.start >= 3) joined = joined.substring(0, digits.start);
  for (final suffix in _gluedSuffixes) {
    if (joined.endsWith(suffix) && joined.length - suffix.length >= 3) {
      joined = joined.substring(0, joined.length - suffix.length);
      break;
    }
  }
  // 4. Letter pairs that read as one letter, then look-alike characters.
  joined = joined.replaceAll('rn', 'm').replaceAll('vv', 'w').replaceAll('cl', 'd');
  final out = StringBuffer();
  for (final ch in joined.split('')) {
    out.write(_letterFolds[ch] ?? ch);
  }
  return out.toString();
}

// Family words in a nickname, by kin class, and how each class is spelled
// in a handle.
const _kinNameWords = <String, List<String>>{
  'mother': ['엄마', '어머니', '엄빠', 'mom', 'mum', 'mother'],
  'father': ['아빠', '아버지', '엄빠', 'dad', 'father'],
  'son': ['아들', 'son'],
  'daughter': ['딸', 'daughter'],
  'sibling': ['언니', '오빠', '누나', '형'],
  'grandparent': ['할머니', '할아버지', 'grandma', 'grandpa', 'nan'],
  'auntUncle': ['이모', '삼촌', '고모'],
};
const _kinHandles = <String, List<String>>{
  'mother': ['eomma', 'umma', 'omma', 'mom', 'mommy', 'mum', 'mummy', 'mama', 'mother', 'eomeoni'],
  'father': ['appa', 'dad', 'daddy', 'papa', 'father', 'abeoji'],
  'son': ['adeul'],
  'daughter': ['ttal', 'daughter'],
  'sibling': ['unni', 'eonni', 'oppa', 'nuna', 'noona', 'hyung', 'hyeong'],
  'grandparent': ['halmeoni', 'halmoni', 'grandma', 'granny', 'harabeoji', 'grandpa'],
  'auntUncle': ['imo', 'samchon', 'gomo'],
};
final _kinHandleSkeletons = {
  for (final e in _kinHandles.entries) e.key: {for (final h in e.value) handleSkeleton(h)},
};

/// The kin classes a nickname names ("엄마", "Mom", "우리 엄마", "막내딸").
Set<String> kinClassesOfName(String name) {
  final lower = name.toLowerCase();
  final words = lower.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty);
  final classes = <String>{};
  for (final e in _kinNameWords.entries) {
    for (final word in e.value) {
      final latin = RegExp(r'^[a-z]+$').hasMatch(word);
      // Korean: the word alone or at the end of a word (우리엄마, 막내딸), or
      // at the start when it has two syllables (엄마폰; 딸기 is no daughter).
      final found = latin
          ? words.contains(word)
          : words.any((w) => w == word || w.endsWith(word) || (word.length >= 2 && w.startsWith(word)));
      if (found) {
        classes.add(e.key);
      }
    }
  }
  return classes;
}

/// Whether the handle spells a family word in Latin letters (mom_new,
/// eomma2). "son" and "nan" are left out: 손 is a common surname and Nan a
/// common name.
bool isKinHandle(String handle) {
  final skeleton = handleSkeleton(handle);
  return _kinHandleSkeletons.values.any((set) => set.contains(skeleton));
}

/// Optimal string alignment distance (insertions, deletions, substitutions
/// and swaps of two adjacent characters), stopping early above [limit].
int editDistance(String a, String b, {int limit = 1 << 30}) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  final n = a.length, m = b.length;
  var prev2 = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (j) => j);
  for (var i = 1; i <= n; i++) {
    final cur = List<int>.filled(m + 1, 0);
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= m; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        v = math.min(v, prev2[j - 2] + 1);
      }
      cur[j] = v;
      rowMin = math.min(rowMin, v);
    }
    if (rowMin > limit) return limit + 1;
    prev2 = prev;
    prev = cur;
  }
  return prev[m];
}

const _confusable = <String>{'o0', '0o', 'l1', '1l', 'li', 'il', '1i', 'i1', 'e3', '3e', 'a4', '4a', 's5', '5s', 't7', '7t', 'b8', '8b', 'g9', '9g'};

// R2 for a short anchor: exactly one adjacent swap, one confusable
// substitution, or one repeated character added or dropped.
bool _oneLookalikeEdit(String h, String a) {
  if (h.length == a.length) {
    final diffs = [for (var i = 0; i < h.length; i++) if (h[i] != a[i]) i];
    if (diffs.length == 1) return _confusable.contains('${h[diffs[0]]}${a[diffs[0]]}');
    return diffs.length == 2 &&
        diffs[1] == diffs[0] + 1 &&
        h[diffs[0]] == a[diffs[1]] &&
        h[diffs[1]] == a[diffs[0]];
  }
  final longer = h.length > a.length ? h : a;
  final shorter = h.length > a.length ? a : h;
  if (longer.length != shorter.length + 1) return false;
  for (var i = 0; i < longer.length; i++) {
    if (longer.substring(0, i) + longer.substring(i + 1) != shorter) continue;
    final repeated = (i > 0 && longer[i - 1] == longer[i]) || (i + 1 < longer.length && longer[i + 1] == longer[i]);
    if (repeated) return true;
  }
  return false;
}

String _fold(String s) => s.trim().toLowerCase();

/// The strongest way [handle] imitates one of [anchors], or null. Anchors
/// with the peer's own user id or with exactly [handle] are skipped (one
/// handle on two accounts is the existing hold path). Nothing is checked for
/// a verified peer.
LookalikeMatch? findLookalike(
  String handle,
  String? peerName,
  Iterable<LookalikeAnchor> anchors, {
  String? peerUserId,
  bool peerVerified = false,
}) {
  if (peerVerified) return null;
  final h = handle.toLowerCase();
  final hNorm = normHandle(h);
  final hSkeleton = handleSkeleton(h);
  final matches = <LookalikeMatch>[];
  for (final a in anchors) {
    if (peerUserId != null && a.userId == peerUserId) continue;
    final aHandle = a.handle.toLowerCase();
    if (aHandle == h) continue;
    final aNorm = normHandle(aHandle);
    final distance = editDistance(hNorm, aNorm);
    LookalikeRule? rule;
    if (peerName != null && a.name != null && _fold(peerName).isNotEmpty && _fold(peerName) == _fold(a.name!)) {
      rule = LookalikeRule.sameName;
    } else if (hSkeleton.length >= 3 && hSkeleton == handleSkeleton(aHandle)) {
      rule = LookalikeRule.skeleton;
    } else if (a.name != null && kinClassesOfName(a.name!).any((c) => _kinHandleSkeletons[c]!.contains(hSkeleton))) {
      rule = LookalikeRule.kinName;
    } else if (aNorm.length >= 4 &&
        ((aNorm.length >= 12 && distance <= 2) ||
            (aNorm.length >= 8 && distance <= 1) ||
            _oneLookalikeEdit(hNorm, aNorm))) {
      rule = LookalikeRule.oneEdit;
    } else if (aNorm.length >= 4 &&
        hNorm.length > aNorm.length &&
        hNorm.length - aNorm.length <= 4 &&
        (hNorm.startsWith(aNorm) || hNorm.endsWith(aNorm))) {
      rule = LookalikeRule.affix;
    }
    if (rule != null) matches.add(LookalikeMatch(a, rule, distance));
  }
  if (matches.isEmpty) return null;
  matches.sort((x, y) {
    final byRule = x.rule.index - y.rule.index;
    if (byRule != 0) return byRule;
    if (x.anchor.verified != y.anchor.verified) return x.anchor.verified ? -1 : 1;
    final byDistance = x.distance - y.distance;
    if (byDistance != 0) return byDistance;
    return x.anchor.handle.compareTo(y.anchor.handle);
  });
  return matches.first;
}
