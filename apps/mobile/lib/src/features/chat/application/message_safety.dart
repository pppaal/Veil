import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/safety/message_risk.dart';
import '../../../core/safety/rule_risk_checker.dart';
import '../../../core/safety/thread_risk.dart';
import '../../attachments/domain/attachment_rules.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger_providers.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import '../../safety/application/contact_trust.dart';
import '../../safety/application/risk_relationship.dart';
import '../../safety/data/safety_providers.dart';

/// The checks a message is read with: the rules on the phone. Another
/// [MessageRiskChecker] can take their place without the chat changing.
final messageRiskCheckerProvider = Provider<MessageRiskChecker>((ref) => const RuleRiskChecker());

/// What the chat with [conversationId] shows under its messages, kept while
/// the chat is open.
final messageSafetyProvider = ChangeNotifierProvider.autoDispose.family<MessageSafety, String>((ref, conversationId) {
  final messenger = ref.read(messengerControllerProvider);
  return MessageSafety(
    conversationId: conversationId,
    messenger: messenger,
    trust: ref.read(contactTrustProvider),
    checker: ref.read(messageRiskCheckerProvider),
    kept: ref.read(_keptLinesProvider('${messenger.localUserId}:$conversationId')),
  );
});

/// A line a message was shown with, and what it was worked out from.
typedef KeptLine = ({int relationship, bool startedByMe, MessageRisk risk});

// The lines of each chat's messages, kept in memory while the app runs, so
// one that falls out of the newest texts stays when the chat opens again.
// Message ids and levels only; nothing of what a message says.
final _keptLinesProvider = Provider.family<Map<String, KeptLine>, String>((ref, key) => {});

/// The risk line each message of one chat gets, and whether its links open
/// without asking.
///
/// Every message of someone else drawn as text (any kind without an
/// attachment but a reaction: the sender picks the kind) is read by
/// [assessThread], one sender at a time, the newest [threadRiskTexts] of
/// theirs, each with who the sender
/// was to this phone when it was sent (ContactTrust.relationshipAt at its
/// sentAt): a line keeps the relationship of its time, except that a
/// sender verified or changed since counts as that now, as the trust layer
/// rules. The claim banner reads the same function, so a banner and a line
/// never disagree. A file of someone else is judged by its name alone (an
/// app file). Nothing is on the user's own messages, local notices or
/// messages that did not open. The verdicts are kept per message and
/// relationship and worked out again only when a sender's texts or their
/// relationships change; each text's signals are read once while the chat
/// is open. A line stays when newer texts push its message out of the
/// newest [threadRiskTexts]: it is worked out again, with the same earlier
/// texts, only when its relationship changes.
///
/// Until the trust layer has read its document and run its baseline, and
/// while it is degraded, no message has a line: a relationship not read yet
/// would call everyone new. Nothing here is sent anywhere.
class MessageSafety extends ChangeNotifier {
  MessageSafety({
    required this.conversationId,
    required VeilMessengerController messenger,
    required ContactTrust trust,
    required MessageRiskChecker checker,
    Map<String, KeptLine>? kept,
  })  : _messenger = messenger,
        _trust = trust,
        _checker = checker,
        _kept = kept ?? {} {
    _messenger.addListener(_schedule);
    _trust.addListener(_schedule);
    _schedule();
  }

  final String conversationId;
  final VeilMessengerController _messenger;
  final ContactTrust _trust;
  final MessageRiskChecker _checker;

  Map<String, MessageRisk> _risks = const {};
  final Map<String, ({String key, Map<String, MessageRisk> verdicts})> _threads = {};
  // Each text's signals, read once while the chat is open.
  final ThreadSignals _signals = ThreadSignals();
  // The lines messages were shown with (non-none only), by message id.
  final Map<String, KeptLine> _kept;

  // A group frame names the device that sealed it: the member is the one
  // this phone pinned that device for, as the chat names its sender.
  Map<String, String> _ownerByDevice = const {};
  // The opened messages from devices not named yet when the pins were last
  // read.
  Set<String> _ownersAskedFor = const {};

