import 'package:flutter/widgets.dart';

import '../data/conversation_models.dart';

// What the conversation list decides without a widget: which layout a width
// gets, what of its state survives a rebuild, which conversations a query
// matches and in what order, and how a hit is highlighted.

/// From this width the list keeps the open chat beside it; under it (a
/// phone, a narrow window) it is the whole screen and a chat opens on top.
bool shouldUseWideConversationLayout(double width) {
  return width >= 1120;
}

class ConversationListViewState {
  const ConversationListViewState({
    required this.query,
    required this.senderFilter,
    required this.typeFilter,
    required this.dateFilter,
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

List<ConversationPreview> filterConversationPreviews(
  List<ConversationPreview> conversations,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return conversations;
  }

  final ranked = <({int score, ConversationPreview conversation})>[];
  for (final conversation in conversations) {
    final handle = conversation.peerHandle.toLowerCase();
    final displayName = (conversation.peerDisplayName ?? '').toLowerCase();
    final matchScore = _conversationSearchScore(
      query: normalizedQuery,
      handle: handle,
      displayName: displayName,
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
  required String displayName,
}) {
  if (handle == query) {
    return 0;
  }
  if (displayName == query) {
    return 10;
  }
  if (handle.startsWith(query)) {
    return 20;
  }
  if (displayName.startsWith(query)) {
    return 30;
  }

  final handleIndex = handle.indexOf(query);
  if (handleIndex >= 0) {
    return 40 + handleIndex;
  }

  final displayIndex = displayName.indexOf(query);
  if (displayIndex >= 0) {
    return 80 + displayIndex;
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
