// Korean match data for the scam checker. These words are compared with
// message text on the phone and never shown on screen (the app is English
// only; people chat in Korean inside it). Lists start from the public
// warning pages of the police, FSS, FSC and KISA, paraphrased, never copied.
//
// Words in [koShortTokens] match only a whole word of the spaced view, or the
// word with a particle (signals.dart); every other word matches anywhere in
// the compact view (letters, digits and Hangul only).

/// Short words that sit inside many other words (딸기, 이모티콘, 형광펜,
/// 돈까스, 이어폰), so they match only as a whole word.
const koShortTokens = <String>{
  '엄마', '엄빠', '아빠', '아들', '딸', '언니', '오빠', '누나', '형', '이모', '삼촌', '고모', //
  '돈', '폰', '이체', '여권', '검사', '경찰', '출석', '구속', '연루', '영장',
};

/// Particles and copulas a short word may carry, by whether the word ends in
/// a consonant.
const koParticlesAfterConsonant = <String>{'이', '은', '을', '아', '이야', '이랑', '이에요', '으로', '과'};
const koParticlesAfterVowel = <String>{'가', '는', '를', '야', '랑', '예요', '로', '와'};
const koParticlesAfterEither = <String>{
  '한테', '한테서', '에게', '에서', '께', '도', '만', '의', '님', '좀', '까지', '부터', '입니다', //
  '이라고', '라고',
};

// Pattern 1: family and new phone.
const koKin = ['엄마', '어머니', '엄빠', '아빠', '아버지', '아들', '딸', '할머니', '할아버지'];
const koSocialKin = ['언니', '오빠', '누나', '형', '이모', '삼촌', '고모'];
const koGreetings = {'안녕'};
const koMeClaim = {'나야', '나예요', '저예요', '나에요'};
const koPhoneWords = ['휴대폰', '핸드폰', '핸폰'];
const koPhoneTrouble = ['고장', '망가', '깨졌', '액정', '떨어뜨', '잃어버', '분실', '수리', '침수'];

/// Device words glued to the trouble, matched at the start of a word (so
/// 이어폰고장 is not one).
const koGluedDevice = ['폰고장', '폰액정', '폰분실', '폰수리', '폰침수'];
const koDeviceStory = ['임시폰', '친구폰'];
const koNewAccountClaim = ['새번호', '번호바꿨', '이번호로', '계정새로', '새계정'];
const koCallAvoid = ['통화가안돼', '통화는안돼', '통화가못해', '통화는못해', '통화가어려워', '통화는어려워', '전화못받아', '문자로만'];

// Pattern 2: money.
const koMoney = ['송금', '입금', '대신결제', '결제좀', '계좌번호', '이계좌로', '예금주', '돈', '이체'];
const koUrgency = ['급해', '급하게', '급한', '당장', '오늘안에', '빨리좀'];
const koSecrecy = ['비밀로', '말하지마', '비밀유지', '모르게'];
const koThirdParty = ['다른사람계좌', '친구계좌', '지인계좌'];

// Ask forms.
/// Endings that make a request, at the end of a word.
const koAskEndings = ['줘', '줘요', '줄래', '주세요', '주실래요', '주십시오', '하세요', '하십시오', '바랍니다', '셔야'];

/// Request forms read on the compact view.
const koAskCompact = ['줄수있어', '해달라', '부탁해', '부탁드려', '부탁드립'];

/// Verbs that ask when they end a sentence (보내, 알려 ...).
const koAskSentenceFinal = ['보내', '알려', '불러', '찍어', '깔아', '설치해'];

/// Money nouns after which a sentence-final 해 asks (송금해).
const koMoneyVerbNouns = ['송금', '이체', '입금', '결제'];

/// Verbs that make 좀 a request (돈 좀 보내).
const koAskAfterJom = [
  '보내', '빌려', '알려', '부쳐', '찍어', '깔아', '설치', '입금', '송금', '이체', '결제', '불러', //
  '구매', '사', '줘', '해',
];

/// A word right after the verb that thanks for it (보내줘 고마워).
const koThanks = ['고마', '감사'];

/// Words that end in a request form and are a greeting.
const koGreetingAsks = ['안녕', '수고'];

// Pattern 3: gift cards.
const koGift = ['상품권', '컬쳐랜드', '해피머니', '기프트카드', '구글플레이카드'];
const koPinBack = ['핀번호', 'pin번호', '뒷면사진', '뒷면번호'];

