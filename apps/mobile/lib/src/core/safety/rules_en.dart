// English match data for the scam checker, matched on the spaced view with
// word boundaries. Lists start from the FTC and Action Fraud warning pages,
// paraphrased, never copied. Never shown on screen.

// Pattern 1: family and new phone.
const enKin = ['mom', 'mum', 'mother', 'dad', 'father', 'son', 'daughter', 'grandma', 'grandpa', 'nan'];
const enGreetings = {'hi', 'hey', 'hello'};
const enMeClaim = ["it's me", 'its me', 'this is me'];
const enDeviceStory = ['lost my phone', 'broke my phone', 'phone is broken', 'screen cracked', 'dropped my phone'];
const enNewAccountClaim = ['new number', 'new account', 'this is my new', 'temporary phone', "friend's phone"];
const enCallAvoid = ["can't call", "can't talk right now", 'my mic is broken', 'text only'];

// Pattern 2: money.
const enMoney = [
  'send money', 'send me money', 'transfer money', 'transfer the money', 'wire money', 'wire me', //
  'lend me money', 'pay this for me', 'venmo', 'zelle', 'paypal', 'cash app', 'bank details',
  'account number', 'sort code',
];
const enUrgency = ['asap', 'urgent', 'urgently', 'emergency', 'right now', 'right away'];
const enSecrecy = ["don't tell", 'do not tell', 'keep this between us'];

/// Gift words: secrecy about a present between people who know each other
/// is a surprise (P2).
const enSurprise = ['surprise', 'gift', 'present', 'birthday'];
const enThirdParty = ["someone else's account", "my friend's account"];

// Ask forms.
const enAsk = ['can you', 'could you', 'i need you to', 'send me', 'buy me', 'tell me', 'read me', 'text me the'];

/// "please" asks only when one of these follows within three words.
const enPleaseVerbs = [
  'send', 'buy', 'transfer', 'pay', 'tell', 'read', 'text', 'call', 'install', 'download', //
  'click', 'tap', 'share', 'give',
];

/// Verbs that ask when they open a sentence with their object right after
/// them ("Transfer it today", "Send money now", "Pay \$200").
const enImperatives = ['send', 'transfer', 'wire', 'pay', 'buy', 'install', 'download', 'click', 'tap'];

/// The objects that make an opening verb an ask; an amount does too, and so
/// does one of [enImperativeNouns].
const enImperativeObjects = ['me', 'it', 'this', 'that', 'them', 'us'];

/// What an opening verb asks for, after an optional determiner or number
/// ("Send the verification code", "Buy 3 gift cards", "Transfer the money").
const enImperativeNouns = [
  'money', 'cash', 'payment', 'code', 'codes', 'pin', 'photo', 'photos', 'picture', 'details', //
  ...enGift, ...enCode, ...enId,
];
const enImperativeDeterminers = ['the', 'a', 'an', 'some', 'your', 'my', 'this', 'that'];

/// Card brands that may stand between the determiner and the noun ("Buy 3
/// Apple gift cards").
const enImperativeBrands = ['google play', 'google', 'apple', 'amazon', 'steam', 'itunes'];
const enThanks = ['thanks for', 'thank you for'];

// Pattern 3: gift cards.
const enGift = ['gift card', 'gift cards', 'google play card', 'google play cards', 'itunes card', 'apple gift card', 'steam card', 'top-up code'];
const enPinBack = ['pin on the back', 'scratch'];

// Pattern 4: codes.
const enCode = ['verification code', 'the code i sent you', '6-digit code', 'one-time code', 'otp'];
const enMistake = ['sent it to you by mistake'];

/// A code that did not arrive, unless the reader's side is named.
const enCodeTrouble = [
  "isn't coming", 'is not coming', 'not coming', "didn't get", "haven't got", "haven't received", //
  'not receiving', 'never came', "didn't come", "doesn't come", "isn't arriving", 'not arriving',
];
const enCodeReaderSide = ['you got', 'you received', 'you get', 'sent to you', 'your phone', 'your number', 'to you by mistake'];

// Pattern 5: ID and card details.
const enId = [
  'id card', 'photo id', 'picture of your id', 'passport', "driver's license", 'ssn', //
  'social security number', 'card number', 'cvv', 'cvc',
];
const enPhoto = ['photo', 'picture', 'pic'];

// Pattern 6: remote-control apps.
const enRemoteName = ['teamviewer', 'anydesk', 'remoteview', 'quicksupport', 'rustdesk', 'airdroid', 'supremo'];
const enRemoteWord = ['remote access', 'screen share'];
const enInstall = ['install', 'download'];
const enBankWord = ['bank', 'banking', 'bank account'];

// Pattern 8: delivery.
const enDelivery = ['package', 'parcel', 'delivery failed', 'redelivery'];
const enAddressProblem = ['address incomplete'];
const enFee = ['customs fee', 'unpaid shipping'];

// Pattern 9: bank, card and loan.
const enBankPretext = [
  'suspicious activity', 'account locked', 'verify your account', 'card was charged', //
  "if this wasn't you", 'loan approved', 'low interest',
];

// Pattern 10: prosecutors and police.
const enAuthorityStrong = ['prosecutor', 'fbi', 'police officer', 'detective', 'fraud investigator'];
const enAuthorityWeak = ['police', 'warrant', 'arrest', 'case number'];
const enSafeAccount = ['safe account', 'move your money to keep it safe', 'protect your money by moving it'];

// Pattern 11: government.
const enGov = ['tax refund', 'stimulus', 'toll unpaid', 'traffic violation', 'dmv'];

// Pattern 12: investment.
const enInvest = ['crypto', 'usdt', 'trading platform', 'mentor', 'investment opportunity'];

/// An invitation or an offer of returns.
const enInvite = [
  'join', 'sign up', 'invite', 'opportunity', 'you can earn', "you'll earn", 'you will earn', 'earn up to', //
  'you can make',
];
const enGuarantee = ['guaranteed returns'];
const enReturnWords = ['returns', 'return', 'profits', 'profit'];
const enFeeFirst = ['withdrawal fee'];

/// A digit run near these is a parcel number, never an account.
const enNotAccountNear = ['tracking'];

/// Number words an amount may be written in.
const enNumberWords = [
  'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', //
  'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
  'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'thousand', 'k',
];
const enCurrencyWords = ['dollars', 'dollar', 'bucks', 'pounds', 'pound', 'quid', 'usd'];
