import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/text_normalizer.dart';

void main() {
  test('spacing, jamo, zero-width and full-width tricks read as the plain words', () {
    String spaced(String text) => normalizeText(text).spaced;
    String compact(String text) => normalizeText(text).compact;

    // Letters spaced out, dotted or hyphenated read as one word.
    expect(spaced('s e n d money'), 'send money');
    expect(spaced('s.e.n.d it'), 'send it');
    expect(compact('송 금 해 줘'), '송금해줘');
    expect(spaced('송 금 해 줘'), '송금해줘');
    expect(spaced('인-증-번-호'), '인증번호');
    expect(spaced('1 2 3 4 5 6'), '123456');
    // The loose view keeps the words, so a short word stays findable.
    expect(normalizeText('돈 좀 줘').looseTokens.map((t) => t.text), ['돈', '좀', '줘']);

    // Compatibility jamo typed one letter at a time become syllables.
    expect(spaced('ㅅㅗㅇㄱㅡㅁ ㅎㅐ ㅈㅝ'), '송금 해 줘');
    expect(spaced('ㅇㅓㅁㅁㅏ ㄴㅏㅇㅑ'), '엄마 나야');
    expect(spaced('ㄷㅗㅐ'), '돼');
    expect(spaced('ㄱㅏㅂㅅ'), '값');
    expect(spaced('ㅇㅓㅂㅅㅓ'), '업서');
    // Conjoining jamo (L V T) too.
    expect(compact('\u110b\u1175\u11ab\u110c\u1173\u11bc'), '인증');
    // Lone jamo (laughs, tears) are no word.
    expect(spaced('ㅋㅋㅋ 알았어 ㅠㅠ'), '알았어');

    // Zero-width and other invisible characters vanish.
    expect(compact('인\u200b증\u200b번\u200b호'), '인증번호');
    expect(spaced('veri\u200bfication \u2060code'), 'verification code');
    expect(spaced('\u202e\ufeffsend\u00ad me'), 'send me');

    // Full-width letters, the ideographic space and circled digits fold.
    expect(spaced('ＯＴＰ　번호'), 'otp 번호');
    expect(compact('①②③'), '123');
    expect(compact('⑴⑵'), '12');

    // Cyrillic and Greek letters that look Latin fold to Latin.
    expect(spaced('\u0422e\u0430mvi\u0435wer'), 'teamviewer');
    expect(spaced('\u039f\u03a4P'), 'otp');

    // Symbols and emoji between words are spaces.
    expect(spaced('send💰money'), 'send money');
    expect(spaced('송금💸해줘'), '송금 해줘');

    // A line break ends a sentence.
    final lines = normalizeText('돈 보내\n고마워');
    expect(lines.tokens.firstWhere((t) => t.text == '보내').sentenceEnd, isTrue);

    // Plain text is left as it is.
    expect(spaced('엄마 나 오늘 늦어'), '엄마 나 오늘 늦어');
    expect(spaced('Mum can you send me £20'), 'mum can you send me £20');

    // Only the first 4000 code units are read.
    expect(normalizeText('a' * 5000).compact.length, maxCheckedLength);
  });
}
