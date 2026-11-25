// One sender's texts in one chat, each checked with the story the same
// sender told in the day before it. The claim banner and the risk lines both
// read this, so a banner and a line never disagree.

import 'message_risk.dart';
import 'rule_risk_checker.dart';
import 'signals.dart';

/// At most this many of a sender's texts are checked, the newest.
const threadRiskTexts = 50;

/// Earlier texts count as context only from this long before a text.
const threadContextWindow = Duration(hours: 24);

/// At most this many earlier texts are context for one text.
const threadContextTexts = 4;

/// Checks [senderTexts] (one sender, one chat, oldest first). Only the last
/// [threadRiskTexts] are read; the result has one entry per text read, in
/// the same order, so it lines up with the end of [senderTexts]. Each text
/// is checked with its own relationship and with up to
/// [threadContextTexts] earlier texts of the list from the
/// [threadContextWindow] before it.
List<MessageRisk> assessThread(
  MessageRiskChecker checker,
  List<({String text, DateTime at, RiskRelationship relationship})> senderTexts, {
  bool startedByMe = false,
}) {
  final texts = senderTexts.length > threadRiskTexts
      ? senderTexts.sublist(senderTexts.length - threadRiskTexts)
      : senderTexts;
  // Each text is read once in this call, though it is context for up to
  // four later ones; nothing is kept after it returns.
  final read = <String, RiskSignals>{};
  RiskSignals signalsOf(String text) => read.putIfAbsent(text, () => detectSignals(text));
  final risks = <MessageRisk>[];
  for (var i = 0; i < texts.length; i++) {
    final current = texts[i];
    final earlier = <String>[];
    for (var j = i - 1; j >= 0 && earlier.length < threadContextTexts; j--) {
      final gap = current.at.difference(texts[j].at);
      if (gap.isNegative || gap > threadContextWindow) continue;
      earlier.insert(0, texts[j].text);
    }
    final input = MessageRiskInput(
      text: current.text,
      earlierTexts: earlier,
      relationship: current.relationship,
      startedByMe: startedByMe,
    );
    risks.add(checker is RuleRiskChecker ? checker.assessWith(input, signalsOf) : checker.assess(input));
  }
  return risks;
}
