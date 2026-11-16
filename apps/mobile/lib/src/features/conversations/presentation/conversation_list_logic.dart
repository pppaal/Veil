import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../data/conversation_models.dart';

// What the conversation list decides without a widget: which layout a width
// gets, what of its state survives a rebuild, which conversations a query
// matches and in what order, how a hit is highlighted, and where a line of
// separated parts breaks.

/// From this width the list keeps the open chat beside it; under it (a
/// phone, a narrow window) it is the whole screen and a chat opens on top.
bool shouldUseWideConversationLayout(double width) {
  return width >= 1120;
}

/// Packs parts of the given [widths] into lines no wider than [maxWidth],
/// with [separatorWidth] between two parts of one line, and returns the
/// indices of the parts of each line. A line breaks between parts, so a
/// separator is only ever drawn between two parts that share a line: none
/// is left hanging at the end of one or the start of the next. A part wider
/// than a line gets a line to itself.
List<List<int>> packPartsIntoLines(List<double> widths, {required double separatorWidth, required double maxWidth}) {
  final lines = <List<int>>[];
  var used = 0.0;
  for (final (index, width) in widths.indexed) {
    final fits = lines.isNotEmpty && used + separatorWidth + width <= maxWidth;
    if (fits) {
      lines.last.add(index);
      used += separatorWidth + width;
    } else {
      lines.add([index]);
      used = width;
    }
  }
  return lines;
}

class ConversationListViewState {
  const ConversationListViewState({
    required this.query,
    this.senderFilter = MessageSearchSenderFilter.all,
    this.typeFilter = MessageSearchTypeFilter.all,
    this.dateFilter = MessageSearchDateFilter.any,
    this.selectedConversationId,
    this.lastNavigationRequestId = 0,
  });

  final String query;
  final String? selectedConversationId;
  final MessageSearchSenderFilter senderFilter;
  final MessageSearchTypeFilter typeFilter;
  final MessageSearchDateFilter dateFilter;
  final int lastNavigationRequestId;
}

MessageNavigationTarget issueMessageNavigationTarget({
  required String messageId,
  required String query,
  required int requestId,
}) {
  return MessageNavigationTarget(
    messageId: messageId,
    requestId: requestId,
    query: query.trim(),
  );
}

List<MessageSearchResult> mergeArchiveSearchResults(
  List<MessageSearchResult> existing,
  List<MessageSearchResult> incoming,
) {
  final merged = <MessageSearchResult>[];
  final seenMessageIds = <String>{};

  for (final item in [...existing, ...incoming]) {
    if (!seenMessageIds.add(item.messageId)) {
      continue;
    }
    merged.add(item);
  }

  return merged;
}

Map<String, Object?> encodeConversationListViewState(
  ConversationListViewState state,
) {
  return <String, Object?>{
    'query': state.query.trim(),
    'selectedConversationId': state.selectedConversationId,
    'senderFilter': state.senderFilter.name,
    'typeFilter': state.typeFilter.name,
    'dateFilter': state.dateFilter.name,
    'lastNavigationRequestId': state.lastNavigationRequestId,
  };
}

ConversationListViewState? decodeConversationListViewState(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final query = raw['query'];
  final senderFilter = _messageSearchSenderFilterByName(raw['senderFilter']);
  final typeFilter = _messageSearchTypeFilterByName(raw['typeFilter']);
  final dateFilter = _messageSearchDateFilterByName(raw['dateFilter']);
  if (query is! String ||
      senderFilter == null ||
      typeFilter == null ||
      dateFilter == null) {
    return null;
  }
  final selectedConversationId = raw['selectedConversationId'];
  final lastNavigationRequestId = raw['lastNavigationRequestId'];
  return ConversationListViewState(
    query: query,
    selectedConversationId:
        selectedConversationId is String ? selectedConversationId : null,
    senderFilter: senderFilter,
    typeFilter: typeFilter,
    dateFilter: dateFilter,
    lastNavigationRequestId:
        lastNavigationRequestId is int ? lastNavigationRequestId : 0,
  );
}

