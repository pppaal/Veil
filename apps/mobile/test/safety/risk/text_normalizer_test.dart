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
    // So does every other default-ignorable code point: variation selectors,
    // Mongolian selectors, tag characters, fillers and the rest.
    const ignorable = [
      0x00AD, 0x034F, 0x061C, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x180B, 0x180C, 0x180D, 0x180E, 0x180F, //
      0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x202A, 0x202E, 0x2060, 0x2064, 0x2065, 0x2066, 0x2069,
      0x206A, 0x206F, 0x3164, 0xFE00, 0xFE0E, 0xFE0F, 0xFEFF, 0xFFA0, 0xFFF0, 0xFFF8, 0x1BCA0, 0x1BCA3,
      0x1D173, 0x1D17A, 0xE0000, 0xE0001, 0xE0020, 0xE007F, 0xE0100, 0xE01EF, 0xE0FFF,
    ];
    for (final c in ignorable) {
      final mark = String.fromCharCode(c);
      expect(spaced('se${mark}nd mo${mark}ney'), 'send money', reason: 'U+${c.toRadixString(16)}');
      expect(spaced('\uc5c4$mark\ub9c8 \ub098$mark\uc57c'), '\uc5c4\ub9c8 \ub098\uc57c', reason: 'U+${c.toRadixString(16)}');
    }
    expect(spaced('Can y\ufe0fou s\ufe0fend m\ufe0fe \$500 urg\ufe0fently'), 'can you send me \$500 urgently');
    expect(spaced('Hi M\ufe0fum it\u2019s me'), "hi mum it's me");

    // Full-width letters, the ideographic space and circled digits fold.
    expect(spaced('ＯＴＰ　번호'), 'otp 번호');
    expect(compact('①②③'), '123');
    expect(compact('⑴⑵'), '12');

    // Cyrillic and Greek letters that look Latin fold to Latin.
    expect(spaced('\u0422e\u0430mvi\u0435wer'), 'teamviewer');
    expect(spaced('\u039f\u03a4P'), 'otp');
    // Mathematical and enclosed letters fold to plain ones.
    expect(spaced('\ud835\udc2c\ud835\udc1e\ud835\udc27\ud835\udc1d \ud835\udc26\ud835\udc1e \ud835\udc26\ud835\udc28\ud835\udc27\ud835\udc1e\ud835\udc32'), 'send me money');
    expect(spaced('\ud835\ude34\ud835\ude26\ud835\ude2f\ud835\ude25 \ud835\ude48\ud835\ude4a\ud835\ude49\ud835\ude40\ud835\ude54 \ud835\udfd3\ud835\udfce\ud835\udfce'), 'send money 500');
    expect(spaced('\u24e2\u24d4\u24dd\u24d3 \u24dc\u24d4 \u24dc\u24de\u24dd\u24d4\u24e8'), 'send me money');
    expect(spaced('\u24b7\u24ca\u24ce \ud83c\udd50 \ud83c\udd36\ud83c\udd38\ud83c\udd35\ud83c\udd43 \ud83c\udd72\ud83c\udd70\ud83c\udd81\ud83c\udd73'), 'buy a gift card');

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
