import '../crypto/crypto_engine.dart';

enum MessageSearchSenderFilter { all, mine, theirs }

enum MessageSearchTypeFilter { all, text, media, file, system }

enum MessageSearchDateFilter { any, last7Days, last30Days }

class MessageSearchQuery {
  const MessageSearchQuery({
    required this.query,
    this.conversationId,
    this.senderFilter = MessageSearchSenderFilter.all,
    this.typeFilter = MessageSearchTypeFilter.all,
    this.dateFilter = MessageSearchDateFilter.any,
    this.limit = 20,
    this.beforeSentAt,
    this.beforeMessageId,
  });

  final String query;
  final String? conversationId;
  final MessageSearchSenderFilter senderFilter;
  final MessageSearchTypeFilter typeFilter;
  final MessageSearchDateFilter dateFilter;
  final int limit;
  final DateTime? beforeSentAt;
  final String? beforeMessageId;

  String get normalizedQuery => query.trim().toLowerCase();

  DateTime? resolveCutoff(DateTime now) {
    return switch (dateFilter) {
      MessageSearchDateFilter.any => null,
      MessageSearchDateFilter.last7Days => now.subtract(const Duration(days: 7)),
      MessageSearchDateFilter.last30Days => now.subtract(const Duration(days: 30)),
    };
  }
}

class MessageSearchPage {
  const MessageSearchPage({
    required this.items,
    this.nextBeforeSentAt,
    this.nextBeforeMessageId,
  });

  final List<MessageSearchResult> items;
  final DateTime? nextBeforeSentAt;
  final String? nextBeforeMessageId;

  bool get hasMore => nextBeforeSentAt != null && nextBeforeMessageId != null;
}

class MessageSearchResult {
  const MessageSearchResult({
    required this.conversationId,
    required this.messageId,
    required this.peerHandle,
    required this.peerDisplayName,
    required this.sentAt,
    required this.messageKind,
    required this.isMine,
    required this.bodySnippet,
    this.conversationOrder,
  });

  final String conversationId;
  final String messageId;
  final String peerHandle;
  final String? peerDisplayName;
  final DateTime sentAt;
  final MessageKind messageKind;
  final bool isMine;
  final String bodySnippet;
  final int? conversationOrder;

  String get title => peerDisplayName ?? '@$peerHandle';
}
