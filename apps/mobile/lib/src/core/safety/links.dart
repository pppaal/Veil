// Finding links in a message and judging where they go, from the text alone:
// the phone never fetches, previews, resolves or expands a link.

import 'handle_lookalike.dart';
import 'link_brands.dart';
import 'link_hosts.dart';

/// How risky a link looks, in rising order.
enum LinkRisk {
  none,

  /// A company's own short link (naver.me, kko.to, me2.do).
  soft,

  /// A short link or an address that hides its host (an IP address, a login
  /// before the host, an unusual port, punycode, non-Latin letters).
  hidden,

  /// A domain made to look like a known brand's.
  lookalike,

  /// A link to an Android app file.
  appFile,
}

/// One link in a message.
class FoundLink {
  const FoundLink({
    required this.start,
    required this.end,
    required this.text,
    required this.uri,
    required this.host,
    required this.registrableDomain,
    required this.path,
    this.userInfo = '',
    this.port,
    this.nonAsciiHost = false,
    this.hidesHost = false,
  });

  /// Where the link sits in the text, in UTF-16 code units, end exclusive.
  final int start;
  final int end;

  /// The link as written.
  final String text;

  /// What opening it would open: the written URL, or https:// before a bare
  /// domain.
  final Uri uri;

  /// The host a browser opens (browserHost): %-escapes decoded, other
  /// full stops read as dots, lower case, and any label that is not plain
  /// ASCII in its xn-- form, as an address bar shows it. A host a browser
  /// refuses (an escape that does not decode, or a character no host may
  /// hold once decoded) is the host of [uri], escaped as there.
  final String host;

  /// The last two labels of [host], or three under an ending such as co.kr;
  /// all of [host] when a browser refuses it, so no decoded part of it reads
  /// as the domain.
  final String registrableDomain;

  /// Everything after the host, query included.
  final String path;
  final String userInfo;
  final int? port;

  /// The host as written holds a character outside ASCII: a non-Latin
  /// letter, or a full stop other than '.'.
  final bool nonAsciiHost;

  /// The address as written seems to name another host than the one it
  /// opens: a backslash right after the host (browsers read it as '/'), any
  /// %-escape in the host, a host a browser refuses, or a host that opens
  /// as another name.
  final bool hidesHost;

  @override
  String toString() => 'FoundLink($text)';
}

final _scheme = RegExp(r'https?://', caseSensitive: false);
final _bareDomain = RegExp(
  r'(?<![A-Za-z0-9@._\-/])((?:[A-Za-z0-9](?:[A-Za-z0-9\-]{0,61}[A-Za-z0-9])?\.)+'
  '(?:${(bareDomainEndings.toList()..sort((a, b) => b.length - a.length)).join('|')}))'
  r'(?![A-Za-z0-9\-]|\.[A-Za-z0-9])((?:/[\x21-\x7E]*)?)',
  caseSensitive: false,
);
final _ipv4 = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');

// A host browsers open as an IPv4 address although it is not written as
// four decimal numbers: one number (3232235777), hex or octal parts
// (0x7f.0.0.1, 0177.0.0.1) or fewer parts (127.1).
final _numericHost = RegExp(r'^(?:0x[0-9a-f]*|\d+)(?:\.(?:0x[0-9a-f]*|\d+)){0,3}$');

bool _isIpHost(String host) => _ipv4.hasMatch(host) || _numericHost.hasMatch(host) || host.startsWith('[');
final _hostLike = RegExp(r'(?<![A-Za-z0-9\-.])[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}(?![A-Za-z0-9\-])');

final _trailingDot = RegExp(r'\.$');

const _trailing = '.,!?;:\'"';
const _openerOf = {0x29: 0x28, 0x5D: 0x5B, 0x7D: 0x7B}; // ) ] } after ( [ {

