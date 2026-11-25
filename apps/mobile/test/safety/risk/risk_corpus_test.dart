// The scam checker against the corpus of written-for-the-test messages in
// corpus/: scam and evasion cases must be flagged at least at their level
// with exactly their reason, normal and everyday chat must not be flagged,
// and the relationship matrix must give exactly its level. The holdout files,
// written by a reviewer who did not read the word lists, are held to a
// recall bar instead. A miss is fixed in the rules, never in the case.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/message_risk.dart';
import 'package:veil_mobile/src/core/safety/rule_risk_checker.dart';

class _Case {
  _Case(Map<String, dynamic> json)
      : id = json['id'] as String,
        set = json['set'] as String,
        pattern = json['pattern'] as String?,
        relationship = RiskRelationship.values.byName(json['relationship'] as String),
        startedByMe = json['startedByMe'] as bool? ?? false,
        earlier = [for (final e in json['earlier'] as List? ?? const []) e as String],
        text = json['text'] as String,
        level = RiskLevel.values.byName(json['level'] as String),
        reason = json['reason'] == null ? null : RiskReason.values.byName(json['reason'] as String),
        source = json['source'] as String?;

  final String id;
  final String set;
  final String? pattern;
  final RiskRelationship relationship;
  final bool startedByMe;
  final List<String> earlier;
  final String text;
  final RiskLevel level;
  final RiskReason? reason;
  final String? source;

  MessageRiskInput get input => MessageRiskInput(
        text: text,
        earlierTexts: earlier,
        relationship: relationship,
        startedByMe: startedByMe,
      );

  @override
  String toString() => '$id (${relationship.name}) "$text"';
}

List<_Case> _load(String name) {
  final file = File('test/safety/risk/corpus/$name');
  if (!file.existsSync()) return const [];
  return [for (final c in jsonDecode(file.readAsStringSync()) as List) _Case(c as Map<String, dynamic>)];
}

