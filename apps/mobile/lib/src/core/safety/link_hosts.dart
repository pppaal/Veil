// The host a browser opens for a host as a message writes it. A browser
// decodes %-escapes in a host, reads the ideographic and full-width full
// stops as dots, reads full-width letters and digits as plain ones, and
// turns every label that is not plain ASCII into its punycode (xn--) form,
// which is how its address bar shows such a host. The link sheet names
// that host, so a host written to look like another one is shown as what
// it opens.

/// Full stops a browser reads as '.' in a host: ideographic (U+3002), full
/// width (U+FF0E) and half-width ideographic (U+FF61).
bool isHostFullStop(int c) => c == 0x3002 || c == 0xFF0E || c == 0xFF61;

/// [written] (no login, no port) as a browser opens it: %-escapes decoded,
/// [isHostFullStop] dots and full-width forms read as ASCII, lower case,
/// no trailing dot, and every label that is still not ASCII in its xn--
/// form. An escape that does not decode is left as written.
String browserHost(String written) {
  var host = written;
  if (host.contains('%')) {
    try {
      host = Uri.decodeComponent(host);
    } on ArgumentError {
      // Not a valid escape, or not UTF-8: a browser refuses such a host;
      // it is shown as written.
    } on FormatException {
      // As above.
    }
  }
  final plain = StringBuffer();
  for (final c in host.runes) {
    if (isHostFullStop(c)) {
      plain.write('.');
    } else if (c >= 0xFF01 && c <= 0xFF5E) {
      plain.writeCharCode(c - 0xFEE0);
    } else {
      plain.writeCharCode(c);
    }
  }
  final lower = plain.toString().toLowerCase();
  final trimmed = lower.endsWith('.') ? lower.substring(0, lower.length - 1) : lower;
  return trimmed.split('.').map(_asciiLabel).join('.');
}

String _asciiLabel(String label) => label.runes.every((c) => c < 0x80) ? label : 'xn--${punycode(label)}';

const _base = 36;
const _tMin = 1;
const _tMax = 26;
const _skew = 38;
const _damp = 700;

/// [input] in Punycode (RFC 3492), without the xn-- prefix.
String punycode(String input) {
  final codePoints = input.runes.toList();
  final out = StringBuffer();
  for (final c in codePoints) {
    if (c < 0x80) out.writeCharCode(c);
  }
  final basic = out.length;
  if (basic > 0) out.write('-');
  var n = 0x80;
  var delta = 0;
  var bias = 72;
  var handled = basic;
  while (handled < codePoints.length) {
    var next = 0x10FFFF + 1;
    for (final c in codePoints) {
      if (c >= n && c < next) next = c;
    }
    delta += (next - n) * (handled + 1);
    n = next;
    for (final c in codePoints) {
      if (c < n) delta++;
      if (c != n) continue;
      var q = delta;
      for (var k = _base;; k += _base) {
        final t = k <= bias ? _tMin : (k >= bias + _tMax ? _tMax : k - bias);
        if (q < t) break;
        out.writeCharCode(_digit(t + (q - t) % (_base - t)));
        q = (q - t) ~/ (_base - t);
      }
      out.writeCharCode(_digit(q));
      bias = _adapt(delta, handled + 1, first: handled == basic);
      delta = 0;
      handled++;
    }
    delta++;
    n++;
  }
  return out.toString();
}

int _digit(int d) => d < 26 ? 0x61 + d : 0x30 + d - 26;

int _adapt(int delta, int points, {required bool first}) {
  var d = first ? delta ~/ _damp : delta ~/ 2;
  d += d ~/ points;
  var k = 0;
  while (d > ((_base - _tMin) * _tMax) ~/ 2) {
    d ~/= _base - _tMin;
    k += _base;
  }
  return k + ((_base - _tMin + 1) * d) ~/ (d + _skew);
}
