import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/rule_risk_checker.dart';
import 'package:veil_mobile/src/core/safety/signals.dart';
import 'package:veil_mobile/src/core/safety/text_normalizer.dart';

void main() {
  test('short Korean words match only as whole words, and words inside other words match nothing', () {
    bool has(String text, String word) => hasShortWord(normalizeText(text), word);

    // A whole word, or the word with a particle chosen by its last sound.
    expect(has('엄마 나야', '엄마'), isTrue);
    expect(has('엄마가 그러는데', '엄마'), isTrue);
    expect(has('엄마랑 갔어', '엄마'), isTrue);
    expect(has('엄마한테 말해', '엄마'), isTrue);
    expect(has('아들아 미안', '아들'), isTrue);
    expect(has('딸이에요', '딸'), isTrue);
    expect(has('돈이 없어', '돈'), isTrue);
    expect(has('돈 좀 보내줘', '돈'), isTrue);
    expect(has('형한테 물어봐', '형'), isTrue);
    expect(has('여권을 잃어버렸어', '여권'), isTrue);
    // 이체 also as a verb.
    expect(has('이체해줘', '이체'), isTrue);
    expect(has('이체하세요', '이체'), isTrue);
    // A two-syllable word split by a space, a dot or an emoji is still the word.
    expect(has('엄 마 나야', '엄마'), isTrue);
    expect(has('엄.마 나야', '엄마'), isTrue);
    expect(has('엄💕마 나야', '엄마'), isTrue);
    expect(has('이💰체해줘', '이체'), isTrue);

    // Inside another word: nothing.
    for (final (text, word) in [
      ('딸기 사 와', '딸'),
      ('딸랑 하나 남았어', '딸'), // 랑 follows a vowel; 딸 ends in a consonant
      ('이모티콘 보내줘', '이모'),
      ('형광펜 빌려줘', '형'),
      ('형편이 어려워', '형'),
      ('돈까스 먹자', '돈'),
      ('돈가스 먹자', '돈'),
      ('용돈 받았어', '돈'),
      ('이어폰 고장났어', '폰'),
      ('이 체크카드로 결제해', '이체'),
      ('검사비 5만원', '검사'),
      ('경찰서 앞이야', '경찰'),
      ('이 모자 예쁘다', '이모'),
      ('아 들어왔어', '아들'),
      ('오 빠르다', '오빠'),
    ]) {
      expect(has(text, word), isFalse, reason: '$word in $text');
    }

    // Through the checker: none of these reads as family, money or a phone
    // story.
    const checker = RuleRiskChecker();
    for (final text in ['딸기 사 와', '이모티콘 보내줘', '형광펜 빌려줘', '돈까스 먹자', '이 체크카드로 결제해', '이어폰 고장났어']) {
      final s = checker.signalsOf(text);
      for (final signal in [Signal.kin, Signal.socialKin, Signal.money, Signal.deviceStory]) {
        expect(s.has(signal), isFalse, reason: '$signal in $text');
      }
    }
    expect(checker.signalsOf('돈 좀 보내줘').has(Signal.money), isTrue);
    expect(checker.signalsOf('엄마 나야').has(Signal.kinVocative), isTrue);
    expect(checker.signalsOf('아빠한테 말하지 마').has(Signal.kinVocative), isFalse);
    expect(checker.signalsOf('폰 고장나서 연락해').has(Signal.deviceStory), isTrue);

    // Longer Korean words match anywhere in the compact view, spaced or not.
    expect(checker.signalsOf('송 금 해 줘').has(Signal.money), isTrue);
    expect(checker.signalsOf('인증 번호가 안 와').has(Signal.code), isTrue);
    expect(checker.signalsOf('안전 계좌로 옮기세요').has(Signal.safeAccount), isTrue);

    // Ask endings count only at the end of a word, and not as thanks.
    expect(checker.signalsOf('돈 보내줘').has(Signal.ask), isTrue);
    expect(checker.signalsOf('돈 보내줘서 고마워').has(Signal.ask), isFalse);
    expect(checker.signalsOf('돈 보냈어').has(Signal.ask), isFalse);
    expect(checker.signalsOf('안녕하세요').has(Signal.ask), isFalse);
    // A sentence-final 해 asks only after a money noun.
    expect(checker.signalsOf('지금 송금해').has(Signal.ask), isTrue);
    expect(checker.signalsOf('돈 없어서 미안해').has(Signal.ask), isFalse);

    // Bank names that are everyday words count only joined to 은행.
    expect(checker.signalsOf('우리 123-456-789012 맞지?').has(Signal.account), isFalse);
    expect(checker.signalsOf('우리은행 123-456-789012').has(Signal.account), isTrue);
    expect(checker.signalsOf('운송장 우리은행 123456789012').has(Signal.account), isFalse);
    expect(checker.signalsOf('010-1234-5678 로 연락해').has(Signal.account), isFalse);

    // Amounts: number words count, counted things do not.
    expect(checker.signalsOf('오십 만 원').has(Signal.amount), isTrue);
    expect(checker.signalsOf('50만 보내줘').has(Signal.amount), isTrue);
    expect(checker.signalsOf('5천 걸음 걸었어').has(Signal.amount), isFalse);
    expect(checker.signalsOf('일이 원래 많아').has(Signal.amount), isFalse);

    // English words match on word boundaries only.
    expect(checker.signalsOf('my sonata broke').has(Signal.kin), isFalse);
    expect(checker.signalsOf('my son broke it').has(Signal.kin), isTrue);
    expect(checker.signalsOf('the passport office').has(Signal.id), isTrue);
    expect(checker.signalsOf('I wire my house').has(Signal.money), isFalse);
  });

  test('words of a Korean list in ASCII letters and words that sit across a space match only whole', () {
    Set<Signal> signals(String text) => detectSignals(text).present;

    // The compact view joins English words: "got pizza" holds otp, a video
    // id may too. Only the whole word is a code.
    for (final text in ['I got pizza, can you grab drinks?', 'Can you check the hotspot password?', 'https://www.youtube.com/watch?v=xOtPq12abcd 봐줘']) {
      expect(signals(text), isNot(contains(Signal.code)), reason: text);
    }
    expect(signals('OTP 번호 알려주세요'), contains(Signal.codeAsk));
    expect(containsWord('spin번호', 'pin번호'), isFalse);
    expect(containsWord('핀pin번호', 'pin번호'), isTrue);

    // 지검 and 검찰 inside one word only, never across a space, and not the
    // exam track or the job.
    for (final text in ['금액 맞는지 검토해 주세요', '이미지 검색해봐', '검찰직 인강 들어', '검찰공무원 시험 준비해', '수사 관련 기사 봤어']) {
      expect(signals(text), isNot(contains(Signal.authorityStrong)), reason: text);
    }
    for (final text in ['서울중앙지검 수사관입니다', '수원지검에서 연락드립니다', '검찰청입니다', '검 찰 입니다']) {
      expect(signals(text), contains(Signal.authorityStrong), reason: text);
    }

    // 모르게 after the speaker, 당장 inside 식당 장소, 번호 바꿨 after 비밀.
    expect(signals('나도 모르게 잠들었네'), isNot(contains(Signal.secrecy)));
    expect(signals('아빠 모르게 보내줘'), contains(Signal.secrecy));
    expect(signals('식당 장소 정했어'), isNot(contains(Signal.urgency)));
    expect(signals('지금당장 보내'), contains(Signal.urgency));
    expect(signals('비밀번호 바꿨어'), isNot(contains(Signal.newAccountClaim)));
    expect(signals('나 번호 바꿨어'), contains(Signal.newAccountClaim));

    // A loss is no high return.
    expect(signals('코인 수익률 -20%'), isNot(contains(Signal.highReturn)));
    expect(signals('코인 수익률 마이너스 20%'), isNot(contains(Signal.highReturn)));
    expect(signals('코인 수익률 20%'), contains(Signal.highReturn));
  });
}