void main() {
  const checker = RuleRiskChecker();
  final corpus = [..._load('ko.json'), ..._load('en.json')];

  test('every scam message in the corpus is flagged at its level and no normal message is flagged', () {
    expect(corpus, hasLength(greaterThanOrEqualTo(340)), reason: 'corpus/ko.json and corpus/en.json');
    final ids = <String>{};
    final misses = <String>[];
    final hits = <String, int>{};
    final totals = <String, int>{};
    final falsePositives = {for (final level in RiskLevel.values) level: 0};
    for (final c in corpus) {
      expect(ids.add(c.id), isTrue, reason: 'duplicate id ${c.id}');
      expect(const {'scam', 'normal', 'edge', 'evasion', 'everyday'}, contains(c.set), reason: c.id);
      final got = checker.assess(c.input);
      switch (c.set) {
        case 'scam' || 'evasion':
          expect(c.source, startsWith('https://'), reason: '${c.id} names no source page');
          final key = '${c.set} ${c.pattern}';
          totals[key] = (totals[key] ?? 0) + 1;
          if (got.level.index >= c.level.index && got.reason == c.reason) {
            hits[key] = (hits[key] ?? 0) + 1;
          } else {
            misses.add('$c: want at least ${c.level.name} ${c.reason?.name}, got $got');
          }
        case 'normal' || 'everyday':
          if (got.level != RiskLevel.none) {
            falsePositives[got.level] = falsePositives[got.level]! + 1;
            misses.add('$c: want none, got $got');
          }
        case 'edge':
          if (got.level != c.level || got.reason != c.reason) {
            misses.add('$c: want exactly ${c.level.name} ${c.reason?.name}, got $got');
          }
      }
    }
    final keys = totals.keys.toList()..sort();
    for (final key in keys) {
      // ignore: avoid_print
      print('recall $key: ${hits[key] ?? 0}/${totals[key]}');
    }
    // ignore: avoid_print
    print('false positives on normal and everyday chat: '
        '${[for (final e in falsePositives.entries) if (e.key != RiskLevel.none) '${e.key.name} ${e.value}'].join(', ')}');
    expect(misses, isEmpty, reason: misses.join('\n'));
  });

  test('the worked checks of the build spec hold exactly', () {
    const u = RiskRelationship.unknown, k = RiskRelationship.known;
    const s = RiskRelationship.saved, v = RiskRelationship.verified;
    final checks = <(RiskRelationship, bool, String, RiskLevel, RiskReason?)>[
      (u, false, '돈 좀 보내줘', RiskLevel.warn, RiskReason.asksForMoney),
      (k, false, '돈 좀 보내줘', RiskLevel.none, null),
      (u, false, '엄마 나야', RiskLevel.warn, RiskReason.familyClaim),
      (u, false, '엄마 나야 폰 고장나서 새 계정이야', RiskLevel.strong, RiskReason.newPhoneClaim),
      (u, true, '엄마 나 오늘 늦어', RiskLevel.none, null),
      (u, false, '언니 저 지민이에요', RiskLevel.none, null),
      (k, false, '엄마 10만원만 보내줘', RiskLevel.none, null),
      (k, false, '엄마 급해 10만원만 보내줘', RiskLevel.mild, RiskReason.asksForMoney),
      (k, false, '구글 기프트카드 사서 핀번호 보내줘', RiskLevel.warn, RiskReason.asksForGiftCard),
      (s, false, '인증번호 알려줘', RiskLevel.warn, RiskReason.asksForCode),
      (v, false, '인증번호 알려줘', RiskLevel.mild, RiskReason.asksForCode),
      (v, false, '팀뷰어 깔면 내가 봐 줄게', RiskLevel.mild, RiskReason.asksToInstallApp),
      (k, false, '검찰입니다 안전계좌로 이체하세요', RiskLevel.strong, RiskReason.fakeAuthority),
      (k, false, '검사비 5만원 보내줘', RiskLevel.none, null),
      (u, false, '회비 3만원씩 카카오뱅크 3333-01-1234567로 보내주세요', RiskLevel.warn, RiskReason.asksForMoney),
      (k, false, '회비 3만원씩 카카오뱅크 3333-01-1234567로 보내주세요', RiskLevel.none, null),
    ];
    for (final (relationship, startedByMe, text, level, reason) in checks) {
      final got = checker.assess(MessageRiskInput(text: text, relationship: relationship, startedByMe: startedByMe));
      expect(got, MessageRisk(level: level, reason: reason), reason: '${relationship.name} "$text"');
      final inCorpus = corpus.where((c) => c.text == text && c.relationship == relationship && c.startedByMe == startedByMe);
      expect(inCorpus, isNotEmpty, reason: 'corpus lacks ${relationship.name} "$text"');
    }
    // An app sent as a file gets the app-file line from anyone; other files
    // get none.
    expect(checker.assessFileName('update.APK', u), const MessageRisk(level: RiskLevel.strong, reason: RiskReason.appFile));
    expect(checker.assessFileName('bank.xapk', s), const MessageRisk(level: RiskLevel.warn, reason: RiskReason.appFile));
    expect(checker.assessFileName('app.apks', v), const MessageRisk(level: RiskLevel.mild, reason: RiskReason.appFile));
    expect(checker.assessFileName('lease.pdf', u), MessageRisk.none);
    // Only the first 4000 code units are read.
    expect(checker.assess(MessageRiskInput(text: '${'가' * 4000} 인증번호 알려줘', relationship: u)), MessageRisk.none);
  });

  test('the holdout set is caught at warn or higher and its normal chat is not', () {
    final holdout = [..._load('holdout_ko.json'), ..._load('holdout_en.json')];
    if (holdout.isEmpty) {
      markTestSkipped('holdout_ko.json and holdout_en.json are written by the reviewer');
      return;
    }
    var scams = 0;
    var caught = 0;
    final misses = <String>[];
    for (final c in holdout) {
      final got = checker.assess(c.input);
      if (c.set == 'scam' || c.set == 'evasion') {
        scams++;
        if (got.level.index >= RiskLevel.warn.index) {
          caught++;
        } else {
          misses.add('missed $c: got $got');
        }
      } else if (got.level.index >= RiskLevel.warn.index) {
        misses.add('flagged $c: got $got');
      }
    }
    // ignore: avoid_print
    print('holdout recall at warn: $caught/$scams');
    expect(caught * 10, greaterThanOrEqualTo(scams * 9), reason: misses.join('\n'));
    expect(misses.where((m) => m.startsWith('flagged')), isEmpty, reason: misses.join('\n'));
  });

  test('checks 1000 corpus messages in under two seconds', () {
    final watch = Stopwatch()..start();
    var n = 0;
    while (n < 1000) {
      for (final c in corpus) {
        checker.assess(c.input);
        if (++n == 1000) break;
      }
    }
    watch.stop();
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)), reason: '${watch.elapsedMilliseconds} ms');
  });
}
