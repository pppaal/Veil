import 'dart:async';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/network/veil_api_client.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../../../attachments/data/attachment_temp_file_store.dart';
import '../conversation_models.dart';
import 'attachment_transfer_service.dart';
import 'conversation_crypto_router.dart';
import 'conversation_peer_bindings.dart';
import 'decrypted_message_cache.dart';
import 'disappearing_messages_service.dart';
import 'local_notice.dart';
import 'local_notice_writer.dart';
import 'message_content_service.dart';
import 'message_merge.dart';
import 'messenger_api_mapper.dart';
import 'messenger_operation_runner.dart';
import 'messenger_persistence.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'outbox_service.dart';
import 'reaction_service.dart';

/// Brings the local state in line with the cache at start and with the
/// relay afterwards: the conversation list, each conversation's history,
/// and the debounced resyncs realtime hints ask for.
class ConversationSyncService {
  ConversationSyncService({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required VeilApiClient apiClient,
    required MessengerApiMapper mapper,
    required MessageContentService contents,
    required MessengerPersistence persistence,
    required ConversationCryptoRouter crypto,
    required ConversationPeerBindings peerBindings,
    required LocalNoticeWriter notices,
    required DisappearingMessagesService disappearing,
    required OutboxService outbox,
    required AttachmentTransferService attachments,
    required ReactionService reactions,
    required DecryptedMessageCache latest,
    required AttachmentTempFileStore? tempStore,
    required MessengerOperationRunner ops,
  })  : _store = store,
        _session = session,
        _apiClient = apiClient,
        _mapper = mapper,
        _contents = contents,
        _persistence = persistence,
        _crypto = crypto,
        _peerBindings = peerBindings,
        _notices = notices,
        _disappearing = disappearing,
        _outbox = outbox,
        _attachments = attachments,
        _reactions = reactions,
        _latest = latest,
        _tempStore = tempStore,
        _ops = ops;

  static const _syncHintDebounce = Duration(milliseconds: 180);

  // A refresh pages the relay's history from the newest message back to the
  // newest one this device already holds, so a backlog longer than one page
  // is fetched, and decrypted oldest first, rather than skipped: frames past
  // it would otherwise wait on skipped keys, of which a chain keeps only so
  // many. It stops after [_historyPagesPerSync] pages; the paging cursor
  // then points at what is left, which loading older history picks up.
  static const _historyPageSize = 50;
  static const _historyPagesPerSync = 10;

  final MessengerStateStore _store;
  final MessengerSessionContext _session;
  final VeilApiClient _apiClient;
  final MessengerApiMapper _mapper;
  final MessageContentService _contents;
  final MessengerPersistence _persistence;
  final ConversationCryptoRouter _crypto;
  final ConversationPeerBindings _peerBindings;
  final LocalNoticeWriter _notices;
  final DisappearingMessagesService _disappearing;
  final OutboxService _outbox;
  final AttachmentTransferService _attachments;
  final ReactionService _reactions;
  final DecryptedMessageCache _latest;
  final AttachmentTempFileStore? _tempStore;
  final MessengerOperationRunner _ops;
  final Set<String> _historyLoading = {};
  final Set<String> _queuedConversationIds = {};
  bool _conversationRefreshQueued = false;
  bool _hintFlushInFlight = false;
  Timer? _hintDebounce;

  bool isLoadingHistory(String conversationId) => _historyLoading.contains(conversationId);

