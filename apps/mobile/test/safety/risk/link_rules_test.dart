import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/links.dart';

void main() {
  test('app files, short links and look-alike domains are risky; everyday domains are not', () {
    FoundLink only(String text) {
      final links = findLinks(text);
      expect(links, hasLength(1), reason: text);
      return links.single;
    }

    LinkRisk risk(String text) => linkRiskOf(only(text));

    // App files, from any host and with any query.
    for (final text in [
      'http://update-check.xyz/app.apk',
      'https://naver.com/files/viewer.APK?v=2',
      'wedding-card.site/invite.xapk',
      'http://203.0.113.7/card.apks#top',
    ]) {
      expect(risk(text), LinkRisk.appFile, reason: text);
    }

    // Short links and hosts that hide where they go.
    for (final text in [
      'bit.ly/3xYz',
      'https://han.gl/abcd',
      'tinyurl.com/y7abc',
      'http://192.168.10.4/login',
      'https://user@login.example.com/',
      'https://kakao.com:8443/event',
      'https://xn--80ak6aa92e.com/',
      'https://n\u0430ver.com/login', // a Cyrillic a
    ]) {
      expect(risk(text), LinkRisk.hidden, reason: text);
    }

    // The companies' own short links get the plain sheet.
    for (final text in ['naver.me/5abc', 'kko.to/xyz', 'me2.do/Fa3']) {
      expect(risk(text), LinkRisk.soft, reason: text);
    }

    // Look-alikes of brand domains (L1 to L5).
    for (final text in [
      'https://cj-delivery.com/track', // L1
      'naver-login.net', // L1
      'kakao-secure.xyz/auth', // L1
      'amaz0n-support.co', // L1 after folding 0 to o
      'my-post.kr', // L1
      'naverlogin.com', // L2
      'securekakao.com', // L2
      'coupnag.com/order', // L3: one swap
      'wooribamk.com', // L3: nine letters, one edit
      'c0upang.com', // L4
      'paypa1.com', // L4
      'app1e.com', // L4
      'kakao.net', // L4: the brand's name on a domain it does not own
      'http://hometax.go.kr.refund.top', // L5
      'gov-kr.site/fine', // L5
      'go-kr.info', // L5
    ]) {
      expect(risk(text), LinkRisk.lookalike, reason: text);
    }

    // Forty everyday domains are not risky (the three company short links
    // among them get only the plain sheet).
    const everyday = [
      'naver.com',
      'naver.me',
      'kakao.com',
      'kakaocorp.com',
      'kakaopay.com',
      'kakaogames.com',
      'youtube.com',
      'google.com',
      'groups.google.com',
      'instagram.com',
      'coupang.com',
      'coupangeats.com',
      'coupangplay.com',
      'apple.com',
      'icloud.com',
      'gov.kr',
      'hometax.go.kr',
      'spo.go.kr',
      'spotify.com',
      'sportsseoul.com',
      'dhlottery.co.kr',
      'groups.io',
      'cupsofjoe.com',
      'first.org',
      'stairs.co.uk',
      'pineapple.com',
      'shinhancard.com',
      'shinhansec.com',
      'amazonaws.com',
      'daum.net',
      'kakaobank.com',
      'https://toss.im/',
      'wikipedia.org',
      'github.com',
      'netflix.com',
      'lotteon.com',
      'kbstar.com',
      'https://www.dhl.de/de/privatkunden.html',
      'https://www.irs.gov/refunds',
      'https://m.blog.naver.com/abc',
    ];
    expect(everyday, hasLength(40));
    for (final text in everyday) {
      final expected = text == 'naver.me' ? LinkRisk.soft : LinkRisk.none;
      expect(risk(text), expected, reason: text);
    }
    // Near names of five-letter brands stay clean.
    for (final text in ['lotto.com', 'never.com', 'ample.com', 'polite.co.kr']) {
      expect(risk(text), LinkRisk.none, reason: text);
    }
    // The global brands' country and sister domains are their own.
    for (final text in [
      'https://amazon.ca/dp/B0abc',
      'https://www.amazon.in/x',
      'https://www.amazon.com.au/gp/x',
      'https://amazon.fr',
      'https://www.amazon.com.mx/x',
      'https://www.amazon.com.br/x',
      'https://apple.news/AbCdEf',
      'https://www.dhl.fr/fr.html',
      'https://www.dhl.co.uk/x',
      'https://www.paypal.co.uk/x',
      'https://www.paypal.de',
    ]) {
      expect(risk(text), LinkRisk.none, reason: text);
    }
    expect(only('https://www.amazon.com.mx/x').registrableDomain, 'amazon.com.mx');
    expect(only('https://shop.example.com.br/a').registrableDomain, 'example.com.br');
    expect(only('https://www.example.co.in/a').registrableDomain, 'example.co.in');

    // A brand's whole domain used as part of another host (L6).
    for (final text in [
      'https://kbstar.com.verify.xyz/login',
      'https://www.naver.com.login.top',
      'https://naver.com-login.top/a',
      'https://kakao.com.secure-login.xyz',
      'kbstar-com.xyz/login',
    ]) {
      expect(risk(text), LinkRisk.lookalike, reason: text);
    }

    // An IP address written as one number, in hex or in short form.
    for (final text in ['http://3232235777/', 'http://0x7f.0.0.1/', 'http://127.1/x', 'http://0177.0.0.1/']) {
      expect(risk(text), LinkRisk.hidden, reason: text);
    }

    // A backslash ends the host, as browsers read it: the host found is the
    // one that would open, and the trick itself hides the host.
    for (final text in ['https://evil.com\\.naver.com/login', 'https://evil.com\\@naver.com/login']) {
      final link = only(text);
      expect(link.host, 'evil.com', reason: text);
      expect(link.registrableDomain, 'evil.com', reason: text);
      expect(link.uri.host, link.host, reason: text);
      expect(isBrandHost(link.host), isFalse, reason: text);
      expect(linkRiskOf(link), LinkRisk.hidden, reason: text);
    }
    // For every link here, the host found is the host the link opens.
    for (final text in [
      'https://naver.com/a?b=1',
      'https://user@login.example.com/',
      'https://kakao.com:8443/event',
      'https://naver.com\\@evil.com/login',
      'HTTPS://WWW.NAVER.COM/A',
      'https://www.naver.com./x',
      'https://nav%65r.com/x',
    ]) {
      final link = only(text);
      if (link.host != link.uri.host.replaceAll(RegExp(r'\.$'), '')) {
        expect(linkRiskOf(link), LinkRisk.hidden, reason: '$text opens ${link.uri.host}, not ${link.host}');
      }
    }
    expect(linkRiskOf(only('https://nav%65r.com/x')), LinkRisk.hidden);

    // Two sentences with no space after the full stop are no link: a
    // Title-case ending, a title before a name, or a word-like ending with
    // no path.
    for (final text in [
      'Your package is at the door.Do you want me to bring it in?',
      'The parcel arrived today.At least it is not broken',
      'crypto is down again.Do not buy now lol',
      'got a traffic violation ticket.To be fair I was speeding',
      'package came.Me and dad opened it',
      'your package is here.do u want it',
      'it arrived today.at least',
      '택배 왔어 Mr.Kim이 받아놨대',
      'Mr.Kim sent the package',
      'mr.kim sent it',
      'ask dr.lee',
      'that was so funny.lol',
    ]) {
      expect(findLinks(text), isEmpty, reason: text);
    }
    // Real bare domains on those endings still are links.
    for (final text in [
      'naver.me',
      'kko.to',
      'me2.do/Fa3',
      'example.me/path',
      'www.example.do',
      'kakao-secure.site',
      'NAVER.COM',
      'kakao.co',
      'naver-login.Com',
    ]) {
      expect(findLinks(text), hasLength(1), reason: text);
    }
    // A short brand domain inside an ordinary host is no look-alike.
    for (final text in ['https://www.a.co.kr/', 'https://shop.me.com.ar/']) {
      expect(risk(text), LinkRisk.none, reason: text);
    }

    // Where links are and what they are.
    final links = findLinks('봐 https://naver.com/a?b=1에서, then (see bit.ly/x). mail kim@naver.com');
    expect(links.map((l) => l.text), ['https://naver.com/a?b=1', 'bit.ly/x']);
    expect(links.first.host, 'naver.com');
    expect(links.last.uri, Uri.parse('https://bit.ly/x'));
    expect(only('blog.naver.co.kr/x').registrableDomain, 'naver.co.kr');
    expect(only('https://www.hometax.go.kr/x').registrableDomain, 'hometax.go.kr');
    expect(only('naver.com').registrableDomain, 'naver.com');
    expect(findLinks('3.5kg, a.m. and e.g. are not links'), isEmpty);
  });

  // A browser decodes %-escapes in a host, reads the ideographic and
  // full-width full stops as dots and opens a non-Latin host by its xn--
  // name. Each of those tricks makes a link hidden whoever sends it, and
  // the domain the sheet names is the one the browser would open.
  test('a host is read the way a browser reads it, and any escape or non-Latin letter in it hides the link', () {
    FoundLink only(String text) {
      final links = findLinks(text);
      expect(links, hasLength(1), reason: text);
      return links.single;
    }

    for (final (text, domain) in [
      ('https://naver.com%E3%80%82login-check.xyz/', 'login-check.xyz'),
      ('https://naver.com%2Elogin-check.xyz/', 'login-check.xyz'),
      ('https://naver.com%2elogin-check.xyz/login', 'login-check.xyz'),
      ('https://naver.com\u3002login-check.xyz/', 'login-check.xyz'),
      ('https://naver.com\uFF0Elogin-check.xyz/', 'login-check.xyz'),
      ('https://naver.com\uFF61login-check.xyz/', 'login-check.xyz'),
      ('https://\u0430pple.com/login', 'xn--pple-43d.com'),
      ('https://b\u00FCcher.de/x', 'xn--bcher-kva.de'),
      ('https://xn--pple-43d.com/login', 'xn--pple-43d.com'),
      ('https://nav%65r.com/x', 'naver.com'),
      // An escape beside a letter written outside ASCII: the escape is
      // decoded and the letter kept, as a browser does.
      ('https://naver%2Ecom\u3002evil.xyz/', 'evil.xyz'),
      ('https://naver.com\u3002login%2Dcheck.xyz/', 'login-check.xyz'),
      ('https://naver.com%2E\uB85C\uADF8\uC778.xyz/', 'xn--2i0b10rutm.xyz'),
    ]) {
      final link = only(text);
      expect(linkRiskOf(link), LinkRisk.hidden, reason: text);
      expect(link.registrableDomain, domain, reason: text);
      expect(hasRiskyHost(link), isTrue, reason: text);
    }
    expect(only('https://naver.com%2Elogin-check.xyz/').host, 'naver.com.login-check.xyz');
    expect(only('https://\u0430pple.com/login').host, 'xn--pple-43d.com');
    expect(only('https://\uC608\uC2DC.\uD55C\uAD6D/').host, 'xn--vv4b11d.xn--3e0b707e');
    expect(only('https://\uFF4E\uFF41\uFF56\uFF45\uFF52.com/').host, 'naver.com', reason: 'full-width letters');

    // Not a brand's own domain because it decodes to one.
    expect(allLinksOfficial('https://nav%65r.com/x', findLinks('https://nav%65r.com/x')), isFalse);

    // A full stop that ends a sentence, or one before a Korean word, ends
    // the link as before.
    for (final text in ['\u898B\u3066 https://naver.com\u3002', 'https://naver.com\u3002\uD655\uC778\uD574']) {
      final link = only(text);
      expect(link.text, 'https://naver.com', reason: text);
      expect(linkRiskOf(link), LinkRisk.none, reason: text);
    }

    // So does one before the next sentence's first word or number: only a
    // rest that ends in a known ending (login-check.xyz) is more host.
    for (final (text, link) in [
      ('see https://naver.com\u3002Thanks', 'https://naver.com'),
      ('see https://naver.com\uFF61Thanks', 'https://naver.com'),
      ('menu at https://flats.example.org\u3002OK see you', 'https://flats.example.org'),
      ('https://www.google.com\u30021234', 'https://www.google.com'),
      ('https://www.google.com\uFF0E1234', 'https://www.google.com'),
      ('https://www.google.com\u3002Do you have it?', 'https://www.google.com'),
      ('https://naver.com\u3002Thanks\u3002See you', 'https://naver.com'),
    ]) {
      final found = only(text);
      expect(found.text, link, reason: text);
      expect(linkRiskOf(found), LinkRisk.none, reason: text);
    }
    for (final text in [
      'Log in at https://naver.com\u3002login-check.xyz/ today',
      'https://naver.com\u3002login-check.xyz\u3002',
      'https://naver.com\uFF61login\u3002check.xyz',
      'https://naver.com\u3002login-check.xyz:8443/a',
      '(https://naver.com\u3002login-check.xyz)',
      'https://naver.com\u3002Login-check.Shop/',
      'https://naver.com\u3002login-check.xyz\u3002Thanks',
    ]) {
      final link = only(text);
      expect(link.host, startsWith('naver.com.login'), reason: text);
      expect(link.registrableDomain, anyOf('login-check.xyz', 'check.xyz', 'login-check.shop'), reason: text);
      expect(linkRiskOf(link), LinkRisk.hidden, reason: text);
    }
  });

  // A browser refuses a host that, once decoded, holds a character no host
  // may hold, or whose escape does not decode. The sheet names such a host
  // as the address escapes it, never by a decoded part of it.
  test('a host a browser would refuse is named as escaped, and still hides the link', () {
    FoundLink only(String text) {
      final links = findLinks(text);
      expect(links, hasLength(1), reason: text);
      return links.single;
    }

    for (final (text, domain) in [
      ('https://evil.xyz%2F.naver.com/', 'evil.xyz%2F.naver.com'),
      ('https://naver.com%40evil.xyz/', 'naver.com%40evil.xyz'),
      ('https://evil.xyz%5C.naver.com/', 'evil.xyz%5C.naver.com'),
      ('https://evil.xyz%20.naver.com/', 'evil.xyz%20.naver.com'),
      ('https://evil.xyz%09.naver.com/', 'evil.xyz%09.naver.com'),
      ('https://evil.xyz%00.naver.com/', 'evil.xyz%00.naver.com'),
      ('https://evil.xyz%2525.naver.com/', 'evil.xyz%2525.naver.com'),
      ('https://evil.xyz%23.naver.com/', 'evil.xyz%23.naver.com'),
      ('https://evil.xyz%3F.naver.com/', 'evil.xyz%3F.naver.com'),
      ('https://naver.com%3A443.evil.xyz/', 'naver.com%3A443.evil.xyz'),
      ('https://evil%zz.naver.com/', 'evil%25zz.naver.com'),
      ('https://evil%FF.naver.com/', 'evil%FF.naver.com'),
    ]) {
      final link = only(text);
      expect(link.registrableDomain, domain, reason: text);
      expect(link.host, domain, reason: text);
      expect(link.uri.toString(), 'https://$domain/', reason: text);
      expect(linkRiskOf(link), LinkRisk.hidden, reason: text);
      expect(allLinksOfficial(text, [link]), isFalse, reason: text);
    }
    // An escape that decodes to a host a browser opens is still read as it.
    expect(only('https://naver.com%2Elogin-check.xyz/').registrableDomain, 'login-check.xyz');
  });

  // A message can be as long as the relay takes; finding its links must not
  // stall the chat however many full stops, brackets or letters outside
  // ASCII its address holds.
  test('an address with thousands of full stops or brackets is read in linear time', () {
    for (final text in [
      'https://a${'\u3002com' * 20000}',
      'https://a${'\u3002Thanks' * 15000}',
      'https://a\u3002b${'.\u3002' * 40000}',
      'https://a.com/${')' * 100000}',
      'https://a\u3002b${')' * 100000}',
      'https://a${'\u0434' * 100000}',
    ]) {
      final watch = Stopwatch()..start();
      expect(findLinks(text), hasLength(1), reason: text.substring(0, 12));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)), reason: text.substring(0, 12));
    }
  });
}