bool _isAsciiLetterOrDigit(int c) => (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
bool _isAsciiUrlCharacter(int c) => c > 0x20 && c < 0x7F && c != 0x3C && c != 0x3E;
bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x3000 || c == 0xA0;
bool _isHangul(int c) => (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0x3131 && c <= 0x318E) || (c >= 0x1100 && c <= 0x11FF);

/// Every http(s) URL and bare domain in [text], in order.
List<FoundLink> findLinks(String text) {
  final links = <FoundLink>[];
  for (final m in _scheme.allMatches(text)) {
    if (links.isNotEmpty && m.start < links.last.end) continue;
    if (m.start > 0 && RegExp(r'[A-Za-z0-9]').hasMatch(text[m.start - 1])) continue;
    final link = _urlAt(text, m.start, m.end);
    if (link != null) links.add(link);
  }
  // The links found so far are in order and never overlap, so one index
  // that only moves forward finds the one a bare domain may overlap.
  final taken = [...links];
  var next = 0;
  for (final m in _bareDomain.allMatches(text)) {
    while (next < taken.length && taken[next].end <= m.start) {
      next++;
    }
    if (next < taken.length && m.end > taken[next].start) continue;
    final domain = m[1]!;
    var end = m.start + domain.length + _trimmedLength(m[2]!);
    final written = text.substring(m.start, end);
    final host = domain.toLowerCase();
    final path = written.substring(domain.length);
    if (!_takesBareDomain(domain, host, path)) continue;
    final uri = Uri.tryParse('https://$host$path');
    if (uri == null) continue;
    links.add(FoundLink(
      start: m.start,
      end: end,
      text: written,
      uri: uri,
      host: host,
      registrableDomain: registrableDomainOf(host),
      path: path,
    ));
  }
  links.sort((a, b) => a.start - b.start);
  return links;
}

// Endings on the bare-domain list that are also everyday words ("here.do u
// want it", "funny.lol"). A bare domain on one is taken only when it has a
// path, a www., more than two labels, a hyphen or digit in its name, or a
// host the checker knows (a brand's, a short-link service's, or a
// look-alike of a brand's).
const _wordLikeEndings = {
  'me', 'do', 'at', 'to', 'us', 'la', 'id', 'co', 'kim', 'lol', 'fun', 'top', 'bar', 'rest', 'work', //
  'live', 'link', 'page', 'shop', 'site', 'store', 'club', 'app', 'info', 'online', 'click', 'dev',
  'buzz', 'asia',
};

final _digitOrHyphen = RegExp(r'[\d\-]');

// Titles written before a name with a full stop and no space (Mr.Kim).
const _titlesBeforeName = {'mr', 'mrs', 'ms', 'mx', 'dr', 'prof', 'st', 'sr', 'jr', 'mt'};

bool _isTitleCase(String word) =>
    word.length >= 2 &&
    word[0] != word[0].toLowerCase() &&
    word.substring(1) == word.substring(1).toLowerCase() &&
    word.substring(1) != word.substring(1).toUpperCase();

/// Whether a bare domain [written] ([host] in lower case, [path] after it)
/// is a link and not two sentences with no space after the full stop.
bool _takesBareDomain(String written, String host, String path) {
  final lower = host.split('.');
  if (lower.length == 2 && _titlesBeforeName.contains(lower.first)) return false;
  if (!_wordLikeEndings.contains(lower.last)) return true;
  // Real bare domains are typed in lower case or all capitals; a Title-case
  // word (Do, Me, At, Kim) after the full stop starts the next sentence.
  if (_isTitleCase(written.split('.').last)) return false;
  if (path.length > 1 || lower.length > 2 || _digitOrHyphen.hasMatch(lower.first)) return true;
  return isBrandHost(host) || _hostIn(host, shortenerHosts) || _hostIn(host, softShortenerHosts) || isLookalikeHost(host);
}

// What follows an ideographic or full-width full stop in one address's
// authority: more of the host, or the next sentence. The rest of the
// authority is read once, not once per full stop, so each full stop costs
// only its own label and an address with thousands of them is still read
// in linear time.
class _HostRest {
  _HostRest(this.text);

  final String text;

  // The rest read last: where it stops (at '/', '?', '#', '\\' or a
  // character no host holds), where it ends less what ends the sentence and
  // any port, its last '.' or full stop, and whether its last label is a
  // known ending.
  var _stop = -1;
  var _end = 0;
  var _lastDot = -1;
  var _lastIsEnding = false;

  /// Whether the authority from [from], just after a full stop, is more of
  /// the host: '.'-separated labels whose last is a known ending, up to the
  /// end (login-check.xyz) or up to the next full stop
  /// (login-check.xyz。Thanks), not the next sentence's first word or
  /// number (Thanks, OK, 1234). A lone Title-case word that is also an
  /// ending (Do, Me, At) starts a sentence, as after a bare domain.
  bool goesOnAfter(int from) {
    if (from > _stop) _read(from);
    if (from > _lastDot) return from < _end && _endsInEnding(text.substring(from, _end));
    if (_lastIsEnding) return true;
    var next = from;
    while (next < _end && !isHostFullStop(text.codeUnitAt(next))) {
      next++;
    }
    return next < _end && _endsInEnding(text.substring(from, _trimmedEnd(text, from, next)));
  }

  void _read(int from) {
    var stop = from;
    while (stop < text.length) {
      final c = text.codeUnitAt(stop);
      if (c == 0x2F || c == 0x3F || c == 0x23 || c == 0x5C) break;
      if (!isHostFullStop(c) && !_isAsciiUrlCharacter(c)) break;
      stop++;
    }
    _stop = stop;
    // Less what ends the sentence (punctuation, closing brackets, full
    // stops), then less a port.
    var end = _trimmedEnd(text, from, stop, fullStops: true);
    var digits = end;
    while (digits > from && _isAsciiDigit(text.codeUnitAt(digits - 1))) {
      digits--;
    }
    if (digits > from && text.codeUnitAt(digits - 1) == 0x3A) end = digits - 1;
    _end = end;
    var dot = end - 1;
    while (dot >= from && !_isDot(text.codeUnitAt(dot))) {
      dot--;
    }
    _lastDot = dot < from ? -1 : dot;
    _lastIsEnding = bareDomainEndings.contains(text.substring(dot + 1, end).toLowerCase());
  }
}

// Whether [rest], '.'-separated labels, ends in a known ending; a lone
// Title-case word that is also an ending (Do, Me, At) does not.
bool _endsInEnding(String rest) {
  final labels = rest.split(_anyFullStop);
  final ending = labels.last.toLowerCase();
  if (labels.length == 1 && _wordLikeEndings.contains(ending) && _isTitleCase(labels.last)) return false;
  return bareDomainEndings.contains(ending);
}

final _anyFullStop = RegExp('[.\u3002\uFF0E\uFF61]');
bool _isDot(int c) => c == 0x2E || isHostFullStop(c);
bool _isAsciiDigit(int c) => c >= 0x30 && c <= 0x39;

// The length of [path] once trailing punctuation and unbalanced closing
// brackets are trimmed.
int _trimmedLength(String path) => _trimmedEnd(path, 0, path.length);

// The end of [text] from [start] to [end] once trailing punctuation and
// unbalanced closing brackets are trimmed, and with [fullStops] trailing
// ideographic and full-width full stops too. Brackets are counted once, so
// this takes linear time however many close the text.
int _trimmedEnd(String text, int start, int end, {bool fullStops = false}) {
  final counts = <int, int>{};
  for (var j = start; j < end; j++) {
    final c = text.codeUnitAt(j);
    if (_openerOf.containsKey(c) || _openerOf.containsValue(c)) counts[c] = (counts[c] ?? 0) + 1;
  }
  while (end > start) {
    final c = text.codeUnitAt(end - 1);
    final opener = _openerOf[c];
    if (_trailing.codeUnits.contains(c) || (fullStops && isHostFullStop(c))) {
      end--;
    } else if (opener != null && (counts[opener] ?? 0) <= counts[c]! - 1) {
      // As many of its opening bracket before it as of itself: it closes
      // nothing in the link.
      counts[c] = counts[c]! - 1;
      end--;
    } else {
      break;
    }
  }
  return end;
}

final _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);

