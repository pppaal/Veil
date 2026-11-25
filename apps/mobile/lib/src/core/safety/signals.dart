// The signals the scam rules are built from: what one message holds (an ask,
// money, an account number, a family word, a link ...), read from its
// normalised views with the matching rules of each language.

import 'links.dart';
import 'rules_en.dart';
import 'rules_ko.dart';
import 'text_normalizer.dart';

enum Signal {
  ask,
  money,
  amount,
  account,
  thirdParty,
  secrecy,
  callAvoid,
  urgency,
  gift,
  pinBack,
  code,
  mistake,
  id,
  cardSecret,
  photo,
  remoteName,
  remoteWord,
  install,
  link,

  /// A link that is not an app store page (the authority rule's LINK).
  linkOutsideStores,
  apk,
  shortener,
  softShortener,
  lookalikeDomain,
  riskyHost,
  officialDomain,
  kin,
  socialKin,
  kinVocative,
  meClaim,
  deviceStory,
  newAccountClaim,
  delivery,
  addressProblem,
  fee,
  bankPretext,
  phoneToCall,
  gov,
  invest,
  guarantee,
  highReturn,
  feeFirst,
  authorityStrong,
  authorityWeak,

  /// AUTHORITY_STRONG from an earlier text of the same sender.
  authorityCarried,
  safeAccount,
  // Derived.
  moneyAsk,
  giftAsk,
  codeAsk,
  idAsk,
  remote,
}

/// Signals that ask the reader to do something.
const actionSignals = {
  Signal.moneyAsk,
  Signal.account,
  Signal.giftAsk,
  Signal.codeAsk,
  Signal.idAsk,
  Signal.remote,
  Signal.install,
  Signal.link,
  Signal.safeAccount,
};

/// Signals that tell a story and carry over from earlier texts.
const storySignals = {
  Signal.kin,
  Signal.kinVocative,
  Signal.meClaim,
  Signal.deviceStory,
  Signal.newAccountClaim,
  Signal.callAvoid,
  Signal.urgency,
  Signal.secrecy,
  Signal.authorityStrong,
};

class RiskSignals {
  const RiskSignals(this.present);

  final Set<Signal> present;

  bool has(Signal signal) => present.contains(signal);

  /// The story signals, AUTHORITY_STRONG turned into AUTHORITY_CARRIED.
  Set<Signal> get story => {
        for (final s in present)
          if (storySignals.contains(s)) s == Signal.authorityStrong ? Signal.authorityCarried : s,
      };

  @override
  String toString() => 'RiskSignals(${present.map((s) => s.name).join(', ')})';
}

// Matching -------------------------------------------------------------------

bool _endsInConsonant(String word) {
  final c = word.codeUnitAt(word.length - 1);
  return c >= 0xAC00 && c <= 0xD7A3 && (c - 0xAC00) % 28 != 0;
}

/// Whether [token] is [word], or [word] with a particle or copula after it
/// (chosen by whether [word] ends in a consonant). 이체 also matches when 해,
/// 하, 했 or 할 follows (이체해줘, 이체하세요).
bool matchesShortWord(String token, String word) {
  if (token == word) return true;
  if (!token.startsWith(word)) return false;
  final rest = token.substring(word.length);
  if (word == '이체' && (rest.startsWith('해') || rest.startsWith('하') || rest.startsWith('했') || rest.startsWith('할'))) {
    return true;
  }
  if (koParticlesAfterEither.contains(rest)) return true;
  return _endsInConsonant(word) ? koParticlesAfterConsonant.contains(rest) : koParticlesAfterVowel.contains(rest);
}

/// Whether a whole word of [text] (joined or loose) is [word] with an
/// optional particle.
bool hasShortWord(NormalizedText text, String word) =>
    text.tokens.any((t) => matchesShortWord(t.text, word)) ||
    text.looseTokens.any((t) => matchesShortWord(t.text, word)) ||
    (word.length == 2 && splitShortWords(text).any((t) => matchesShortWord(t, word)));

