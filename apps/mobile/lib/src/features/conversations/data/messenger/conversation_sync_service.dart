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
  // history this device already holds (see [_heldThrough]), so a backlog
  // longer than one page is fetched, and decrypted oldest first, rather than
  // skipped: one frame may skip at most 200 keys of its chain, so a frame
  // further ahead waits until the ones before it opened. It stops after
  // [_historyPagesPerSync] pages (2000 messages, as on the web); the paging
  // cursor then points at what is left, which loading older history picks
  // up, and every page ingested retries the rows still waiting, so the newer
  // ones open in order once the older ones did.
  static const _historyPageSize = 50;
  static const _historyPagesPerSync = 40;

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
  // How far each conversation's history is held without a gap: the newest
  // relayed order a history page brought in, or that the cache held opened
  // at start. A refresh pages back to it. A frame that arrived any other way
  // (live, or the ack of this device's own send) says nothing about the
  // frames before it, so a refresh never stops at one: a live frame or a
  // reply sent before the resync would otherwise leave an older backlog
  // unfetched, its frames too far ahead of their chain to open.
  final Map<String, int> _heldThrough = {};
  final Set<String> _queuedConversationIds = {};
  bool _conversationRefreshQueued = false;
  bool _hintFlushInFlight = false;
  Timer? _hintDebounce;

  bool isLoadingHistory(String conversationId) => _historyLoading.contains(conversationId);

  /// Replaces the local state with what the cache holds: conversations and
  /// messages in one read, the content lookups for all of them batched.
  Future<void> hydrate() async {
    _heldThrough.clear();
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
      // A row still waiting for key material may be a live frame whose
      // history never came; only what reached a final outcome counts. (A
      // reply of ours acked just before the app stopped, ahead of the resync
      // it raced, still counts: the cache does not say how a row arrived.)
      if (contents[message.id]?.status.isFinal ?? false) _markHeld(message);
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

    // A list fetched for an identity that signed out (or was replaced)
    // while it was on its way is dropped: it must reach neither the next
    // identity's state nor the cache that was wiped for it.
    final generation = _session.generation;
    bool stillCurrent() => generation == _session.generation && !_session.isClosed;
    final response = await _apiClient.getConversations(session.accessToken);
    if (!stillCurrent()) return;
    final fetched = _mapper.conversations(response, localHandle: session.handle);
    // Recorded before this list can drop a conversation together with the
    // only record of whom its session is with.
    await _peerBindings.bindAll({
      for (final preview in _store.conversations)
        if (preview.type == ConversationType.direct && preview.sessionState != null)
          preview.id: ConversationPeer(userId: preview.recipientBundle.userId, handle: preview.peerHandle),
    });
    final bound = await _peerBindings.all();
    if (!stillCurrent()) return;
    final overruled = await _store.replaceConversations(
      fetched,
      bound: bound,
      pin: _crypto.keepSenderKeys,
      stillCurrent: stillCurrent,
    );
    if (overruled == null || !stillCurrent()) return;
    _crypto.recordUnlistedSessions();
    for (final conversationId in overruled) {
      await _notices.write(
        conversationId,
        senderKeysKeptNotice(conversationId, conversationMessages: _store.messagesOf(conversationId), now: DateTime.now()),
      );
    }
    await _announceMemberChanges(stillCurrent);
    await _disappearing.reconcile();
  }

  // The relay decides who is in a group, and the next send seals the group's
  // keys to every member it lists. So each member it adds or removes is
  // announced in the chat, against the member set this device last showed
  // (kept in the keystore, so a change made while the app was closed is
  // announced too). A group's first listing only records its members.
  // Each change is numbered by this device, never by the relay's epoch: a
  // relay that removes a member and adds them back without moving the epoch
  // still gets a notice for each. The number is recorded with the members,
  // so a change found again after a crash between its notices and that
  // record reuses its number, and its notices are not written twice.
  Future<void> _announceMemberChanges(bool Function() stillCurrent) async {
    final recorded = await _peerBindings.groupMembers();
    if (!stillCurrent()) return;
    final localUserId = _session.userId;
    final shown = <String, GroupMembership>{};
    for (final group in _store.conversations.where((preview) => preview.type == ConversationType.group)) {
      final members = {for (final member in group.members) member.userId};
      final before = recorded[group.id];
      if (before != null && before.sameMembers(members)) continue;
      final change = before == null ? 0 : before.changes + 1;
      shown[group.id] = GroupMembership(members, changes: change);
      if (before == null) continue;
      final now = DateTime.now();
      for (final (added, userIds) in [
        (true, members.difference(before.members)),
        (false, before.members.difference(members)),
      ]) {
        for (final userId in userIds.where((userId) => userId != localUserId)) {
          await _notices.write(
            group.id,
            memberChangeNotice(group.id,
                added: added,
                userId: userId,
                change: '$change',
                conversationMessages: _store.messagesOf(group.id),
                now: now),
          );
        }
      }
    }
    if (stillCurrent()) await _peerBindings.recordGroupMembers(shown);
  }

  Future<void> syncConversation(String conversationId, {bool loadMore = false}) async {
    final session = _session.authed;
    if (session == null) {
      _store.setMessages(conversationId, []);
      return;
    }

    final generation = _session.generation;
    final knownUpTo = loadMore ? null : _heldThroughOrOldest(conversationId);
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
    final listed = fetched
        // A frame names the conversation it was sealed for; listed under
        // another one, it is the relay moving it, and it opens only there.
        .where((message) => !message.isLocalNotice && message.envelope.conversationId == conversationId)
        .toList()
      ..sort(compareMessages);
    final items = await _contents.withoutRetired(listed);
    // History fetched for an identity that is gone is dropped.
    if (generation != _session.generation || _session.isClosed) return;
    listed.forEach(_markHeld);

    _store.mergeMessages(conversationId, items);
    // Rows waiting on frames before them (a live frame that beat this sync,
    // or a backlog page whose older frames only arrived now) are retried in
    // order once this page has been decrypted.
    unawaited(_contents
        .ingestAll(items)
        .then((_) => _contents.retryPending(conversationId, _store.messagesOf(conversationId))));
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

  /// Forgets how far the previous identity's histories were held.
  void forgetHistoryMarks() => _heldThrough.clear();

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

  void _markHeld(ChatMessage message) {
    final order = message.conversationOrder;
    if (order == null || message.isLocalNotice) return;
    final conversationId = message.envelope.conversationId;
    final held = _heldThrough[conversationId];
    if (held == null || order > held) _heldThrough[conversationId] = order;
  }

  // Where a refresh of [conversationId] stops paging back. Before any
  // history of it is held, that is the oldest message this device holds;
  // with none, a refresh reads only the newest page.
  int? _heldThroughOrOldest(String conversationId) =>
      _heldThrough[conversationId] ??
      _store
          .messagesOf(conversationId)
          .where((message) => !message.isLocalNotice)
          .map((message) => message.conversationOrder)
          .nonNulls
          .fold<int?>(null, (oldest, order) => oldest == null || order < oldest ? order : oldest);
}