// Whether the text from [start] to [end] ends in a '.' and two or more
// ASCII letters (a complete domain such as naver.com).
bool _endsInDotLetters(String text, int start, int end) {
  var letters = end;
  while (letters > start && _isAsciiLetter(text.codeUnitAt(letters - 1))) {
    letters--;
  }
  return end - letters >= 2 && letters > start && text.codeUnitAt(letters - 1) == 0x2E;
}

bool _isAsciiLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

FoundLink? _urlAt(String text, int start, int afterScheme) {
  final runes = text.codeUnits;
  // The authority: up to whitespace, '/', '?', '#' or '\\' (which browsers
  // and Uri read as '/').
  var i = afterScheme;
  var nonAscii = false;
  final rest = _HostRest(text);
  while (i < runes.length) {
    final c = runes[i];
    if (_isSpace(c) || c == 0x2F || c == 0x3F || c == 0x23 || c == 0x5C) break;
    // An ideographic or full-width full stop between two parts of a host
    // is a dot to a browser (naver.com。login-check.xyz opens
    // naver.com.login-check.xyz); one that ends a sentence ends the link
    // (naver.com。Thanks, example.org。OK, google.com。1234).
    if (isHostFullStop(c)) {
      final next = i + 1 < runes.length ? runes[i + 1] : 0;
      if (!_isAsciiLetterOrDigit(next) || !rest.goesOnAfter(i + 1)) break;
      nonAscii = true;
      i++;
      continue;
    }
    if (c >= 0x80) {
      // A Korean word glued after a complete domain ends the link; a host
      // that holds non-Latin letters itself is the trick. A character
      // outside the Basic Multilingual Plane (an emoji) is read whole, so a
      // link never ends between the two halves of its surrogate pair.
      final pair = _isHighSurrogate(c) && i + 1 < runes.length && _isLowSurrogate(runes[i + 1]);
      final code = pair ? 0x10000 + ((c - 0xD800) << 10) + (runes[i + 1] - 0xDC00) : c;
      if (_isHangul(code) && _endsInDotLetters(text, afterScheme, i)) break;
      if (i > afterScheme && !_letterOrNumber.hasMatch(String.fromCharCode(code))) break;
      nonAscii = true;
      i += pair ? 2 : 1;
      continue;
    } else if (!_isAsciiUrlCharacter(c)) {
      break;
    }
    i++;
  }
  final authorityEnd = i;
  // An address whose authority names no host is no link. That is decided
  // here, before the path is read: a text of thousands of such addresses
  // ("https:///" over and over) would otherwise read each path to the end
  // of the text, in quadratic time.
  // The authority is the one written, or that less what ends a sentence
  // when no path follows; neither naming a host means no link.
  final writtenAuthority = text.substring(afterScheme, authorityEnd);
  if (!_authorityNamesHost(writtenAuthority) &&
      !_authorityNamesHost(writtenAuthority.substring(0, _trimmedLength(writtenAuthority)))) {
    return null;
  }
  final backslash = i < runes.length && runes[i] == 0x5C;
  // The path: ASCII URL characters only.
  while (i < runes.length && _isAsciiUrlCharacter(runes[i])) {
    i++;
  }
  final rawPath = text.substring(authorityEnd, i);
  var authority = text.substring(afterScheme, authorityEnd);
  var path = rawPath.substring(0, _trimmedLength(rawPath));
  if (path.isEmpty) {
    final trimmed = _trimmedLength(authority);
    authority = authority.substring(0, trimmed);
  }
  if (authority.isEmpty) return null;
  final end = afterScheme + authority.length + path.length;
  final at = authority.lastIndexOf('@');
  final userInfo = at < 0 ? '' : authority.substring(0, at);
  var hostPort = authority.substring(at + 1);
  int? port;
  final portMatch = RegExp(r':(\d+)$').firstMatch(hostPort);
  var portOverflows = false;
  if (portMatch != null) {
    // A port too long for an int names no real port: the address hides
    // where it goes.
    port = int.tryParse(portMatch[1]!);
    portOverflows = port == null;
    hostPort = hostPort.substring(0, portMatch.start);
  }
  final writtenHost = hostPort.toLowerCase().replaceAll(_trailingDot, '');
  if (writtenHost.isEmpty) return null;
  final escaped = writtenHost.contains('%');
  final written = text.substring(start, end);
  final uri = Uri.tryParse(written);
  if (uri == null) return null;
  // A host a browser refuses is named as the address escapes it, never as
  // it decodes (evil.xyz%2F.naver.com is not naver.com).
  final opened = writtenHost.startsWith('[') ? writtenHost : browserHost(writtenHost);
  final host = opened ?? uri.host;
  if (host.isEmpty) return null;
  // The host that would open must be the host found; any other reading of
  // the address hides where it goes.
  final opens = uri.host.toLowerCase().replaceAll(_trailingDot, '');
  final mismatch =
      !nonAscii && !escaped && opens != (host.startsWith('[') ? host.substring(1, host.length - 1) : host);
  return FoundLink(
    start: start,
    end: end,
    text: written,
    uri: uri,
    host: host,
    registrableDomain: opened == null ? host : registrableDomainOf(host),
    path: path,
    userInfo: userInfo,
    port: port,
    nonAsciiHost: nonAscii,
    hidesHost: backslash || escaped || opened == null || mismatch || portOverflows,
  );
}

bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;

// Whether an authority (login, host and port as written) names a host: not
// a bare login or port ("@", ":"), and, for a host a browser refuses, one
// that Uri reads. [_urlAt] returns null for every authority this refuses,
// whatever path follows it.
bool _authorityNamesHost(String authority) {
  final hostPort = authority.substring(authority.lastIndexOf('@') + 1).replaceFirst(_portAtEnd, '');
  final written = hostPort.toLowerCase().replaceAll(_trailingDot, '');
  if (written.isEmpty) return false;
  if (written.startsWith('[') || browserHost(written) != null) return true;
  final uri = Uri.tryParse('https://$authority');
  return uri != null && uri.host.isNotEmpty;
}

final _portAtEnd = RegExp(r':\d+$');

/// The last two labels of [host], or the last three under a two-part
/// ending (co.kr, go.kr, co.uk ...). An IP address is its own domain.
String registrableDomainOf(String host) {
  if (_isIpHost(host)) return host;
  final labels = host.split('.');
  if (labels.length >= 3 && twoPartSuffixes.contains(labels.sublist(labels.length - 2).join('.'))) {
    return labels.sublist(labels.length - 3).join('.');
  }
  if (labels.length >= 2) return labels.sublist(labels.length - 2).join('.');
  return host;
}

/// Whether [host] is a brand's own or sister domain, or under one.
bool isBrandHost(String host) => linkBrands.any(
      (brand) => brand.domains.any((d) => host == d || host.endsWith('.$d')),
    );