final _innerMarks = RegExp(r'[.\-]');

/// A two-syllable word split by a space, a dot, a hyphen or an emoji
/// ("엄 마", "엄.마", "이💰체해줘"), read whole: two loose words joined when
/// the first is one Hangul syllable, and words with an inner dot or hyphen
/// taken out.
Iterable<String> splitShortWords(NormalizedText text) sync* {
  final tokens = text.looseTokens;
  for (var i = 0; i + 1 < tokens.length; i++) {
    final a = tokens[i].text;
    final b = tokens[i + 1].text;
    if (a.length == 1 && !tokens[i].sentenceEnd && isHangulSyllable(a.codeUnitAt(0)) && b.isNotEmpty) {
      if (isHangulSyllable(b.codeUnitAt(0))) yield '$a$b';
    }
  }
  for (final t in tokens) {
    if (t.text.contains('.') || t.text.contains('-')) yield t.text.replaceAll(_innerMarks, '');
  }
}

/// Whether [text] holds a Korean word of [words]: a short word as a whole
/// word, any other in the compact view.
bool hasKoreanWord(NormalizedText text, Iterable<String> words) =>
    words.any((w) => koShortTokens.contains(w) ? hasShortWord(text, w) : text.compact.contains(w));

String _phrase(String p) => RegExp.escape(p).replaceAll("'", "'?").replaceAll(' ', ' ?');

/// A pattern matching any of [phrases] as whole words of the spaced view.
RegExp englishPattern(Iterable<String> phrases) =>
    RegExp('(?<![a-z0-9])(?:${phrases.map(_phrase).join('|')})(?![a-z0-9])');

bool _english(NormalizedText text, RegExp pattern) =>
    pattern.hasMatch(text.spaced) || (text.looseSpaced != text.spaced && pattern.hasMatch(text.looseSpaced));

// English patterns, built once.
final _enKin = englishPattern(enKin);
final _enMeClaim = englishPattern(enMeClaim);
final _enDeviceStory = englishPattern(enDeviceStory);
final _enNewAccountClaim = englishPattern(enNewAccountClaim);
final _enCallAvoid = englishPattern(enCallAvoid);
final _enMoney = englishPattern(enMoney);
final _enUrgency = englishPattern(enUrgency);
final _enSecrecy = englishPattern(enSecrecy);
final _enThirdParty = englishPattern(enThirdParty);
final _enAsk = englishPattern(enAsk);
final _enPlease = RegExp('(?<![a-z])please,?(?: [^ ]+){0,2} (?:${enPleaseVerbs.join('|')})(?![a-z])');
// An opening verb asks only with its object right after it: "send me",
// "transfer the money", "buy 3 gift cards", "pay \$200"; "Pay day is
// Friday" and "Buy 2 get 1 free" do not.
final _enImperative = RegExp(
  '^(?:${enImperatives.join('|')}) '
  '(?:(?:${enImperativeObjects.map(_phrase).join('|')})(?![a-z])'
  '|(?:(?:${enImperativeDeterminers.join('|')}|\\d+|${enNumberWords.join('|')}) )?'
  '(?:(?:${enImperativeBrands.join('|')}) )?(?:${enImperativeNouns.map(_phrase).join('|')})(?![a-z])'
  '|[\$£₩] ?\\d'
  '|\\d[\\d,.]* ?k? ?(?:${enCurrencyWords.join('|')}|\\\$|£|₩|원|만|천)'
  '|(?:${enNumberWords.join('|')})(?:[ -](?:${enNumberWords.join('|')}|and))* (?:${enCurrencyWords.join('|')})(?![a-z]))',
);
final _enThanksBefore = RegExp('(?:${enThanks.map(_phrase).join('|')})(?: [^ ]+){0,2} ?\$');
final _enGift = englishPattern(enGift);
final _enPinBack = englishPattern(enPinBack);
final _enCode = englishPattern(enCode);
final _enMistake = englishPattern(enMistake);
final _enId = englishPattern(enId);
final _enPhoto = englishPattern(enPhoto);
final _enRemoteName = englishPattern(enRemoteName);
final _enRemoteWord = englishPattern(enRemoteWord);
final _enInstall = englishPattern(enInstall);
final _enDelivery = englishPattern(enDelivery);
final _enAddressProblem = englishPattern(enAddressProblem);
final _enFee = englishPattern(enFee);
final _enBankPretext = englishPattern(enBankPretext);
final _enAuthorityStrong = englishPattern(enAuthorityStrong);
final _enAuthorityWeak = englishPattern(enAuthorityWeak);
final _enSafeAccount = englishPattern(enSafeAccount);
final _enGov = englishPattern(enGov);
final _enInvest = englishPattern(enInvest);
final _enGuarantee = englishPattern(enGuarantee);
final _enFeeFirst = englishPattern(enFeeFirst);
final _enNotAccountNear = englishPattern(enNotAccountNear);
final _enAccountWord = englishPattern(['account']);
final _returnWords = '(?:${[...koReturnWords, ...enReturnWords].join('|')})';
final _highReturn = RegExp('$_returnWords\\D{0,6}\\d+(?:\\.\\d+)?\\s?%|(?<![\\d.])\\d+(?:\\.\\d+)?\\s?%\\s?(?:의\\s?)?$_returnWords');

