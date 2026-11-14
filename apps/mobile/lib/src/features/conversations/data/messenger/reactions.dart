import 'dart:convert';

import '../conversation_models.dart';

/// Longest emoji a reaction may carry, in Unicode code points.
const int maxReactionEmojiCodePoints = 8;

/// The body of an end-to-end reaction: a message of inner kind reaction
/// whose body is compact JSON {"v":1,"target":id,"emoji":e,"op":"add"|"remove"}.
/// The relay sees an ordinary encrypted envelope and learns neither the
/// target nor the emoji.
class ReactionPayload {
  const ReactionPayload({required this.target, required this.emoji, required this.add});

  static const int version = 1;

  final String target;
  final String emoji;
  final bool add;

  String encode() => json.encode({'v': version, 'target': target, 'emoji': emoji, 'op': add ? 'add' : 'remove'});

  /// The payload in [body], or null when it is not one this client accepts.
  /// The peer authenticated the bytes but may still send anything.
  static ReactionPayload? tryDecode(String body) {
    final Object? decoded;
    try {
      decoded = json.decode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> || decoded['v'] != version) return null;
    final target = decoded['target'];
    final emoji = decoded['emoji'];
    final op = decoded['op'];
    if (target is! String || target.isEmpty || emoji is! String || !isAcceptableEmoji(emoji)) return null;
    if (op != 'add' && op != 'remove') return null;
    return ReactionPayload(target: target, emoji: emoji, add: op == 'add');
  }

  static bool isAcceptableEmoji(String emoji) =>
      emoji.isNotEmpty && emoji.runes.length <= maxReactionEmojiCodePoints;
}

/// Where a reaction sits in its conversation; later positions win.
class ReactionPosition implements Comparable<ReactionPosition> {
  const ReactionPosition({required this.conversationOrder, required this.sentAt});

  /// Null while the reaction is not relayed yet, which sorts it last.
  final int? conversationOrder;
  final DateTime sentAt;

  @override
  int compareTo(ReactionPosition other) {
    final mine = conversationOrder;
    final theirs = other.conversationOrder;
    if (mine != theirs) {
      if (mine == null) return 1;
      if (theirs == null) return -1;
      return mine.compareTo(theirs);
    }
    return sentAt.compareTo(other.sentAt);
  }
}

class _Choice {
  const _Choice(this.emoji, this.position);

  // Empty once the reactor withdrew it.
  final String emoji;
  final ReactionPosition position;
}

/// Every reaction seen per conversation, so the latest one of each reactor
/// on each target wins whatever order they arrive in, and a target loaded
/// after its reactions still shows them.
class ReactionLedger {
  // conversation id -> target message id -> reactor -> latest choice
  final Map<String, Map<String, Map<String, _Choice>>> _choices = {};

  /// Records a reaction; returns true when it changed what [target] shows.
  bool apply({
    required String conversationId,
    required String target,
    required String reactor,
    required String emoji,
    required bool add,
    required ReactionPosition position,
  }) {
    final byReactor = _choices.putIfAbsent(conversationId, () => {}).putIfAbsent(target, () => {});
    final current = byReactor[reactor];
    if (current != null && current.position.compareTo(position) > 0) return false;
    final next = add ? emoji : '';
    byReactor[reactor] = _Choice(next, position);
    return current?.emoji != next;
  }

  /// The emoji [reactor] currently shows on [target], if any.
  String? emojiOf(String conversationId, String target, String reactor) {
    final emoji = _choices[conversationId]?[target]?[reactor]?.emoji;
    return emoji == null || emoji.isEmpty ? null : emoji;
  }

  /// [messages] with the reactions this ledger holds for them.
  List<ChatMessage> decorate(String conversationId, List<ChatMessage> messages) {
    final targets = _choices[conversationId];
    if (targets == null) return messages;
    return [
      for (final message in messages)
        if (targets[message.id] case final byReactor?)
          message.copyWith(reactions: [
            for (final MapEntry(key: reactor, value: choice) in byReactor.entries)
              if (choice.emoji.isNotEmpty)
                Reaction(messageId: message.id, userId: reactor, emoji: choice.emoji, createdAt: choice.position.sentAt),
          ])
        else
          message,
    ];
  }

  void clear() => _choices.clear();
}
