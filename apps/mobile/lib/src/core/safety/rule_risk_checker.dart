// The scam checker as fixed rules on the phone: fourteen patterns, each a
// gate and a sum of weights over the signals of one message, adjusted by who
// sent it. Deterministic and synchronous; it sends nothing anywhere.

import 'message_risk.dart';
import 'signals.dart';

/// Scores at or above these give the level.
const mildScore = 4;
const warnScore = 6;
const strongScore = 9;

/// Added to every pattern that scores, by relationship.
const relationshipAdjustment = {
  RiskRelationship.unknown: 3,
  RiskRelationship.changed: 3,
  RiskRelationship.known: 0,
  RiskRelationship.saved: -1,
  RiskRelationship.verified: -2,
};

/// When two patterns score the same, the reason comes from the first here.
const reasonOrder = [
  RiskReason.fakeAuthority,
  RiskReason.appFile,
  RiskReason.newPhoneClaim,
  RiskReason.familyClaim,
  RiskReason.asksForCode,
  RiskReason.asksForGiftCard,
  RiskReason.asksForId,
  RiskReason.asksForMoney,
  RiskReason.asksToInstallApp,
  RiskReason.lookalikeLink,
  RiskReason.fakeBank,
  RiskReason.fakeDelivery,
  RiskReason.fakeGovernment,
  RiskReason.investment,
  RiskReason.hiddenLink,
];

typedef _Who = ({RiskRelationship relationship, bool startedByMe});

/// One pattern: which action signals let it read earlier texts, and its
/// score (0 when its gate is shut) and reason for a set of signals.
class _Pattern {
  const _Pattern(this.actions, this.score, this.reason);

  final Set<Signal> actions;
  final int Function(Set<Signal> s, _Who who) score;
  final RiskReason Function(Set<Signal> s) reason;
}

bool _notTrusted(_Who who) =>
    who.relationship == RiskRelationship.unknown || who.relationship == RiskRelationship.changed;

int _sum(Set<Signal> s, Map<Signal, int> weights) {
  var total = 0;
  weights.forEach((signal, weight) {
    if (s.contains(signal)) total += weight;
  });
  return total;
}