// Amounts.
const _numerals = '일이삼사오육칠팔구십백천만억';
final _koNumeralWon = RegExp(
  '(?<![가-힣\\d,])(\\d[\\d,]*\\s?)?([$_numerals](?:\\s?[$_numerals])*)\\s?원(?!래|본|룸|장|망|하는)',
);
final _koDigitWon = RegExp(r'(?<![\d,.])\d[\d,.]*\s?(?:만|천|백|억)?\s?원(?!래|본|룸|장|망|하는)');
final _koDigitMan = RegExp(
  '(?<![\\d,.])\\d[\\d,.]*\\s?(?:만|천|억)(?!\\s?원)(?!\\s?(?:${koCounters.join('|')}))',
);
final _wonSign = RegExp(r'₩\s?\d|(?<![\d,.])\d[\d,.]*\s?₩');
final _enAmount = RegExp(
  '[\$£]\\s?\\d|(?<![\\d,.])\\d[\\d,.]*\\s?k?\\s?(?:${enCurrencyWords.join('|')}|\\\$|£)(?![a-z])|'
  '(?<![a-z])(?:${enNumberWords.join('|')})(?:[ -](?:${enNumberWords.join('|')}|and))*'
  ' (?:${enCurrencyWords.join('|')})(?![a-z])',
);

// Account numbers and phone numbers.
// Digit runs that may be an account number: groups joined by hyphens or
// spaces (110-123-456789), or one unbroken run of 10 to 14 digits
// (110123456789), as people often type them.
final _digitGroups = RegExp(r'(?<![\d\-])(?:\d{10,14}|\d{2,8}(?:[\- ]\d{1,8}){0,4})(?!\d)');
final _koPhoneShape = RegExp(r'^(?:01[016789][\- ]?\d{3,4}[\- ]?\d{4}|0\d{1,2}[\- ]\d{3,4}[\- ]\d{4})$');
final _dateShape = RegExp(r'\d{4}-\d{1,2}-\d{1,2}');
final _iban = RegExp(r'(?<![a-z0-9])[a-z]{2}\d{2}(?: ?[a-z0-9]{4}){2,7}(?: ?[a-z0-9]{1,3})?(?![a-z0-9])');
final _sortCode = RegExp(r'(?<![\d\-])\d{2}-\d{2}-\d{2}(?![\d\-])');
final _eightDigits = RegExp(r'(?<![\d\-])\d{8}(?![\d\-])');
final _phoneToCall = RegExp(
  r'(?<![\d\-])(?:01[016789][\- ]?\d{3,4}[\- ]?\d{4}|0\d{1,2}[\- ]\d{3,4}[\- ]\d{4}|1[5-9]\d{2}[\- ]\d{4}'
  r'|\+\d{1,3}[\- ]?\d{1,4}(?:[\- ]?\d{2,4}){2,3}|1[\- ]8\d{2}[\- ]\d{3}[\- ]\d{4}'
  r'|0800[\- ]?\d{3}[\- ]?\d{3,4}|\d{3} \d{3}-\d{4})(?![\d\-])',
);
final _appFileName = RegExp(r'(?<![a-z0-9_\-])[a-z0-9_\-]+\.(?:apk|xapk|apks)(?![a-z0-9])');

