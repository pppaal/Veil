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

/// The signals of each text, read once and kept: a caller that checks the
/// same chat again on every change (MessageSafety) keeps one across runs,
/// so a new message costs one read however many texts are checked with it.
/// A text whose read throws counts as having no signals, so one bad text
/// cannot stop the others from being checked.
class ThreadSignals {
  final Map<String, RiskSignals> _read = {};
  int _reads = 0;

  /// How many texts were read so far.
  int get reads => _reads;

  /// The signals of [text].
  RiskSignals of(String text) => _read.putIfAbsent(text, () {
        _reads++;
        try {
          return detectSignals(text);
        } catch (_) {
          return const RiskSignals({});
        }
      });

  /// Forgets every text but [texts].
  void keepOnly(Set<String> texts) => _read.removeWhere((text, _) => !texts.contains(text));
}

/// Checks [senderTexts] (one sender, one chat, oldest first). Only the last
/// [threadRiskTexts] are read; the result has one entry per text read, in
/// the same order, so it lines up with the end of [senderTexts]. Each text
/// is checked with its own relationship and with up to
/// [threadContextTexts] earlier texts of the list from the
/// [threadContextWindow] before it. [signals] keeps what was read for the
/// next call; without it, each text is read once in this call. A text the
/// checker fails on gets no line, and the others are checked all the same.
List<MessageRisk> assessThread(
  MessageRiskChecker checker,
  List<({String text, DateTime at, RiskRelationship relationship})> senderTexts, {
  bool startedByMe = false,
  ThreadSignals? signals,
}) {
  final texts =
      senderTexts.length > threadRiskTexts ? senderTexts.sublist(senderTexts.length - threadRiskTexts) : senderTexts;
  final read = signals ?? ThreadSignals();
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
    try {
      risks.add(checker is RuleRiskChecker ? checker.assessWith(input, read.of) : checker.assess(input));
    } catch (_) {
      risks.add(MessageRisk.none);
    }
  }
  return risks;
}
