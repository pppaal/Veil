import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/message_risk.dart';
import 'package:veil_mobile/src/core/safety/rule_risk_checker.dart';
import 'package:veil_mobile/src/core/safety/thread_risk.dart';

void main() {
  test('earlier messages add their story only to a message that asks for something', () {
    const checker = RuleRiskChecker();
    final t0 = DateTime.utc(2026, 11, 25, 9);
    ({String text, DateTime at, RiskRelationship relationship}) text(
      String body,
      Duration after, [
      RiskRelationship relationship = RiskRelationship.unknown,
    ]) =>
        (text: body, at: t0.add(after), relationship: relationship);

    // A family story told over three messages, then the ask.
    final story = assessThread(checker, [
      text('엄마 나야', Duration.zero),
      text('폰 고장나서 새 번호야', const Duration(minutes: 1)),
      text('50만원만 보내줘', const Duration(minutes: 2)),
    ]);
    expect(story, hasLength(3));
    expect(story[0], const MessageRisk(level: RiskLevel.warn, reason: RiskReason.familyClaim));
    expect(story[1], const MessageRisk(level: RiskLevel.strong, reason: RiskReason.newPhoneClaim));
    // Alone the ask is a money ask; with the story it is the new-phone scam.
    expect(
      checker.assess(const MessageRiskInput(text: '50만원만 보내줘', relationship: RiskRelationship.unknown)),
      const MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForMoney),
    );
    expect(story[2], const MessageRisk(level: RiskLevel.strong, reason: RiskReason.newPhoneClaim));

    // A harmless follow-up inherits nothing: no ask, no carried story.
    final harmless = assessThread(checker, [
      text('엄마 나야', Duration.zero),
      text('오늘 저녁 뭐 먹어?', const Duration(minutes: 1)),
    ]);
    expect(harmless[1], MessageRisk.none);

    // Topic words are never carried: a delivery question, then a video link.
    final topic = assessThread(checker, [
      text('쿠팡 배송 언제 와', Duration.zero, RiskRelationship.known),
      text('youtube.com/watch?v=abc', const Duration(minutes: 1), RiskRelationship.known),
    ]);
    expect(topic, [MessageRisk.none, MessageRisk.none]);

    // An authority story carried into a money ask counts less than one in
    // the same message.
    final authority = assessThread(checker, [
      text('서울중앙지검 수사관입니다', Duration.zero),
      text('지금 알려드리는 계좌로 1000만원 이체하세요', const Duration(minutes: 3)),
    ]);
    expect(authority[1], const MessageRisk(level: RiskLevel.warn, reason: RiskReason.fakeAuthority));

    // Only the 24 hours before a text count.
    final stale = assessThread(checker, [
      text('엄마 나야 폰 고장났어', Duration.zero),
      text('50만원만 보내줘', const Duration(hours: 25)),
    ]);
    expect(stale[1], const MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForMoney));

    // Only the four texts before it count.
    final crowded = assessThread(checker, [
      text('엄마 나야 폰 고장났어', Duration.zero),
      for (var i = 1; i <= 4; i++) text('응', Duration(minutes: i)),
      text('50만원만 보내줘', const Duration(minutes: 5)),
    ]);
    expect(crowded.last, const MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForMoney));

    // Each text keeps the relationship it was sent under.
    final weekLater = assessThread(checker, [
      text('인증번호 알려줘', Duration.zero, RiskRelationship.unknown),
      text('인증번호 알려줘', const Duration(days: 8), RiskRelationship.verified),
    ]);
    expect(weekLater.map((r) => r.level), [RiskLevel.strong, RiskLevel.mild]);

    // A chat I started from a typed handle: the story gives no family line.
    final typed = assessThread(
      checker,
      [text('엄마 나 오늘 늦어', Duration.zero), text('엄마 나야', const Duration(minutes: 1))],
      startedByMe: true,
    );
    expect(typed, [MessageRisk.none, MessageRisk.none]);

    // At most the last fifty texts are read, lined up with the end.
    final long = assessThread(checker, [
      for (var i = 0; i < 60; i++) text('응 $i', Duration(minutes: i)),
      text('인증번호 알려줘', const Duration(minutes: 61)),
    ]);
    expect(long, hasLength(threadRiskTexts));
    expect(long.last.reason, RiskReason.asksForCode);
  });

  test('signals kept across calls make a new message cost one read, well under 200 ms for 50 long texts', () {
    const checker = RuleRiskChecker();
    final t0 = DateTime.utc(2026, 11, 25, 9);
    String long(int i) => ('send money now mom 12 https://a.co/ $i ' * 200).substring(0, 4000);
    final texts = [
      for (var i = 0; i < 50; i++)
        (text: long(i), at: t0.add(Duration(minutes: i)), relationship: RiskRelationship.unknown),
    ];
    final signals = ThreadSignals();
    final first = assessThread(checker, texts, signals: signals);
    expect(signals.reads, 50);

    // A new message: the window moves by one, and only the new text is read.
    texts.add((text: long(50), at: t0.add(const Duration(minutes: 50)), relationship: RiskRelationship.unknown));
    final watch = Stopwatch()..start();
    final again = assessThread(checker, texts, signals: signals);
    watch.stop();
    expect(signals.reads, 51, reason: 'a new message costs one read');
    expect(watch.elapsedMilliseconds, lessThan(200), reason: 'checker work for one new message');
    expect(again.sublist(0, 49), first.sublist(1), reason: 'kept signals give the same lines');

    // Without kept signals every text is read again.
    final fresh = ThreadSignals();
    assessThread(checker, texts, signals: fresh);
    expect(fresh.reads, 50);
  });

  test('a text the checker fails on gets no line, and the rest of the thread is still checked', () {
    final t0 = DateTime.utc(2026, 11, 25, 9);
    final risks = assessThread(const _Failing(), [
      (text: '인증번호 알려줘', at: t0, relationship: RiskRelationship.unknown),
      (text: 'boom', at: t0.add(const Duration(minutes: 1)), relationship: RiskRelationship.unknown),
      (text: '인증번호 알려줘 지금', at: t0.add(const Duration(minutes: 2)), relationship: RiskRelationship.unknown),
    ]);
    expect(risks[0].reason, RiskReason.asksForCode);
    expect(risks[1], MessageRisk.none);
    expect(risks[2].reason, RiskReason.asksForCode);
  });
}

// The rules, except that a text reading "boom" throws, as a bad text did in
// the link reader.
class _Failing implements MessageRiskChecker {
  const _Failing();

  @override
  MessageRisk assess(MessageRiskInput input) {
    if (input.text == 'boom') throw const FormatException('Positive input exceeds the limit of integer');
    return const RuleRiskChecker().assess(input);
  }

  @override
  MessageRisk assessFileName(String name, RiskRelationship relationship) =>
      const RuleRiskChecker().assessFileName(name, relationship);
}