// A piece of the spaced view with its spaces and kept punctuation removed.
String _compactOf(String spaced) => spaced.replaceAll(RegExp('[ .,!?:;\'"\\-/@£\$₩%]'), '');

bool _hasAccountNumber(NormalizedText text) {
  final spaced = text.spaced;
  for (final m in _digitGroups.allMatches(spaced)) {
    final run = m[0]!.trim();
    final digits = run.replaceAll(RegExp(r'[\- ]'), '');
    if (digits.length < 10 || digits.length > 14) continue;
    if (_koPhoneShape.hasMatch(run) || RegExp(r'^01[016789]\d{7,8}$').hasMatch(digits)) continue;
    if (_dateShape.hasMatch(run)) continue;
    final after = spaced.substring(m.end).trimLeft();
    if (after.startsWith('원') || after.startsWith(':') || after.startsWith('만원')) continue;
    if (m.start > 0 && spaced[m.start - 1] == '₩') continue;
    final window = spaced.substring(m.start < 20 ? 0 : m.start - 20, m.end + 20 > spaced.length ? spaced.length : m.end + 20);
    final windowCompact = _compactOf(window);
    if (koNotAccountNear.any(windowCompact.contains) || _enNotAccountNear.hasMatch(window)) continue;
    final bank = koDistinctiveBanks.any(windowCompact.contains) ||
        koPlainBanks.any((b) => koBankJoins.any((j) => windowCompact.contains('$b$j'))) ||
        koAccountWords.any(windowCompact.contains) ||
        _enAccountWord.hasMatch(window);
    if (bank) return true;
  }
  for (final m in _iban.allMatches(spaced)) {
    final length = m[0]!.replaceAll(' ', '').length;
    if (length >= 15 && length <= 34) return true;
  }
  return _sortCode.hasMatch(spaced) && _eightDigits.hasMatch(spaced);
}

bool _hasAmount(NormalizedText text) {
  final spaced = text.spaced;
  for (final m in _koNumeralWon.allMatches(spaced)) {
    final numerals = m[2]!.replaceAll(' ', '');
    if (m[1] != null || numerals.length >= 2 || RegExp('[십백천만억]').hasMatch(numerals)) return true;
  }
  return _koDigitWon.hasMatch(spaced) ||
      _koDigitMan.hasMatch(spaced) ||
      _wonSign.hasMatch(spaced) ||
      _enAmount.hasMatch(spaced);
}

bool _koreanAsk(List<TextToken> tokens) {
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final w = token.text;
    final next = i + 1 < tokens.length ? tokens[i + 1].text : null;
    if (next != null && koThanks.any(next.startsWith)) continue;
    if (koGreetingAsks.any(w.startsWith)) continue;
    if (koAskEndings.any(w.endsWith)) return true;
    if (token.sentenceEnd) {
      if (koAskSentenceFinal.any(w.endsWith)) return true;
      if (koMoneyVerbNouns.any((n) => w.endsWith('$n해'))) return true;
      if (w == '해' && i > 0 && koMoneyVerbNouns.any(tokens[i - 1].text.endsWith)) return true;
    }
    if (w == '좀' && next != null && koAskAfterJom.any(next.startsWith)) return true;
  }
  return false;
}