final _patterns = <_Pattern>[
  // P1 identity claim.
  _Pattern(
    {Signal.moneyAsk, Signal.giftAsk, Signal.codeAsk, Signal.idAsk, Signal.remote},
    (s, who) {
      final notTrusted = (who.relationship == RiskRelationship.unknown && !who.startedByMe) ||
          who.relationship == RiskRelationship.changed;
      final story = s.contains(Signal.deviceStory) || s.contains(Signal.newAccountClaim);
      final gate = story ||
          s.contains(Signal.kinVocative) ||
          (s.contains(Signal.meClaim) && s.contains(Signal.kin));
      if (!notTrusted || !gate) return 0;
      return _sum(s, const {
            Signal.deviceStory: 3,
            Signal.newAccountClaim: 3,
            Signal.kinVocative: 2,
            Signal.kin: 1,
            Signal.callAvoid: 2,
            Signal.moneyAsk: 3,
            Signal.giftAsk: 3,
            Signal.codeAsk: 3,
            Signal.idAsk: 3,
            Signal.remote: 2,
            Signal.urgency: 1,
          }) +
          (story && s.contains(Signal.socialKin) ? 1 : 0);
    },
    (s) => s.contains(Signal.deviceStory) || s.contains(Signal.newAccountClaim)
        ? RiskReason.newPhoneClaim
        : RiskReason.familyClaim,
  ),
  // P2 money.
  _Pattern(
    {Signal.moneyAsk, Signal.account},
    (s, who) {
      final act = s.contains(Signal.moneyAsk) || s.contains(Signal.account);
      final pressure = _notTrusted(who) ||
          s.contains(Signal.urgency) ||
          s.contains(Signal.secrecy) ||
          s.contains(Signal.thirdParty) ||
          s.contains(Signal.callAvoid);
      if (!act || !pressure) return 0;
      return _sum(s, const {
        Signal.moneyAsk: 3,
        Signal.account: 2,
        Signal.urgency: 1,
        Signal.secrecy: 3,
        Signal.thirdParty: 3,
        Signal.callAvoid: 2,
      });
    },
    (_) => RiskReason.asksForMoney,
  ),
  // P3 gift card.
  _Pattern(
    {Signal.giftAsk},
    (s, who) => s.contains(Signal.giftAsk)
        ? _sum(s, const {Signal.giftAsk: 5, Signal.pinBack: 2, Signal.urgency: 1, Signal.deviceStory: 2})
        : 0,
    (_) => RiskReason.asksForGiftCard,
  ),
  // P4 code.
  _Pattern(
    {Signal.codeAsk},
    (s, who) =>
        s.contains(Signal.codeAsk) ? _sum(s, const {Signal.codeAsk: 7, Signal.urgency: 1, Signal.mistake: 2}) : 0,
    (_) => RiskReason.asksForCode,
  ),
  // P5 ID.
  _Pattern(
    {Signal.idAsk},
    (s, who) {
      final pressure = _notTrusted(who) ||
          s.contains(Signal.urgency) ||
          s.contains(Signal.secrecy) ||
          s.contains(Signal.callAvoid);
      if (!s.contains(Signal.idAsk) || !pressure) return 0;
      return _sum(s, const {Signal.idAsk: 7, Signal.cardSecret: 2, Signal.urgency: 1});
    },
    (_) => RiskReason.asksForId,
  ),
  // P6 remote app.
  _Pattern(
    {Signal.remote, Signal.install},
    (s, who) => s.contains(Signal.remote)
        ? _sum(s, const {
            Signal.remote: 6,
            Signal.install: 1,
            Signal.ask: 1,
            Signal.authorityStrong: 2,
            Signal.bankPretext: 2,
          })
        : 0,
    (_) => RiskReason.asksToInstallApp,
  ),
  // P7 app file.
  _Pattern(
    {Signal.install},
    (s, who) => s.contains(Signal.apk) ? _sum(s, const {Signal.apk: 9, Signal.install: 1}) : 0,
    (_) => RiskReason.appFile,
  ),
  // P8 lookalike link.
  _Pattern(
    const {},
    (s, who) => s.contains(Signal.lookalikeDomain) ? 8 : 0,
    (_) => RiskReason.lookalikeLink,
  ),
  // P9 hidden link.
  _Pattern(
    const {},
    (s, who) => _sum(s, const {Signal.shortener: 3, Signal.riskyHost: 5, Signal.softShortener: 1}),
    (_) => RiskReason.hiddenLink,
  ),
  // P10 delivery.
  _Pattern(
    {Signal.link},
    (s, who) => s.contains(Signal.delivery) && s.contains(Signal.link)
        ? 5 +
            _sum(s, const {
              Signal.shortener: 2,
              Signal.lookalikeDomain: 3,
              Signal.apk: 3,
              Signal.addressProblem: 1,
              Signal.fee: 1,
              Signal.officialDomain: -3,
            })
        : 0,
    (_) => RiskReason.fakeDelivery,
  ),
  // P11 bank.
  _Pattern(
    {Signal.link, Signal.install, Signal.moneyAsk},
    (s, who) {
      final act = s.contains(Signal.link) ||
          s.contains(Signal.phoneToCall) ||
          s.contains(Signal.install) ||
          s.contains(Signal.moneyAsk);
      if (!s.contains(Signal.bankPretext) || !act) return 0;
      return 5 +
          _sum(s, const {
            Signal.lookalikeDomain: 3,
            Signal.shortener: 2,
            Signal.apk: 3,
            Signal.urgency: 1,
            Signal.officialDomain: -3,
          });
    },
    (_) => RiskReason.fakeBank,
  ),
  // P12 authority.
  _Pattern(
    {Signal.moneyAsk, Signal.safeAccount, Signal.account, Signal.install, Signal.link},
    (s, who) {
      final moneyAct =
          s.contains(Signal.moneyAsk) || s.contains(Signal.safeAccount) || s.contains(Signal.account);
      final strongAct = s.contains(Signal.authorityStrong) &&
          (moneyAct ||
              s.contains(Signal.secrecy) ||
              (s.contains(Signal.install) && (s.contains(Signal.linkOutsideStores) || s.contains(Signal.apk))));
      final carriedAct = s.contains(Signal.authorityCarried) && moneyAct;
      if (!strongAct && !carriedAct && !s.contains(Signal.safeAccount)) return 0;
      return (strongAct ? 9 : (carriedAct ? 5 : 0)) +
          _sum(s, const {Signal.authorityWeak: 1, Signal.safeAccount: 6, Signal.secrecy: 2, Signal.urgency: 1});
    },
    (_) => RiskReason.fakeAuthority,
  ),
  // P13 government.
  _Pattern(
    {Signal.link},
    (s, who) => s.contains(Signal.gov) && s.contains(Signal.link)
        ? 5 +
            _sum(s, const {
              Signal.lookalikeDomain: 3,
              Signal.apk: 3,
              Signal.shortener: 2,
              Signal.officialDomain: -3,
            })
        : 0,
    (_) => RiskReason.fakeGovernment,
  ),
  // P14 investment.
  _Pattern(
    {Signal.link},
    (s, who) {
      final hook = s.contains(Signal.guarantee) ||
          s.contains(Signal.highReturn) ||
          s.contains(Signal.feeFirst) ||
          s.contains(Signal.link);
      if (!s.contains(Signal.invest) || !hook) return 0;
      return 5 + _sum(s, const {Signal.guarantee: 2, Signal.highReturn: 2, Signal.feeFirst: 2});
    },
    (_) => RiskReason.investment,
  ),
];

