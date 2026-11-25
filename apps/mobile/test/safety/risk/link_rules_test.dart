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
}