  bool _scheduled = false;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// The line [message] gets: none until it is worked out, and none on
  /// the user's own messages.
  MessageRisk riskOf(ChatMessage message) => _risks[message.id] ?? MessageRisk.none;

  /// Whether a message of someone else here has a family or new-phone line
  /// at warn or higher: what opens the claim banner (ChatTrustNotices), so
  /// a banner and a line never disagree.
  bool get claims => _risks.values.any((risk) =>
      risk.level.index >= RiskLevel.warn.index &&
      (risk.reason == RiskReason.familyClaim || risk.reason == RiskReason.newPhoneClaim));

  /// How many texts had their signals read so far.
  @visibleForTesting
  int get signalReads => _signals.reads;

  /// Whether a tap on a link in [message] opens it without a sheet: the
  /// message is the user's own or its sender is verified, in a chat that
  /// is no message request. A link that looks risky asks whoever sent it.
  bool linksOpenAtOnce(ChatMessage message) {
    if (_trust.isRequest(conversationId)) return false;
    if (message.isMine) return true;
    final chat = _messenger.conversationById(conversationId);
    final userId = chat == null ? null : _senderOf(chat, message)?.userId;
    return userId != null && _trust.verified.isVerified(userId);
  }

  /// Completes once what changed so far has been worked out.
  Future<void> get settled async {
    while (_scheduled || _running) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _messenger.removeListener(_schedule);
    _trust.removeListener(_schedule);
    super.dispose();
  }