// Pattern 4: codes.
const koCode = ['인증번호', '인증코드', '보안코드', 'otp', '6자리', '여섯자리', '문자로온번호', '문자로간번호'];
const koMistake = ['잘못보냈'];

// Pattern 5: ID and card details.
const koId = [
  '신분증', '주민등록증', '운전면허증', '여권', '주민번호', '주민등록번호', '카드번호', '유효기간', //
  'cvc', '공동인증서', '보안카드',
];
const koCardSecretNear = ['카드', '계좌', '통장', '은행', '공동인증서', '보안카드'];
const koCardSecretWord = ['비밀번호', 'cvc', 'cvv', '유효기간'];
const koPhoto = ['사진', '찍어'];

// Pattern 6: remote-control apps. 금감원 앱 and 검찰 앱 are left out of the
// pattern list: "금감원 앱 깔면 사기 문자 신고된대" is normal talk, and an
// agency app pushed with a link is the authority rule's.
const koRemoteName = ['팀뷰어', '애니데스크', '리모트뷰', '퀵서포트', '러스트데스크', '에어드로이드'];
const koRemoteWord = ['원격제어', '원격조종', '원격지원', '원격접속', '보안앱'];
const koInstall = ['설치', '깔아', '깔면', '깔고', '다운받', '다운로드'];

// Pattern 8: delivery.
const koDelivery = ['택배', '배송', '운송장', '반송', '보관중', '재배송', '통관'];
const koAddressProblem = ['주소불일치', '주소오류', '주소확인', '주소지'];
const koFee = ['관세', '미납'];

// Pattern 9: bank, card and loan.
const koBankPretext = [
  '카드발급', '카드배송', '카드승인', '본인이아니', '고객센터로연락', '해외결제', '결제승인', '이상거래', //
  '계좌정지', '대출', '저금리', '대환', '한도조회',
];

// Pattern 10: prosecutors, police, FSS.
const koAuthorityStrong = ['검찰', '지검', '수사관', '경찰청', '사이버수사대', '금융감독원', '금감원'];
const koAuthorityWeak = [
  '검사', '경찰', '출석', '구속', '연루', '영장', '사건번호', '명의도용', '대포통장', '약식조사', //
  '계좌동결', '자산보호',
];
const koSafeAccount = ['안전계좌', '국가안전계좌', '보호계좌'];

// Pattern 11: government.
const koGov = [
  '지원금', '생계비', '환급', '건강보험공단', '국민건강보험', '국세청', '과태료', '범칙금', '교통위반', //
  '체납', '정부24', '국민연금',
];

// Pattern 12: investment. 선물 alone is a present, so futures need 거래 or
// 옵션; 코인노래방 and the like are no coin talk.
const koInvest = ['리딩방', '종목추천', '고수익', '비트코인', '테더', 'usdt', '거래소', '선물거래', '선물옵션', '차익거래', '단톡방초대'];
final koCoin = RegExp(r'코인(?!노래|빨래|세탁|락커|로커)');
const koGuarantee = ['원금보장', '수익보장'];
const koReturnWords = ['수익률', '수익'];
const koFeeFirst = ['출금수수료', '출금하려면수수료', '세금먼저', '보증금'];

// Account numbers.
/// Bank names that are no everyday word, counted alone.
const koDistinctiveBanks = ['신한', '농협', '카카오뱅크', '토스뱅크', '케이뱅크', 'sc제일', 'im뱅크', 'kb', 'ibk', 'nh'];

/// Bank names that are everyday words (우리, 하나, 국민), counted only when
/// joined to 은행, 뱅크, 금고 or 예금.
const koPlainBanks = ['우리', '하나', '국민', '기업', '부산', '대구', '광주', '경남', '전북', '제주', '새마을', '수협', '씨티', '우체국'];
const koBankJoins = ['은행', '뱅크', '금고', '예금'];
const koAccountWords = ['예금주', '계좌'];

/// A digit run near these is a parcel or order number, never an account.
const koNotAccountNear = ['운송장', '송장', '택배', '주문번호'];

/// Counter words after 만 or 천 that make a number no amount (5천 걸음).
const koCounters = [
  '개월', '시간', '마리', '걸음', '명', '개', '번', '살', '년', '분', '층', '호', '점', '등', '위', //
  '장', '권', '대', '병', '잔', '회', 'km', 'kg',
];
