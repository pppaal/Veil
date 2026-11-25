// Link data for the scam checker: brands whose sites scam texts imitate, the
// short-link services that hide where a link goes, and the endings a bare
// domain is read with. Match data only; none of it is shown on screen.

/// A company or agency scam links pretend to be.
class LinkBrand {
  const LinkBrand({required this.tokens, required this.labels, required this.domains});

  /// Words that name the brand inside a host label: `cj-delivery`,
  /// `naverlogin` (rules L1 and L2).
  final List<String> tokens;

  /// The brand's own domain names without their ending, compared by edit
  /// distance and look-alike letters (rules L3 and L4). Ordinary English
  /// words (police, post) are left out here: a near spelling of them is a
  /// normal word, not a fake site.
  final List<String> labels;

  /// Its own and sister domains; a host equal to one of them or under one is
  /// the brand itself.
  final List<String> domains;
}

const linkBrands = <LinkBrand>[
  // Couriers.
  LinkBrand(tokens: ['cj', 'cjlogistics'], labels: ['cjlogistics'], domains: ['cjlogistics.com', 'cj.net']),
  LinkBrand(tokens: ['epost', 'post'], labels: ['epost'], domains: ['epost.go.kr', 'koreapost.go.kr']),
  LinkBrand(tokens: ['hanjin'], labels: ['hanjin'], domains: ['hanjin.com', 'hanjin.co.kr']),
  LinkBrand(
    tokens: ['lotte', 'lotteglogis'],
    labels: ['lotteglogis', 'lotte'],
    domains: ['lotteglogis.com', 'lotte.co.kr', 'lottecard.co.kr', 'lotteon.com', 'lotte.com'],
  ),
  LinkBrand(tokens: ['ilogen', 'logen'], labels: ['ilogen'], domains: ['ilogen.com']),
  LinkBrand(
    tokens: ['coupang'],
    labels: ['coupang'],
    domains: ['coupang.com', 'coupangeats.com', 'coupangplay.com'],
  ),
  LinkBrand(tokens: ['usps'], labels: ['usps'], domains: ['usps.com']),
  LinkBrand(tokens: ['royalmail'], labels: ['royalmail'], domains: ['royalmail.com', 'royalmail.co.uk']),
  LinkBrand(tokens: ['fedex'], labels: ['fedex'], domains: ['fedex.com']),
  LinkBrand(tokens: ['ups'], labels: ['ups'], domains: ['ups.com']),
  LinkBrand(
    tokens: ['dhl'],
    labels: ['dhl'],
    domains: [
      'dhl.com', 'dhl.de', 'dhl.co.kr', 'dhl.fr', 'dhl.co.uk', 'dhl.it', 'dhl.es', 'dhl.nl', 'dhl.be', //
      'dhl.ch', 'dhl.at', 'dhl.pl', 'dhl.se', 'dhl.dk', 'dhl.fi', 'dhl.no', 'dhl.ie', 'dhl.pt', 'dhl.cz',
      'dhl.hu', 'dhl.ca', 'dhl.com.au', 'dhl.co.jp', 'dhl.co.in', 'dhl.com.mx', 'dhl.com.br',
      'dhl.com.tr', 'dhl.com.sg', 'dhl.com.hk', 'dhl.com.cn', 'dhl.com.tw', 'dhl.co.nz', 'dhl.co.za',
    ],
  ),
  // Amazon's stores, one per country, and its own services.
  LinkBrand(
    tokens: ['amazon'],
    labels: ['amazon'],
    domains: [
      'amazon.com', 'amazon.ca', 'amazon.com.mx', 'amazon.com.br', 'amazon.co.uk', 'amazon.ie', //
      'amazon.de', 'amazon.fr', 'amazon.it', 'amazon.es', 'amazon.nl', 'amazon.se', 'amazon.pl',
      'amazon.com.be', 'amazon.com.tr', 'amazon.ae', 'amazon.sa', 'amazon.eg', 'amazon.in',
      'amazon.co.jp', 'amazon.sg', 'amazon.com.au', 'amazon.cn', 'amazon.co.za', 'amazonaws.com',
      'primevideo.com', 'amzn.to', 'amzn.com', 'amzn.eu', 'a.co',
    ],
  ),
  // Banks and payments.
  LinkBrand(tokens: ['kb', 'kbstar'], labels: ['kbstar'], domains: ['kbstar.com', 'kbcard.com']),
  LinkBrand(
    tokens: ['shinhan'],
    labels: ['shinhan'],
    domains: ['shinhan.com', 'shinhancard.com', 'shinhansec.com'],
  ),
  LinkBrand(
    tokens: ['woori', 'wooribank'],
    labels: ['wooribank', 'woori'],
    domains: ['wooribank.com', 'wooricard.com', 'woorifg.com'],
  ),
  LinkBrand(
    tokens: ['hana', 'kebhana'],
    labels: ['kebhana'],
    domains: ['kebhana.com', 'hanacard.co.kr', 'hanafn.com', 'hanabank.com'],
  ),
  LinkBrand(tokens: ['nh', 'nonghyup'], labels: ['nonghyup'], domains: ['nonghyup.com', 'nhbank.com']),
  LinkBrand(tokens: ['ibk'], labels: ['ibk'], domains: ['ibk.co.kr']),
  LinkBrand(
    tokens: ['kakao', 'kakaobank', 'kakaopay'],
    labels: ['kakao', 'kakaobank', 'kakaopay'],
    domains: [
      'kakao.com',
      'kakaocorp.com',
      'kakaopay.com',
      'kakaobank.com',
      'kakaogames.com',
      'kakaomobility.com',
      'kakaoenterprise.com',
      'daum.net',
      'kko.to',
    ],
  ),
  LinkBrand(
    tokens: ['toss', 'tossbank'],
    labels: ['tossbank', 'toss'],
    domains: ['toss.im', 'toss.me', 'tossbank.com', 'tosspayments.com'],
  ),
  LinkBrand(
    tokens: ['naver'],
    labels: ['naver'],
    domains: ['naver.com', 'naver.me', 'navercorp.com', 'naver.net', 'pstatic.net', 'me2.do'],
  ),
  LinkBrand(
    tokens: ['paypal'],
    labels: ['paypal'],
    domains: [
      'paypal.com', 'paypal.me', 'paypalobjects.com', 'paypal.co.uk', 'paypal.de', 'paypal.fr', //
      'paypal.it', 'paypal.es', 'paypal.nl', 'paypal.be', 'paypal.at', 'paypal.ch', 'paypal.pl',
      'paypal.se', 'paypal.dk', 'paypal.no', 'paypal.ie', 'paypal.pt', 'paypal.ca', 'paypal.com.au',
      'paypal.com.mx', 'paypal.com.br', 'paypal.com.sg', 'paypal.com.hk', 'paypal.jp', 'paypal.cn',
    ],
  ),
  LinkBrand(
    tokens: ['apple'],
    labels: ['apple'],
    domains: [
      'apple.com', 'icloud.com', 'apple.co', 'apple.news', 'apple.com.cn', 'me.com', 'mac.com', //
      'itunes.com', 'mzstatic.com', 'cdn-apple.com', 'icloud-content.com',
    ],
  ),
  // Agencies. Every host under go.kr or gov.uk is the government's own.
  LinkBrand(tokens: ['nhis'], labels: ['nhis'], domains: ['nhis.or.kr']),
  LinkBrand(tokens: ['hometax'], labels: ['hometax'], domains: ['hometax.go.kr']),
  LinkBrand(tokens: ['police'], labels: [], domains: ['police.go.kr']),
  LinkBrand(tokens: ['spo'], labels: ['spo'], domains: ['spo.go.kr']),
  LinkBrand(tokens: ['fss'], labels: ['fss'], domains: ['fss.or.kr']),
  LinkBrand(tokens: [], labels: [], domains: ['gov.kr', 'go.kr']),
  LinkBrand(tokens: ['irs'], labels: ['irs'], domains: ['irs.gov']),
  LinkBrand(tokens: [], labels: [], domains: ['gov.uk']),
];