RiskLevel levelOfScore(int score, RiskRelationship relationship) {
  final level = score >= strongScore
      ? RiskLevel.strong
      : score >= warnScore
          ? RiskLevel.warn
          : score >= mildScore
              ? RiskLevel.mild
              : RiskLevel.none;
  if (relationship == RiskRelationship.verified && level.index > RiskLevel.mild.index) return RiskLevel.mild;
  return level;
}

class RuleRiskChecker implements MessageRiskChecker {
  const RuleRiskChecker();

  /// Every signal the rules read in [text].
  RiskSignals signalsOf(String text) => detectSignals(text);

  @override
  MessageRisk assess(MessageRiskInput input) => assessWith(input, detectSignals);

  /// [assess], with the signals of each text read through [signalsOf]: a
  /// caller that checks many texts of one chat (assessThread) reads each
  /// text once.
  MessageRisk assessWith(MessageRiskInput input, RiskSignals Function(String text) signalsOf) {
    final current = signalsOf(input.text).present;
    final story = <Signal>{};
    for (final earlier in input.earlierTexts.take(4)) {
      story.addAll(signalsOf(earlier).story);
    }
    final withStory = story.isEmpty ? current : {...current, ...story};
    final who = (relationship: input.relationship, startedByMe: input.startedByMe);
    final adjustment = relationshipAdjustment[input.relationship]!;
    var bestScore = 0;
    RiskReason? bestReason;
    for (final pattern in _patterns) {
      var raw = pattern.score(current, who);
      var signals = current;
      if (!identical(withStory, current) && pattern.actions.any(current.contains)) {
        final withContext = pattern.score(withStory, who);
        if (withContext > raw) {
          raw = withContext;
          signals = withStory;
        }
      }
      if (raw <= 0) continue;
      final adjusted = raw + adjustment;
      final reason = pattern.reason(signals);
      if (bestReason == null ||
          adjusted > bestScore ||
          (adjusted == bestScore && reasonOrder.indexOf(reason) < reasonOrder.indexOf(bestReason))) {
        bestScore = adjusted;
        bestReason = reason;
      }
    }
    if (bestReason == null) return MessageRisk.none;
    final level = levelOfScore(bestScore, input.relationship);
    return level == RiskLevel.none ? MessageRisk.none : MessageRisk(level: level, reason: bestReason);
  }

  @override
  MessageRisk assessFileName(String name, RiskRelationship relationship) {
    final lower = name.trim().toLowerCase();
    if (!lower.endsWith('.apk') && !lower.endsWith('.xapk') && !lower.endsWith('.apks')) return MessageRisk.none;
    final level = levelOfScore(9 + relationshipAdjustment[relationship]!, relationship);
    return level == RiskLevel.none ? MessageRisk.none : MessageRisk(level: level, reason: RiskReason.appFile);
  }
}