MessageSearchSenderFilter? _messageSearchSenderFilterByName(Object? value) {
  return _enumByName(MessageSearchSenderFilter.values, value);
}

MessageSearchTypeFilter? _messageSearchTypeFilterByName(Object? value) {
  return _enumByName(MessageSearchTypeFilter.values, value);
}

MessageSearchDateFilter? _messageSearchDateFilterByName(Object? value) {
  return _enumByName(MessageSearchDateFilter.values, value);
}

T? _enumByName<T extends Enum>(List<T> values, Object? value) {
  if (value is! String) {
    return null;
  }
  for (final candidate in values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  return null;
}

/// The conversations [query] matches, best match first: by the handle of a
/// 1:1's peer, and by the name [nameOf] says its row shows (the nickname of
/// a 1:1's peer, a group's name). A match at the start of the handle or of
/// the name, or of a word of the name ("ri" in "Sam Rivera"), comes before
/// one inside a word ("ri" in "priya").
List<ConversationPreview> filterConversationPreviews(
  List<ConversationPreview> conversations,
  String query, {
  required String Function(ConversationPreview conversation) nameOf,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return conversations;
  }

  final ranked = <({int score, ConversationPreview conversation})>[];
  for (final conversation in conversations) {
    // A group has no handle: the one it carries is one of its members'.
    final handle = conversation.type == ConversationType.direct ? conversation.peerHandle.toLowerCase() : '';
    final name = nameOf(conversation).toLowerCase();
    final matchScore = _conversationSearchScore(
      query: normalizedQuery,
      handle: handle,
      name: name,
    );
    if (matchScore == null) {
      continue;
    }
    ranked.add((score: matchScore, conversation: conversation));
  }

  ranked.sort((a, b) {
    final scoreCompare = a.score.compareTo(b.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final updatedAtCompare =
        b.conversation.updatedAt.compareTo(a.conversation.updatedAt);
    if (updatedAtCompare != 0) {
      return updatedAtCompare;
    }
    return a.conversation.peerHandle.compareTo(b.conversation.peerHandle);
  });

  return ranked.map((entry) => entry.conversation).toList(growable: false);
}

int? _conversationSearchScore({
  required String query,
  required String handle,
  required String name,
}) {
  if (handle == query) {
    return 0;
  }
  if (name == query) {
    return 10;
  }
  if (handle.startsWith(query)) {
    return 20;
  }
  // The start of the name or of a word in it, the earlier the better, and
  // all before a handle that only holds the query.
  final word = RegExp('(^|\\s)${RegExp.escape(query)}').firstMatch(name);
  if (word != null) {
    return 30 + math.min(word.start + word.group(1)!.length, 9);
  }

  final handleIndex = handle.indexOf(query);
  if (handleIndex >= 0) {
    return 40 + handleIndex;
  }

  final nameIndex = name.indexOf(query);
  if (nameIndex >= 0) {
    return 80 + nameIndex;
  }

  return null;
}

List<TextSpan> buildSearchHighlightTextSpans({
  required String text,
  required String query,
  TextStyle? baseStyle,
  TextStyle? highlightStyle,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return <TextSpan>[TextSpan(text: text, style: baseStyle)];
  }

  final spans = <TextSpan>[];
  final lowerText = text.toLowerCase();
  var cursor = 0;
  while (cursor < text.length) {
    final matchIndex = lowerText.indexOf(normalizedQuery, cursor);
    if (matchIndex < 0) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
      break;
    }
    if (matchIndex > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, matchIndex), style: baseStyle),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(matchIndex, matchIndex + normalizedQuery.length),
        style: highlightStyle ?? baseStyle,
      ),
    );
    cursor = matchIndex + normalizedQuery.length;
  }
  return spans;
}