bool _englishAsk(String spaced) {
  for (final m in _enAsk.allMatches(spaced)) {
    final before = spaced.substring(m.start < 30 ? 0 : m.start - 30, m.start);
    if (!_enThanksBefore.hasMatch(before)) return true;
  }
  if (_enPlease.hasMatch(spaced)) return true;
  for (final sentence in spaced.split(RegExp(r'[.!?] '))) {
    if (_enImperative.hasMatch(sentence.trimLeft())) return true;
  }
  return false;
}

bool _hasAsk(NormalizedText text) =>
    _koreanAsk(text.tokens) ||
    _koreanAsk(text.looseTokens) ||
    koAskCompact.any(text.compact.contains) ||
    _englishAsk(text.spaced) ||
    (text.looseSpaced != text.spaced && _englishAsk(text.looseSpaced));

bool _startsWithKin(List<TextToken> tokens) {
  var i = 0;
  if (tokens.isNotEmpty && (koGreetings.contains(tokens[0].text) || enGreetings.contains(tokens[0].text))) i = 1;
  if (i >= tokens.length) return false;
  var first = tokens[i].text.replaceAll(_innerMarks, '');
  // A two-syllable kin word split in two ("엄 마 나야").
  if (first.length == 1 && i + 1 < tokens.length && isHangulSyllable(first.codeUnitAt(0)) && !koKin.contains(first)) {
    first = '$first${tokens[i + 1].text}';
  }
  // Called by name: the word alone or with the calling particle 아 or 야
  // (아들아); 아빠한테 is about someone, not to them.
  return koKin.any((k) => first == k || first == '$k아' || first == '$k야') || enKin.contains(first);
}

bool _hasDeviceStory(NormalizedText text) {
  final phone = hasShortWord(text, '폰') || koPhoneWords.any(text.compact.contains);
  if (phone && koPhoneTrouble.any(text.compact.contains)) return true;
  final glued = [...text.tokens, ...text.looseTokens].any((t) => koGluedDevice.any(t.text.startsWith));
  return glued || koDeviceStory.any(text.compact.contains) || _english(text, _enDeviceStory);
}

bool _hasCardSecret(String compact) {
  for (final word in koCardSecretWord) {
    var at = compact.indexOf(word);
    while (at >= 0) {
      final from = at < 10 ? 0 : at - 10;
      final to = at + word.length + 10 > compact.length ? compact.length : at + word.length + 10;
      final window = compact.substring(from, to);
      if (koCardSecretNear.any(window.contains)) return true;
      at = compact.indexOf(word, at + 1);
    }
  }
  return false;
}