  // One run per burst of changes; a change during a run runs it again.
  void _schedule() {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() async {
      _scheduled = false;
      if (_disposed) return;
      _running = true;
      try {
        do {
          _again = false;
          await _work();
        } while (_again && !_disposed);
      } finally {
        _running = false;
      }
    });
  }

  Future<void> _work() async {
    final chat = _messenger.conversationById(conversationId);
    if (!_trust.ready || chat == null) return _publish(const {});
    final messages = [
      for (final message in _messenger.messagesFor(conversationId))
        if (!message.isMine && !message.isLocalNotice) message,
    ];
    final opened = await Future.wait(messages.map(_read));
    if (_disposed) return;
    if (chat.type == ConversationType.group) await _readOwners(chat, messages, opened);
    if (_disposed || !_trust.ready) return _publish(const {});

    final startedByMe = _trust.startedByMe(conversationId);
    final risks = <String, MessageRisk>{};
    final texts = <String, List<({String id, String text, DateTime at, RiskRelationship relationship})>>{};
    for (final (index, message) in messages.indexed) {
      final decrypted = opened[index];
      if (decrypted == null) continue;
      final sender = _senderOf(chat, message);
      final relationship = sender == null
          ? RiskRelationship.unknown
          : riskRelationshipOf(_trust.relationshipAt(sender.userId, sender.handle, chat: chat, at: message.sentAt));
      if (decrypted.attachment != null) {
        if (decrypted.messageKind != MessageKind.file) continue;
        final risk = _checker.assessFileName(sanitizeFileName(decrypted.body, fallback: ''), relationship);
        if (risk.level != RiskLevel.none) risks[message.id] = risk;
        continue;
      }
      // Drawn as text whatever its kind, a system body of someone else's
      // too; a reaction shows on its target.
      if (decrypted.messageKind == MessageKind.reaction || decrypted.body.isEmpty) continue;
      final key = sender?.userId ?? 'device:${message.senderDeviceId}';
      texts.putIfAbsent(key, () => []).add(
        (id: message.id, text: decrypted.body, at: message.sentAt, relationship: relationship),
      );
    }
    for (final MapEntry(key: sender, value: all) in texts.entries) {
      final start = math.max(0, all.length - threadRiskTexts);
      final read = all.sublist(start);
      final key = '${startedByMe ? 1 : 0}|${read.map((text) => '${text.id}:${text.relationship.index}').join(',')}';
      var thread = _threads[sender];
      if (thread == null || thread.key != key) {
        final verdicts = assessThread(
          _checker,
          [for (final text in read) (text: text.text, at: text.at, relationship: text.relationship)],
          startedByMe: startedByMe,
          signals: _signals,
        );
        thread = (key: key, verdicts: {for (final (index, text) in read.indexed) text.id: verdicts[index]});
        _threads[sender] = thread;
      }
      for (final text in read) {
        final risk = thread.verdicts[text.id]!;
        _keep(text.id, text.relationship, startedByMe, risk);
        if (risk.level != RiskLevel.none) risks[text.id] = risk;
      }
      // Older texts keep the line they were shown with; one is worked out
      // again, with the same earlier texts, only when its relationship did
      // change.
      for (var i = 0; i < start; i++) {
        final text = all[i];
        final kept = _kept[text.id];
        if (kept == null) continue;
        var risk = kept.risk;
        if (kept.relationship != text.relationship.index || kept.startedByMe != startedByMe) {
          final context = all.sublist(math.max(0, i - threadContextTexts), i + 1);
          risk = assessThread(
            _checker,
            [for (final text in context) (text: text.text, at: text.at, relationship: text.relationship)],
            startedByMe: startedByMe,
            signals: _signals,
          ).last;
          _keep(text.id, text.relationship, startedByMe, risk);
        }
        if (risk.level != RiskLevel.none) risks[text.id] = risk;
      }
    }
    _signals.keepOnly({
      for (final all in texts.values)
        for (final text in all) text.text,
    });
    _threads.removeWhere((sender, _) => !texts.containsKey(sender));
    _publish(risks);
  }

  void _keep(String id, RiskRelationship relationship, bool startedByMe, MessageRisk risk) {
    if (risk.level == RiskLevel.none) {
      _kept.remove(id);
    } else {
      _kept[id] = (relationship: relationship.index, startedByMe: startedByMe, risk: risk);
    }
  }

  // A message that opened, or null.
  Future<DecryptedMessage?> _read(ChatMessage message) async {
    try {
      final decrypted = await _messenger.decryptMessage(message);
      final opened = decrypted.status == DecryptStatus.ok || decrypted.status == DecryptStatus.legacyUnauthenticated;
      return opened ? decrypted : null;
    } catch (_) {
      return null;
    }
  }

  // The members' pinned devices, read again whenever a message from a
  // device not named yet has opened since the last read: a device's pin
  // appears once its first frame opened (a Sender Keys frame, once its
  // chain key came), which can be after the chat was first read. A message
  // that has not opened gets no line, so it asks for nothing. A read that
  // fails counts as no read: the next run asks again.
  Future<void> _readOwners(ConversationPreview chat, List<ChatMessage> messages, List<DecryptedMessage?> opened) async {
    final unnamed = {
      for (final (index, message) in messages.indexed)
        if (opened[index] != null && !_ownerByDevice.containsKey(message.senderDeviceId)) message.id,
    };
    if (unnamed.isEmpty || _ownersAskedFor.containsAll(unnamed)) return;
    final localUserId = _messenger.localUserId;
    try {
      _ownerByDevice = await _messenger.pinnedDeviceOwners([
        for (final member in chat.members)
          if (member.userId != localUserId) member.userId,
      ]);
      _ownersAskedFor = unnamed;
    } catch (_) {
      // Unnamed devices stay unnamed until a later run reads the pins:
      // their texts are read as a stranger's until then.
    }
  }

  // Who wrote [message]: the peer of a 1:1, or the group member whose
  // device sealed it; null where no member is known for that device.
  ({String userId, String handle})? _senderOf(ConversationPreview chat, ChatMessage message) {
    if (chat.type == ConversationType.direct) {
      final userId = chat.recipientBundle.userId;
      return userId.isEmpty ? null : (userId: userId, handle: chat.peerHandle);
    }
    final userId = _ownerByDevice[message.senderDeviceId];
    if (userId == null) return null;
    for (final member in chat.members) {
      if (member.userId == userId) return (userId: userId, handle: member.handle);
    }
    return null;
  }

  void _publish(Map<String, MessageRisk> risks) {
    if (_disposed || mapEquals(risks, _risks)) return;
    _risks = risks;
    notifyListeners();
  }
}