  /// Replaces the local state with what the cache holds: conversations and
  /// messages in one read, the content lookups for all of them batched.
  Future<void> hydrate() async {
    final cached = await _persistence.hydrate();
    if (cached == null) return;
    final snapshot = cached.snapshot;
    final (conversations, _) = await _crypto.keepSenderKeys(snapshot.conversations);
    // Content this device already retired stays gone, even when a cached
    // copy of its message survived.
    final kept = await _contents.withoutRetired([
      for (final conversation in conversations) ...?snapshot.messages[conversation.id],
    ]);
    // Re-applied in case the app stopped before a clamped copy was saved.
    final innerExpiries = await _contents.innerExpiriesFor(kept);
    final messages = <String, List<ChatMessage>>{
      for (final conversation in conversations) conversation.id: <ChatMessage>[],
    };
    for (final message in kept) {
      messages[message.envelope.conversationId]?.add(
        withInnerExpiry(message.copyWith(isMine: message.senderDeviceId == _session.deviceId), innerExpiries[message.id]),
      );
    }
    _attachments.clear();
    _store.hydrate(
      conversations: conversations,
      messages: messages,
      paging: {
        for (final conversation in conversations)
          conversation.id: snapshot.paging[conversation.id] ?? const ConversationPagingState(),
      },
    );

    // Reactions live only in their encrypted messages; replay the ones
    // already opened and authenticated, as live delivery applies them.
    final hydrated = [for (final list in messages.values) ...list];
    final contents = await _contents.storedFor(hydrated);
    for (final message in hydrated) {
      if (contents[message.id] case final content?
          when content.kind == MessageKind.reaction && content.status == MessageContentStatus.ok) {
        _reactions.applyOpened(message, content);
      }
    }

    final keepTempPaths = _outbox.restore(cached.pending);
    await _tempStore?.cleanupOrphanedFiles(keepPaths: keepTempPaths);
    for (final conversationId in _store.loadedConversationIds.toList()) {
      unawaited(_latest.refresh(conversationId));
    }
    await _disappearing.reconcile();
    _store.changed();
  }

  /// Opens the 1:1 with [handle] (the relay returns an existing one) and
  /// returns its id; null when that failed, which is shown as usual.
  Future<String?> startDirectConversation(String handle) async {
    String? conversationId;
    await _ops.run(() async {
      final session = _session.requireAuthed();
      final result = await _apiClient.createDirectConversation(session.accessToken, handle);
      conversationId = _mapper.createdConversationId(result);
      await refreshConversations();
    });
    return conversationId;
  }

  Future<void> createGroup({
    required String name,
    required String? description,
    required List<String> memberHandles,
    required bool isPublic,
    required bool useSenderKeys,
  }) =>
      _ops.run(() async {
        final session = _session.requireAuthed();
        await _apiClient.createGroup(session.accessToken, {
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
          if (memberHandles.isNotEmpty) 'memberHandles': memberHandles,
          'isPublic': isPublic,
          'useSenderKeys': useSenderKeys,
        });
        await refreshConversations();
      });

  Future<void> refreshConversations() async {
    final session = _session.authed;
    if (session == null) {
      _store.clearConversations();
      return;
    }

    final response = await _apiClient.getConversations(session.accessToken);
    final fetched = _mapper.conversations(response, localHandle: session.handle);
    // Recorded before this list can drop a conversation together with the
    // only record of whom its session is with.
    await _peerBindings.bindAll({
      for (final preview in _store.conversations)
        if (preview.type == ConversationType.direct && preview.sessionState != null)
          preview.id: ConversationPeer(userId: preview.recipientBundle.userId, handle: preview.peerHandle),
    });
    final overruled = await _store.replaceConversations(
      fetched,
      bound: await _peerBindings.all(),
      pin: _crypto.keepSenderKeys,
    );
    _crypto.recordUnlistedSessions();
    for (final conversationId in overruled) {
      await _notices.write(
        conversationId,
        senderKeysKeptNotice(conversationId, conversationMessages: _store.messagesOf(conversationId), now: DateTime.now()),
      );
    }
    await _disappearing.reconcile();
  }