/// Words that turn a brand name into a fake site's name when put next to it.
const scamAffixes = <String>{
  'login', 'secure', 'security', 'verify', 'support', 'help', 'service', 'delivery', 'track', //
  'tracking', 'parcel', 'post', 'pay', 'refund', 'kr', 'korea', 'official', 'update', 'app',
  'center', 'cs', 'gov', 'notice', 'event', 'bank', 'card', 'safe', 'auth', 'account', 'my',
};

/// Services whose links hide the real address.
const shortenerHosts = <String>{
  'bit.ly', 'han.gl', 'vo.la', 'url.kr', 'buly.kr', 'c11.kr', 'lrl.kr', 't.ly', 'tinyurl.com', //
  'is.gd', 'cutt.ly', 'shorturl.at', 'rebrand.ly', 'rb.gy', 'ow.ly', 's.id', 't.co', 'goo.su',
};

/// The companies' own short links: they hide the target too, but families
/// share map places and posts through them every day.
const softShortenerHosts = <String>{'naver.me', 'kko.to', 'me2.do'};

/// App store pages, which do not count as a link for the authority rule.
const appStoreHosts = <String>{'play.google.com', 'apps.apple.com'};

/// Endings a bare domain (no http://) is read with.
const bareDomainEndings = <String>[
  'com', 'net', 'org', 'io', 'me', 'ly', 'gl', 'do', 'la', 'id', 'su', 'to', 'at', 'co', 'kr', //
  'jp', 'uk', 'us', 'info', 'biz', 'xyz', 'top', 'site', 'online', 'shop', 'app', 'dev', 'page',
  'link', 'click', 'cc', 'vip', 'icu', 'cn', 'ru', 'live', 'store', 'club', 'work', 'pw', 'tk',
  'ml', 'ga', 'cf', 'gq', 'buzz', 'fun', 'asia', 'kim', 'mobi', 'lol', 'rest', 'bar',
];

/// Endings of two labels, under which the registrable domain has three.
const twoPartSuffixes = <String>{
  'co.kr', 'go.kr', 'or.kr', 'ne.kr', 're.kr', 'ac.kr', 'pe.kr', 'co.uk', 'org.uk', 'gov.uk', //
  'ac.uk', 'co.jp', 'ne.jp', 'or.jp', 'ac.jp', 'go.jp', 'com.au', 'net.au', 'org.au', 'gov.au',
  'edu.au', 'co.nz', 'co.za', 'co.in', 'net.in', 'org.in', 'gov.in', 'ac.in', 'co.id', 'co.th',
  'co.il', 'com.mx', 'com.br', 'com.ar', 'com.tr', 'com.be', 'com.sg', 'com.my', 'com.ph',
  'com.vn', 'com.hk', 'com.tw', 'com.cn', 'com.sa', 'com.eg',
};