/// Every signal in [text]. Links are read from the text before look-alike
/// letters are folded, so a host written in Cyrillic stays odd.
RiskSignals detectSignals(String text) {
  final limited = text.length > maxCheckedLength ? text.substring(0, maxCheckedLength) : text;
  final t = normalizeText(limited);
  final compact = t.compact;
  final linkText = foldWidth(limited);
  final links = findLinks(linkText);
  final s = <Signal>{};
  void mark(Signal signal, bool present) {
    if (present) s.add(signal);
  }

  bool ko(List<String> words) => hasKoreanWord(t, words);
  bool en(RegExp pattern) => _english(t, pattern);

  mark(Signal.ask, _hasAsk(t));
  mark(Signal.money, ko(koMoney) || en(_enMoney));
  mark(Signal.amount, _hasAmount(t));
  mark(Signal.account, _hasAccountNumber(t));
  mark(Signal.thirdParty, ko(koThirdParty) || en(_enThirdParty));
  mark(Signal.secrecy, ko(koSecrecy) || en(_enSecrecy));
  mark(Signal.callAvoid, ko(koCallAvoid) || en(_enCallAvoid));
  mark(Signal.urgency, ko(koUrgency) || en(_enUrgency));
  mark(Signal.gift, ko(koGift) || en(_enGift));
  mark(Signal.pinBack, ko(koPinBack) || en(_enPinBack));
  mark(Signal.code, ko(koCode) || en(_enCode));
  mark(Signal.mistake, ko(koMistake) || en(_enMistake));
  mark(Signal.id, ko(koId) || en(_enId));
  mark(Signal.cardSecret, _hasCardSecret(compact));
  mark(Signal.photo, ko(koPhoto) || en(_enPhoto));
  mark(Signal.remoteName, ko(koRemoteName) || en(_enRemoteName));
  mark(Signal.remoteWord, ko(koRemoteWord) || en(_enRemoteWord));
  mark(Signal.install, ko(koInstall) || en(_enInstall));

  mark(Signal.link, links.isNotEmpty);
  mark(Signal.linkOutsideStores, links.any((l) => !isAppStoreLink(l)));
  mark(Signal.apk, links.any(isAppFileLink) || _appFileName.hasMatch(t.folded));
  mark(Signal.shortener, links.any(isShortLink));
  mark(Signal.softShortener, links.any(isSoftShortLink));
  mark(Signal.lookalikeDomain, links.any((l) => isLookalikeHost(l.host)));
  mark(Signal.riskyHost, links.any(hasRiskyHost));
  mark(Signal.officialDomain, allLinksOfficial(linkText, links));

  mark(Signal.kin, ko(koKin) || en(_enKin));
  mark(Signal.socialKin, ko(koSocialKin));
  mark(Signal.kinVocative, _startsWithKin(t.tokens) || _startsWithKin(t.looseTokens));
  mark(
    Signal.meClaim,
    [...t.tokens, ...t.looseTokens].any((w) => koMeClaim.contains(w.text)) ||
        splitShortWords(t).any(koMeClaim.contains) ||
        en(_enMeClaim),
  );
  mark(Signal.deviceStory, _hasDeviceStory(t));
  mark(Signal.newAccountClaim, ko(koNewAccountClaim) || en(_enNewAccountClaim));

  mark(Signal.delivery, ko(koDelivery) || en(_enDelivery));
  mark(Signal.addressProblem, ko(koAddressProblem) || en(_enAddressProblem));
  mark(Signal.fee, ko(koFee) || en(_enFee));
  mark(Signal.bankPretext, ko(koBankPretext) || en(_enBankPretext));
  mark(Signal.phoneToCall, _phoneToCall.hasMatch(t.spaced));
  mark(Signal.gov, ko(koGov) || en(_enGov));
  mark(Signal.invest, ko(koInvest) || koCoin.hasMatch(compact) || en(_enInvest));
  mark(Signal.guarantee, ko(koGuarantee) || en(_enGuarantee));
  mark(Signal.highReturn, _highReturn.hasMatch(t.spaced));
  mark(Signal.feeFirst, ko(koFeeFirst) || en(_enFeeFirst));

  final strong = ko(koAuthorityStrong) || en(_enAuthorityStrong);
  mark(Signal.authorityStrong, strong);
  mark(Signal.authorityWeak, strong && (ko(koAuthorityWeak) || en(_enAuthorityWeak)));
  mark(Signal.safeAccount, ko(koSafeAccount) || en(_enSafeAccount));

  // Derived.
  final ask = s.contains(Signal.ask);
  mark(Signal.moneyAsk, ask && (s.contains(Signal.money) || s.contains(Signal.amount)));
  mark(Signal.giftAsk, s.contains(Signal.gift) && (ask || s.contains(Signal.pinBack)));
  mark(Signal.codeAsk, s.contains(Signal.code) && ask);
  mark(Signal.idAsk, (s.contains(Signal.id) || s.contains(Signal.cardSecret)) && ask);
  mark(
    Signal.remote,
    (s.contains(Signal.remoteName) && (ask || s.contains(Signal.install))) ||
        (s.contains(Signal.remoteWord) && s.contains(Signal.install)),
  );
  return RiskSignals(s);
}