  Future<void> syncConversation(String conversationId, {bool loadMore = false}) async {
    final session = _session.authed;
    if (session == null) {
      _store.setMessages(conversationId, []);
      return;
    }

    final knownUpTo = loadMore ? null : _newestRelayedOrder(conversationId);
    final fetched = <ChatMessage>[];
    var cursor = loadMore ? _store.pagingFor(conversationId).nextCursor : null;
    String? nextCursor;
    for (var page = 0; page < (loadMore ? 1 : _historyPagesPerSync); page++) {
      final response = await _apiClient.getMessages(
        session.accessToken,
        conversationId,
        cursor: cursor,
        limit: _historyPageSize,
      );
      final (:items, nextCursor: next) = _mapper.messagePage(response, localDeviceId: _session.deviceId);
      fetched.addAll(items);
      nextCursor = next;
      final reachedKnown = knownUpTo != null && items.any((message) => (message.conversationOrder ?? 0) <= knownUpTo);
      if (nextCursor == null || reachedKnown || knownUpTo == null) break;
      cursor = nextCursor;
    }
    final items = await _contents.withoutRetired(
      fetched.where((message) => !message.isLocalNotice).toList()..sort(compareMessages),
    );

    _store.mergeMessages(conversationId, items);
    unawaited(_contents.ingestAll(items));
    _store.setPaging(
      conversationId,
      ConversationPagingState(nextCursor: nextCursor, hasMoreHistory: nextCursor != null, lastSyncedAt: DateTime.now()),
    );
  }

  Future<void> loadOlder(String conversationId) async {
    if (_historyLoading.contains(conversationId) || !_store.pagingFor(conversationId).hasMoreHistory) return;

    _historyLoading.add(conversationId);
    _store.changed();
    try {
      await syncConversation(conversationId, loadMore: true);
    } catch (error) {
      _ops.show(error);
    } finally {
      _historyLoading.remove(conversationId);
      _store.changed();
    }
  }

  /// Asks for a resync of [conversationId] (and of the conversation list
  /// when [refreshConversations]) shortly, folding bursts of hints into one.
  void scheduleSyncHint({String? conversationId, bool refreshConversations = true}) {
    if (_session.isClosed) return;
    _conversationRefreshQueued |= refreshConversations;
    if (conversationId != null && conversationId.isNotEmpty) {
      _queuedConversationIds.add(conversationId);
    }
    _hintDebounce?.cancel();
    _hintDebounce = Timer(_syncHintDebounce, () => unawaited(_flushSyncHints()));
  }

  void clearQueuedHints() => _queuedConversationIds.clear();

  void dispose() => _hintDebounce?.cancel();

  Future<void> _flushSyncHints() async {
    if (_session.isClosed || _session.authed == null || _hintFlushInFlight) return;

    _hintFlushInFlight = true;
    try {
      if (_conversationRefreshQueued) {
        _conversationRefreshQueued = false;
        await refreshConversations();
      }
      final queued = Set<String>.of(_queuedConversationIds);
      _queuedConversationIds.clear();
      final toSync = <String>{
        ..._store.loadedConversationIds,
        ..._outbox.pendingConversationIds,
        ...queued,
        if (_store.activeConversationId case final activeConversationId?) activeConversationId,
      };
      for (final conversationId in toSync) {
        if (_session.isClosed) return;
        await syncConversation(conversationId);
      }
      await _outbox.drain(ignoreRetrySchedule: true);
    } catch (error) {
      await _ops.fail(error);
    } finally {
      _hintFlushInFlight = false;
      if (_queuedConversationIds.isNotEmpty || _conversationRefreshQueued) {
        scheduleSyncHint(refreshConversations: false);
      }
    }
  }

  // The newest relayed message of [conversationId] this device holds; null
  // when it holds none, and a refresh then reads only the newest page.
  int? _newestRelayedOrder(String conversationId) => _store
      .messagesOf(conversationId)
      .where((message) => !message.isLocalNotice)
      .map((message) => message.conversationOrder)
      .nonNulls
      .fold<int?>(null, (newest, order) => newest == null || order > newest ? order : newest);
}