/// The shared hosting ending [host] is under (anyone may put a site at
/// name.s3.amazonaws.com), or null.
String? sharedHostingSuffixOf(String host) {
  for (final suffix in sharedHostingSuffixes) {
    if (host.endsWith('.$suffix')) return suffix;
  }
  return null;
}

bool _hostIn(String host, Set<String> hosts) =>
    hosts.contains(host) || hosts.any((h) => host.endsWith('.$h'));

/// Whether the link is an app store page (Google Play, the App Store).
bool isAppStoreLink(FoundLink link) => appStoreHosts.contains(link.host);

/// Whether the host itself is hidden or odd: an IP address, a login before
/// it, a port other than 80 or 443, a %-escape, punycode, or a character
/// outside ASCII.
bool hasRiskyHost(FoundLink link) =>
    link.nonAsciiHost ||
    link.hidesHost ||
    link.userInfo.isNotEmpty ||
    (link.port != null && link.port != 80 && link.port != 443) ||
    _isIpHost(link.host) ||
    link.host.split('.').any((label) => label.startsWith('xn--'));

/// Whether the link opens an Android app file: its path as written, or as
/// it decodes (update.ap%6B is update.apk), ends in .apk, .xapk or .apks.
bool isAppFileLink(FoundLink link) {
  bool isApp(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.apk') || lower.endsWith('.xapk') || lower.endsWith('.apks');
  }

  if (isApp(link.path.split(RegExp(r'[?#]')).first)) return true;
  final path = link.uri.path;
  if (isApp(path)) return true;
  try {
    return isApp(Uri.decodeFull(path));
  } on ArgumentError {
    return false;
  } on FormatException {
    return false;
  }
}

bool isShortLink(FoundLink link) => _hostIn(link.host, shortenerHosts);
bool isSoftShortLink(FoundLink link) => _hostIn(link.host, softShortenerHosts);

/// The risk of one link: appFile; then hidden for a host written to read
/// as another (a backslash after it, a %-escape, a character outside
/// ASCII, punycode); then lookalike, any other hidden host, soft, none.
LinkRisk linkRiskOf(FoundLink link) {
  if (isAppFileLink(link)) return LinkRisk.appFile;
  if (link.nonAsciiHost || link.hidesHost || link.host.split('.').any((label) => label.startsWith('xn--'))) {
    return LinkRisk.hidden;
  }
  if (isLookalikeHost(link.host)) return LinkRisk.lookalike;
  if (isShortLink(link) || hasRiskyHost(link)) return LinkRisk.hidden;
  if (isSoftShortLink(link)) return LinkRisk.soft;
  return LinkRisk.none;
}

