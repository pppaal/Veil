import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/handle_lookalike.dart';

LookalikeAnchor _anchor(String handle, {String? name, bool verified = true, String? userId}) =>
    (userId: userId ?? 'u-$handle', handle: handle, name: name, verified: verified);

void main() {
  test('flags handles one edit, a swapped look-alike character or a suffix away from a contact\'s', () {
    LookalikeMatch? check(String anchor, String peer, {String? anchorName, String? peerName}) =>
        findLookalike(peer, peerName, [_anchor(anchor, name: anchorName)], peerUserId: 'u-peer');

    // Must flag (anchor first).
    for (final (anchor, peer) in [
      ('sam', 'sam_new'),
      ('sam', 'sam2'),
      ('sam', 'sam.official'),
      ('sam', '5am'),
      ('sam', 'sarn'), // rn reads as m
      ('jiwoo', 'jiwoo.lee'),
      ('jiwoo', 'jiwoo.kr'),
      ('jiwoo2001', 'jiwoo2002'),
      ('minjun', 'mlnjun'),
      ('minjun', 'mnijun'), // a swap
      ('seoyeon.park', 'seoyeon.parc'), // any one edit at eight letters
      ('kimminjun1234', 'kimminjun1243x'), // two edits at twelve
    ]) {
      expect(check(anchor, peer), isNotNull, reason: '$peer vs $anchor');
    }
    expect(check('sam', 'sam_new')!.rule, LookalikeRule.skeleton);
    // Only a whole trailing run of one to four digits is a number suffix; a
    // longer run stays part of the handle.
    expect(handleSkeleton('sam1234'), 'sam');
    expect(handleSkeleton('sam12345'), 'saml2eas');
    expect(check('jiwoo', 'jiwoo.lee')!.rule, LookalikeRule.affix);
    expect(check('minjun', 'mnijun')!.rule, LookalikeRule.oneEdit);

    // A family nickname and a handle that spells the family word.
    for (final peer in ['mom_new', 'eomma2']) {
      final match = check('jiyoung.kim', peer, anchorName: '엄마');
      expect(match?.rule, LookalikeRule.kinName, reason: peer);
    }
    expect(check('jiyoung.kim', 'appa', anchorName: '우리 아빠')?.rule, LookalikeRule.kinName);
    // Two accounts under one nickname.
    expect(check('jiyoung.kim', 'random.person', anchorName: 'Mom', peerName: ' mom ')?.rule, LookalikeRule.sameName);

    // Must not flag.
    for (final (anchor, peer) in [
      ('sam', 'sami'),
      ('sam', 'sammy'),
      ('alex', 'alexander'),
      ('jiwoo', 'jiwon'),
      ('minji', 'minja'),
      ('seoyun', 'seoyeon'),
    ]) {
      expect(check(anchor, peer), isNull, reason: '$peer vs $anchor');
    }
    expect(isKinHandle('son'), isFalse);
    expect(isKinHandle('son7'), isFalse);
    expect(isKinHandle('nan'), isFalse);
    expect(isKinHandle('mom_new'), isTrue);
    expect(isKinHandle('eomma2'), isTrue);
    expect(check('jiyoung.kim', 'son7', anchorName: '아들'), isNull);
    // An account against itself, and the same handle on another account
    // (the existing hold path).
    expect(findLookalike('sam2', null, [_anchor('sam', userId: 'u-peer')], peerUserId: 'u-peer'), isNull);
    expect(findLookalike('sam', null, [_anchor('sam', userId: 'u-other')], peerUserId: 'u-peer'), isNull);
    // Nothing is checked for a verified peer.
    expect(findLookalike('sam2', null, [_anchor('sam')], peerUserId: 'u-peer', peerVerified: true), isNull);

    // Best match: rule order, then a verified anchor, then distance, then
    // the handle.
    final best = findLookalike(
        'sam2',
        null,
        [
          _anchor('sam', verified: false),
          _anchor('sam.official', verified: true, userId: 'u-sam-verified'),
          _anchor('sam22', verified: false),
        ],
        peerUserId: 'u-peer');
    expect(best!.anchor.userId, 'u-sam-verified');
    expect(best.rule, LookalikeRule.skeleton);
    final byRule = findLookalike(
        'jiwoo.kr',
        null,
        [
          _anchor('jiwoo.k', verified: true),
          _anchor('jiwoo', verified: false),
        ],
        peerUserId: 'u-peer');
    expect(byRule!.anchor.handle, 'jiwoo');
    expect(byRule.rule, LookalikeRule.skeleton);
  });

  test('a handle spelling a contact\'s nickname reads as that contact', () {
    // A verified @k_hj77 saved as "Hyunjin", a saved @jw.park92 as "Jiwoo Park".
    final anchors = [
      _anchor('k_hj77', name: 'Hyunjin', userId: 'u-hj'),
      _anchor('jw.park92', name: 'Jiwoo Park', verified: false, userId: 'u-jw'),
    ];
    LookalikeMatch? check(String peer) => findLookalike(peer, null, anchors, peerUserId: 'u-peer');
    for (final (peer, anchor) in [
      ('hyunjin', 'u-hj'),
      ('hyunjin.kim', 'u-hj'),
      ('hyunjin_new', 'u-hj'),
      ('hyunjin7', 'u-hj'),
      ('hyunjln', 'u-hj'),
      ('jiwoopark', 'u-jw'),
      ('jiwoo.park', 'u-jw'),
      ('park.jiwoo', 'u-jw'),
      ('jiwoo_park92', 'u-jw'),
    ]) {
      expect(check(peer)?.anchor.userId, anchor, reason: peer);
    }
    expect(check('hyunjin')!.rule, LookalikeRule.skeleton);
    expect(check('hyunjin.kim')!.rule, LookalikeRule.affix);
    // Other handles still do not match; a nickname in Hangul is no handle.
    for (final peer in ['minseo', 'hyunwoo', 'jiwon.lee', 'parkour']) {
      expect(check(peer), isNull, reason: peer);
    }
    expect(findLookalike('eomma.kr', null, [_anchor('jy.kim', name: '엄마 폰')], peerUserId: 'u-peer')?.rule,
        LookalikeRule.kinName);
    expect(findLookalike('umma', null, [_anchor('jy.kim', name: '1004')], peerUserId: 'u-peer'), isNull);
  });

  test('digits after letters, look-alike characters in an affix and a surname after a family word are caught', () {
    final anchors = [
      _anchor('jiwoo'),
      _anchor('minjun'),
      _anchor('younghee.park', name: '엄마'),
    ];
    LookalikeMatch? check(String peer) => findLookalike(peer, null, anchors, peerUserId: 'u-peer');
    for (final peer in [
      'jiwoo_k2001', 'jiwoo.x1234', 'jiwoo.lee99', 'jiwoo12345', 'minjun_k1990', //
      'jiwoo.0fficial', 'jiwoo.m0bile', 'jiwoo.ph0ne', 'jiwoo.k0rea', 'offic1al.jiwoo',
      'mom.kim', 'eomma.kim', 'mother.kim',
    ]) {
      expect(check(peer), isNotNull, reason: peer);
    }
    expect(check('jiwoo.0fficial')!.rule, LookalikeRule.skeleton);
    expect(check('eomma.kim')!.rule, LookalikeRule.kinName);
    for (final handle in ['mom.kim', 'eomma.kim', 'mother.kim']) {
      expect(isKinHandle(handle), isTrue, reason: handle);
    }
    // A family word after a name, a surname word alone, and two words after
    // a family word are no family handle.
    for (final handle in ['kim.mom', 'son.kim', 'nan.lee', 'mom.kim.lee']) {
      expect(isKinHandle(handle), isFalse, reason: handle);
    }
    // Still no match: other names, and a long digit tail on another name.
    for (final peer in ['jiwon12', 'minja1990', 'jiwoo.2001x']) {
      expect(check(peer), isNull, reason: peer);
    }
  });

  test('a parent\'s handle made of the child\'s and a family word is no copy of the child\'s', () {
    for (final (anchor, peer) in [
      ('minji', 'minji_mom'),
      ('jiwoo', 'jiwoo.appa'),
      ('jiwoo', 'jiwoomom'),
      ('jiwoo', 'eomma.jiwoo'),
      ('daniel', 'daniel.dad'),
    ]) {
      expect(findLookalike(peer, null, [_anchor(anchor, name: '민지')], peerUserId: 'u-peer'), isNull,
          reason: '$peer vs $anchor');
    }
    // Any other extra part still reads as a copy.
    expect(findLookalike('minji_kim', null, [_anchor('minji')], peerUserId: 'u-peer')?.rule, LookalikeRule.affix);
  });
}
