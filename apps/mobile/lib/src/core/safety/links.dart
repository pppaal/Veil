// Finding links in a message and judging where they go, from the text alone:
// the phone never fetches, previews, resolves or expands a link.

import 'handle_lookalike.dart';
import 'link_brands.dart';

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

  /// Lower case, as written (non-Latin letters kept).
  final String host;

  /// The last two labels of the host, or three under an ending such as co.kr.
  final String registrableDomain;

  /// Everything after the host, query included.
  final String path;
  final String userInfo;
  final int? port;
  final bool nonAsciiHost;

  /// The address as written seems to name another host than the one it
  /// opens: a backslash right after the host (browsers read it as '/'), or a
  /// host written with escapes that opens as another name.
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
const _closers = {')': '(', ']': '[', '}': '{'};

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
  final taken = [...links];
  for (final m in _bareDomain.allMatches(text)) {
    if (taken.any((l) => m.start < l.end && m.end > l.start)) continue;
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

// The length of [path] once trailing punctuation and unbalanced closing
// brackets are trimmed.
int _trimmedLength(String path) {
  var end = path.length;
  while (end > 0) {
    final last = path[end - 1];
    if (_trailing.contains(last)) {
      end--;
      continue;
    }
    final opener = _closers[last];
    if (opener != null) {
      final body = path.substring(0, end - 1);
      final opens = opener.allMatches(body).length;
      final closes = last.allMatches(body).length;
      if (opens <= closes) {
        end--;
        continue;
      }
    }
    break;
  }
  return end;
}

FoundLink? _urlAt(String text, int start, int afterScheme) {
  final runes = text.codeUnits;
  // The authority: up to whitespace, '/', '?', '#' or '\\' (which browsers
  // and Uri read as '/').
  var i = afterScheme;
  var nonAscii = false;
  while (i < runes.length) {
    final c = runes[i];
    if (_isSpace(c) || c == 0x2F || c == 0x3F || c == 0x23 || c == 0x5C) break;
    if (c >= 0x80) {
      final asciiHost = text.substring(afterScheme, i);
      // A Korean word glued after a complete domain ends the link; a host
      // that holds non-Latin letters itself is the trick.
      if (_isHangul(c) && RegExp(r'\.[A-Za-z]{2,}$').hasMatch(asciiHost)) break;
      if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(String.fromCharCode(c)) && asciiHost.isNotEmpty) break;
      nonAscii = true;
    } else if (!_isAsciiUrlCharacter(c)) {
      break;
    }
    i++;
  }
  final authorityEnd = i;
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
  if (portMatch != null) {
    port = int.parse(portMatch[1]!);
    hostPort = hostPort.substring(0, portMatch.start);
  }
  final host = hostPort.toLowerCase().replaceAll(_trailingDot, '');
  if (host.isEmpty) return null;
  final written = text.substring(start, end);
  final uri = Uri.tryParse(written);
  if (uri == null) return null;
  // The host that would open must be the host found; any other reading of
  // the address hides where it goes.
  final opens = uri.host.toLowerCase().replaceAll(_trailingDot, '');
  final mismatch = !nonAscii && opens != (host.startsWith('[') ? host.substring(1, host.length - 1) : host);
  return FoundLink(
    start: start,
    end: end,
    text: written,
    uri: uri,
    host: host,
    registrableDomain: registrableDomainOf(host),
    path: path,
    userInfo: userInfo,
    port: port,
    nonAsciiHost: nonAscii,
    hidesHost: backslash || mismatch,
  );
}

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

bool _hostIn(String host, Set<String> hosts) =>
    hosts.contains(host) || hosts.any((h) => host.endsWith('.$h'));

/// Whether the link is an app store page (Google Play, the App Store).
bool isAppStoreLink(FoundLink link) => appStoreHosts.contains(link.host);

/// Whether the host itself is hidden or odd: an IP address, a login before
/// it, a port other than 80 or 443, punycode, or non-Latin letters.
bool hasRiskyHost(FoundLink link) =>
    link.nonAsciiHost ||
    link.hidesHost ||
    link.userInfo.isNotEmpty ||
    (link.port != null && link.port != 80 && link.port != 443) ||
    _isIpHost(link.host) ||
    link.host.split('.').any((label) => label.startsWith('xn--'));

bool isAppFileLink(FoundLink link) {
  final path = link.path.split(RegExp(r'[?#]')).first.toLowerCase();
  return path.endsWith('.apk') || path.endsWith('.xapk') || path.endsWith('.apks');
}

bool isShortLink(FoundLink link) => _hostIn(link.host, shortenerHosts);
bool isSoftShortLink(FoundLink link) => _hostIn(link.host, softShortenerHosts);

/// The risk of one link: appFile, then lookalike, hidden, soft, none.
LinkRisk linkRiskOf(FoundLink link) {
  if (isAppFileLink(link)) return LinkRisk.appFile;
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
  final suffixLabels = registrable.split('.').length - 1;
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
  final first = registrable.split('.').first;
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