// 0/o, 1/l and rn/m read alike in a host.
String _foldHostLabel(String label) => label.replaceAll('rn', 'm').replaceAll('0', 'o').replaceAll('1', 'l');

final _brandTokens = {for (final b in linkBrands) ...b.tokens};

/// Whether [host] imitates a brand's domain (rules L1 to L6) without being
/// one of its own.
bool isLookalikeHost(String host) {
  if (isBrandHost(host)) return false;
  final padded = '.$host.';
  // L5: a government ending used inside another domain.
  if (host.contains('go-kr') || host.contains('gov-kr') || padded.substring(0, padded.length - 1).contains('.go.kr.')) {
    return true;
  }
  final registrable = registrableDomainOf(host);
  // Under a shared hosting ending every label before it is a name the site
  // chose (kakaobank-login.s3.amazonaws.com), each read as a domain name.
  final shared = sharedHostingSuffixOf(host);
  final suffixLabels = shared != null ? shared.split('.').length : registrable.split('.').length - 1;
  final labels = host.split('.');
  final nameLabels = labels.sublist(0, labels.length - suffixLabels);
  for (final label in nameLabels) {
    final parts = label.split('-').map(_foldHostLabel).toList();
    // L1: a brand token beside a scam word, split by hyphens.
    if (parts.length >= 2) {
      for (var i = 0; i < parts.length; i++) {
        if (!_brandTokens.contains(parts[i])) continue;
        for (var j = 0; j < parts.length; j++) {
          if (j != i && scamAffixes.contains(parts[j])) return true;
        }
      }
    }
    // L2: a brand token of five or more letters glued to a scam word.
    for (final part in {...parts, _foldHostLabel(label)}) {
      for (final token in _brandTokens) {
        if (token.length < 5 || part.length <= token.length) continue;
        if (part.startsWith(token) && scamAffixes.contains(part.substring(token.length))) return true;
        if (part.endsWith(token) && scamAffixes.contains(part.substring(0, part.length - token.length))) return true;
      }
    }
  }
  // L6: a brand's whole domain used as part of this one.
  if (_holdsBrandDomain(host)) return true;
  final names = shared != null ? nameLabels : [registrable.split('.').first];
  for (final first in names) {
    for (final brand in linkBrands) {
      for (final label in brand.labels) {
        // L3: one or two edits from a long brand name, of a similar length.
        if (label.length >= 6 && (first.length - label.length).abs() <= 2) {
          final allowed = label.length >= 9 ? 2 : 1;
          if (editDistance(first, label, limit: allowed) <= allowed) return true;
        }
        // L4: the same name once look-alike letters are folded.
        if (_foldHostLabel(first) == _foldHostLabel(label)) return true;
      }
    }
  }
  return false;
}

// L6: a brand's whole domain inside another host, with more after it
// (kbstar.com.verify.xyz, naver.com-login.top, kbstar-com.xyz). Only for
// domains whose name has three or more letters (not a.co or me.com, which
// sit inside ordinary hosts), and the hyphen form only when the ending has
// three or more too, so apple-co-op stays out.
final _brandDomainForms = <String>[
  for (final brand in linkBrands)
    for (final d in brand.domains)
      if (d.split('.').first.length >= 3) ...[
        d,
        if (d.split('.').last.length >= 3) d.replaceAll('.', '-'),
      ],
];

bool _holdsBrandDomain(String host) {
  for (final form in _brandDomainForms) {
    var at = host.indexOf(form);
    while (at >= 0) {
      final after = at + form.length;
      final startsLabel = at == 0 || host[at - 1] == '.' || host[at - 1] == '-';
      final moreAfter = after < host.length && (host[after] == '.' || host[after] == '-');
      if (startsLabel && moreAfter) return true;
      at = host.indexOf(form, at + 1);
    }
  }
  return false;
}

/// Whether every link in [links] is a brand's own domain and [text] names no
/// other host that [findLinks] did not take.
bool allLinksOfficial(String text, List<FoundLink> links) {
  if (links.isEmpty) return false;
  if (!links.every((l) => isBrandHost(l.host) && !hasRiskyHost(l))) return false;
  for (final m in _hostLike.allMatches(text)) {
    if (!links.any((l) => m.start < l.end && m.end > l.start)) return false;
  }
  return true;
}
