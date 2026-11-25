// The scam checker's interface. The rules behind it (RuleRiskChecker) run on
// the phone and send nothing anywhere; another implementation, such as an
// on-device model, can take its place behind the same interface.

/// How strongly a message is flagged.
enum RiskLevel { none, mild, warn, strong }

/// Why a message is flagged: one key per risk line.
enum RiskReason {
  familyClaim,
  newPhoneClaim,
  asksForMoney,
  asksForGiftCard,
  asksForCode,
  asksForId,
  asksToInstallApp,
  appFile,
  lookalikeLink,
  hiddenLink,
  fakeDelivery,
  fakeBank,
  fakeAuthority,
  fakeGovernment,
  investment,
}

/// Who sent the message, as of when it was sent.
enum RiskRelationship { verified, saved, known, unknown, changed }

class MessageRiskInput {
  const MessageRiskInput({
    required this.text,
    this.earlierTexts = const [],
    required this.relationship,
    this.startedByMe = false,
  });

  final String text;

  /// The same sender's earlier texts in the same chat from the 24 hours
  /// before [text], oldest first, at most four.
  final List<String> earlierTexts;
  final RiskRelationship relationship;

  /// The user started this 1:1 from a handle they typed, or had a nickname
  /// for the handle before the chat appeared.
  final bool startedByMe;
}

class MessageRisk {
  const MessageRisk({required this.level, this.reason})
      : assert((level == RiskLevel.none) == (reason == null));

  static const none = MessageRisk(level: RiskLevel.none);

  final RiskLevel level;

  /// Null exactly when [level] is none.
  final RiskReason? reason;

  @override
  bool operator ==(Object other) => other is MessageRisk && other.level == level && other.reason == reason;

  @override
  int get hashCode => Object.hash(level, reason);

  @override
  String toString() => reason == null ? 'MessageRisk.none' : 'MessageRisk(${level.name}, ${reason!.name})';
}

abstract interface class MessageRiskChecker {
  MessageRisk assess(MessageRiskInput input);

  /// A received file, judged by its name alone (app files).
  MessageRisk assessFileName(String name, RiskRelationship relationship);
}
