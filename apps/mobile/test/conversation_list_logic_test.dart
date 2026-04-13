import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';

void main() {
  test('filterConversationPreviews matches handle and display name locally', () {
    final conversations = [
      _conversation('conv-1', 'selene', 'Selene'),
      _conversation('conv-2', 'orion', 'Orion'),
    ];

    expect(
      filterConversationPreviews(conversations, 'sel'),
      hasLength(1),
    );
    expect(
      filterConversationPreviews(conversations, 'sel').single.peerHandle,
      'selene',
    );
    expect(
      filterConversationPreviews(conversations, 'orion').single.peerHandle,
      'orion',
    );
    expect(
      filterConversationPreviews(conversations, '   '),
      hasLength(2),
    );
  });

  test('filterConversationPreviews ranks exact and prefix matches before loose matches', () {
    final conversations = [
      _conversation('conv-1', 'stellar', 'Relay Sel archive'),
      _conversation('conv-2', 'selene', 'Selene'),
      _conversation('conv-3', 'orion', 'Orbital Selene Desk'),
    ];

    final results = filterConversationPreviews(conversations, 'sel');

    expect(results.map((item) => item.peerHandle).toList(), [
      'selene',
      'stellar',
      'orion',
    ]);
  });

  test('shouldUseWideConversationLayout switches at desktop breakpoint', () {
    expect(shouldUseWideConversationLayout(1119), isFalse);
    expect(shouldUseWideConversationLayout(1120), isTrue);
    expect(shouldUseWideConversationLayout(1440), isTrue);
  });

  test('issueMessageNavigationTarget emits a fresh replayable request id', () {
    final first = issueMessageNavigationTarget(
      messageId: 'msg-42',
      query: '  orbit  ',
      requestId: 1,
    );
    final second = issueMessageNavigationTarget(
      messageId: 'msg-42',
      query: 'orbit',
      requestId: 2,
    );

    expect(first.messageId, 'msg-42');
    expect(first.query, 'orbit');
    expect(first.requestId, 1);
    expect(second.messageId, 'msg-42');
    expect(second.query, 'orbit');
    expect(second.requestId, 2);
  });

  test('mergeArchiveSearchResults keeps existing order and removes duplicate message ids', () {
    final existing = [
      MessageSearchResult(
        conversationId: 'conv-1',
        messageId: 'msg-1',
        peerHandle: 'selene',
        peerDisplayName: 'Selene',
        sentAt: DateTime.utc(2026, 4, 5, 10),
        messageKind: MessageKind.text,
        isMine: true,
        bodySnippet: 'orbit one',
      ),
      MessageSearchResult(
        conversationId: 'conv-1',
        messageId: 'msg-2',
        peerHandle: 'selene',
        peerDisplayName: 'Selene',
        sentAt: DateTime.utc(2026, 4, 5, 9),
        messageKind: MessageKind.text,
        isMine: false,
        bodySnippet: 'orbit two',
      ),
    ];
    final incoming = [
      MessageSearchResult(
        conversationId: 'conv-1',
        messageId: 'msg-2',
        peerHandle: 'selene',
        peerDisplayName: 'Selene',
        sentAt: DateTime.utc(2026, 4, 5, 9),
        messageKind: MessageKind.text,
        isMine: false,
        bodySnippet: 'orbit two',
      ),
      MessageSearchResult(
        conversationId: 'conv-1',
        messageId: 'msg-3',
        peerHandle: 'selene',
        peerDisplayName: 'Selene',
        sentAt: DateTime.utc(2026, 4, 5, 8),
        messageKind: MessageKind.file,
        isMine: false,
        bodySnippet: 'orbit file',
      ),
    ];

    final merged = mergeArchiveSearchResults(existing, incoming);

    expect(merged.map((item) => item.messageId).toList(), ['msg-1', 'msg-2', 'msg-3']);
  });

  test('conversation list view state round-trips through local storage shape',
      () {
    const state = ConversationListViewState(
      query: '  orbit  ',
      selectedConversationId: 'conv-9',
      senderFilter: MessageSearchSenderFilter.theirs,
      typeFilter: MessageSearchTypeFilter.file,
      dateFilter: MessageSearchDateFilter.last30Days,
      lastNavigationRequestId: 7,
    );

    final encoded = encodeConversationListViewState(state);
    final decoded = decodeConversationListViewState(encoded);

    expect(decoded, isNotNull);
    expect(decoded!.query, 'orbit');
    expect(decoded.selectedConversationId, 'conv-9');
    expect(decoded.senderFilter, MessageSearchSenderFilter.theirs);
    expect(decoded.typeFilter, MessageSearchTypeFilter.file);
    expect(decoded.dateFilter, MessageSearchDateFilter.last30Days);
    expect(decoded.lastNavigationRequestId, 7);
  });

  test('conversation list view state decoder rejects invalid payloads', () {
    expect(decodeConversationListViewState(null), isNull);
    expect(
      decodeConversationListViewState(const <String, Object?>{
        'query': 'orbit',
        'senderFilter': 'invalid',
        'typeFilter': 'file',
        'dateFilter': 'last30Days',
      }),
      isNull,
    );
  });

  test('buildSearchHighlightTextSpans isolates repeated local matches', () {
    final spans = buildSearchHighlightTextSpans(
      text: '... orbit relay orbit window ...',
      query: 'orbit',
    );

    expect(spans.map((span) => span.text).join(), '... orbit relay orbit window ...');
    expect(
      spans.where((span) => span.text == 'orbit').length,
      2,
    );
  });

  test('buildSearchHighlightTextSpans matches case-insensitively', () {
    final spans = buildSearchHighlightTextSpans(
      text: 'Orbit relay window',
      query: 'orbit',
    );

    expect(spans.map((span) => span.text).join(), 'Orbit relay window');
    expect(spans.where((span) => span.text == 'Orbit').length, 1);
  });

  test('buildSearchHighlightTextSpans returns single span for empty query', () {
    final spans = buildSearchHighlightTextSpans(
      text: 'Orbit relay window',
      query: '',
    );

    expect(spans.length, 1);
    expect(spans.single.text, 'Orbit relay window');
  });

  test('filterConversationPreviews returns empty list when no conversations match', () {
    final conversations = [
      _conversation('conv-1', 'selene', 'Selene'),
      _conversation('conv-2', 'orion', 'Orion'),
    ];

    expect(
      filterConversationPreviews(conversations, 'zzz_no_match'),
      isEmpty,
    );
  });

  test('filterConversationPreviews handles empty input list', () {
    expect(
      filterConversationPreviews(const [], 'anything'),
      isEmpty,
    );
  });

  test('conversation list view state decoder handles missing optional fields', () {
    final decoded = decodeConversationListViewState(const <String, Object?>{
      'query': 'test',
      'senderFilter': 'all',
      'typeFilter': 'all',
      'dateFilter': 'any',
    });

    expect(decoded, isNotNull);
    expect(decoded!.query, 'test');
    expect(decoded.selectedConversationId, isNull);
  });

  test('mergeArchiveSearchResults handles empty existing list', () {
    final incoming = [
      MessageSearchResult(
        conversationId: 'conv-1',
        messageId: 'msg-1',
        peerHandle: 'selene',
        peerDisplayName: 'Selene',
        sentAt: DateTime.utc(2026, 4, 5, 10),
        messageKind: MessageKind.text,
        isMine: true,
        bodySnippet: 'orbit one',
      ),
    ];

    final merged = mergeArchiveSearchResults(const [], incoming);
    expect(merged.length, 1);
    expect(merged.single.messageId, 'msg-1');
  });
}

ConversationPreview _conversation(
  String id,
  String handle,
  String displayName,
) {
  return ConversationPreview(
    id: id,
    peerHandle: handle,
    peerDisplayName: displayName,
    recipientBundle: const KeyBundle(
      userId: 'user',
      deviceId: 'device',
      handle: 'handle',
      identityPublicKey: 'pub',
      signedPrekeyBundle: 'bundle',
    ),
    lastEnvelope: null,
    updatedAt: DateTime.utc(2026, 4, 2),
  );
}
