import 'dart:async';
import 'dart:collection';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../conversation_models.dart';
import '../../../../core/storage/in_memory_message_content_store.dart';

/// Opens an envelope; [beforeCommit] runs before the engine spends the
/// message key (see [BeforeCommit]).
typedef EnvelopeDecrypter = Future<DecryptedMessage> Function(CryptoEnvelope envelope, {BeforeCommit? beforeCommit});

/// Called when content becomes bound to a relayed message: after its one
/// decrypt, or when our own content is found under its local key once the
/// relay's copy arrived.
typedef ContentStoredListener = void Function(
  ChatMessage message,
  MessageContentRecord record,
);

/// The conversation and sender the relay names a message under.
typedef _Labels = ({String conversationId, String senderDeviceId});

typedef _Read = ({_Labels labels, Future<DecryptedMessage> future});

/// Owns the plaintext of every message.
///
/// Ratchet message keys are single-use: a second decrypt of the same frame
/// yields a replay placeholder, not the text. So each inbound frame is
/// decrypted exactly once and the outcome is written to a
/// [MessageContentStore], the opened content before the engine commits the
/// step that spends its key; outbound text is stored before it is encrypted.
/// A decrypt that could not commit (`persist_failed`) stores nothing and is
/// tried again by the next read.
/// Everything that shows or searches a message reads that content and never
/// decrypts again. Rows that could not be opened yet (missing sender key or
/// session) are retried only when [retryPending] is called for their
/// conversation.
///
/// Message ids and labels come from the relay. Opened content is bound to
/// the conversation and sender it was opened under (or written by), and is
/// shown only for a message the relay still labels that way; under any other
/// labels the message reads as failed, and nothing is decrypted or replaced.
class MessageContentService {
  MessageContentService({
    required ConversationCacheService? cache,
    required EnvelopeDecrypter decrypt,
    required ContentStoredListener onContentStored,
    DateTime Function() now = DateTime.now,
  })  : _store = cache is MessageContentStore
            ? cache as MessageContentStore
            : InMemoryMessageContentStore(),
        _decrypt = decrypt,
        _onContentStored = onContentStored,
        _now = now;

  // Bounds the memo of read futures. Evicted entries are reread from the
  // store, never re-decrypted.
  static const _maxMemoEntries = 600;

  final MessageContentStore _store;
  final EnvelopeDecrypter _decrypt;
  final ContentStoredListener _onContentStored;
  // The clock disappearing expiries are checked on.
  final DateTime Function() _now;
  // Keeps one future per message alive across rebuilds so widgets keyed on
  // the future do not restart.
  // Each entry remembers the labels it was read under, so a read under other
  // labels never gets it.
  final LinkedHashMap<String, _Read> _memo = LinkedHashMap<String, _Read>();
  // Unfinished reads are tracked outside the LRU: evicting one must not let
  // a second read start a second decrypt of the same frame.
  final Map<String, _Read> _inFlight = {};
  // Keys whose last decrypt neither committed nor stored anything: their
  // memoized failure is dropped once read, so the next read decrypts again.
  final Set<String> _uncommitted = {};
  // Decrypts of one conversation run strictly one after another, in arrival
  // order, so ratchet steps and inbound session setup never interleave.
  final Map<String, Future<void>> _ingestTails = {};

  static bool _isLocalEcho(ChatMessage message) {
    final clientMessageId = message.clientMessageId;
    return clientMessageId != null && message.id == 'local-$clientMessageId';
  }

  static String _keyOf(ChatMessage message) => _isLocalEcho(message)
      ? localMessageContentKey(message.clientMessageId!)
      : message.id;

  static _Labels _labelsOf(ChatMessage message) =>
      (conversationId: message.envelope.conversationId, senderDeviceId: message.envelope.senderDeviceId);

  static bool _belongs(MessageContentRecord record, ChatMessage message) => record.belongsTo(
        conversationId: message.envelope.conversationId,
        senderDeviceId: message.envelope.senderDeviceId,
      );

  // What a message shows when the relay labels its id differently from the
  // content stored under it. Never stored: the content keeps its labels.
  static MessageContentRecord _relabelled(String key, ChatMessage message) {
    final now = DateTime.now();
    return MessageContentRecord(
      messageKey: key,
      conversationId: message.envelope.conversationId,
      body: '',
      kind: MessageKind.text,
      status: MessageContentStatus.failed,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Read-through: memo, then the store, then a first and only decrypt.
  Future<DecryptedMessage> read(ChatMessage message) {
    final key = _keyOf(message);
    final labels = _labelsOf(message);
    final memoized = _memo.remove(key);
    if (memoized != null) {
      _memo[key] = memoized;
      if (memoized.labels == labels) return memoized.future;
    }
    final inFlight = _inFlight[key];
    final Future<DecryptedMessage> future;
    if (inFlight != null && inFlight.labels == labels) {
      future = inFlight.future;
    } else if (inFlight != null) {
      // The same id under other labels: wait for the read under way, then
      // read what it stored, so the frame is never decrypted twice at once.
      future = _track(
        key,
        labels,
        inFlight.future.then<void>((_) {}, onError: (Object _) {}).then((_) => _loadOrIngest(message, key)),
      );
    } else {
      future = _track(key, labels, _loadOrIngest(message, key));
    }
    _remember(key, labels, future);
    future.whenComplete(() {
      if (_uncommitted.remove(key) && identical(_memo[key]?.future, future)) _memo.remove(key);
    }).ignore();
    return future;
  }

  /// Decrypts every message in [messages] that has no content yet, in the
  /// given order. Called when messages arrive, not when they are shown.
  Future<void> ingestAll(Iterable<ChatMessage> messages) async {
    final reads = [
      for (final message in messages)
        if (_memo[_keyOf(message)]?.labels != _labelsOf(message)) read(message),
    ];
    // A failed read stays memoized and surfaces where the message renders.
    await Future.wait(reads.map((read) => read.then<void>((_) {}, onError: (Object _) {})));
  }

  /// Retries rows of [conversationId] that are waiting for key material.
  Future<void> retryPending(String conversationId, Iterable<ChatMessage> messages) async {
    final candidates = messages
        .where((message) => message.envelope.conversationId == conversationId)
        .toList(growable: false);
    final records = await _store.getMany(candidates.map(_keyOf));
    for (final message in candidates) {
      final key = _keyOf(message);
      final record = records[key];
      if (record == null || record.status.isFinal || _inFlight.containsKey(key) || !_belongs(record, message)) {
        continue;
      }
      final labels = _labelsOf(message);
      final retry = _enqueueIngest(message, key, retryNonFinal: true)
          .then((record) => record.toDecryptedMessage());
      _memo.remove(key);
      _remember(key, labels, _track(key, labels, retry));
    }
  }

  /// Records the plaintext of an outbound message before it is encrypted.
  /// [senderDeviceId] is this device.
  Future<void> storeOutbound({
    required String conversationId,
    required String clientMessageId,
    required String senderDeviceId,
    required String body,
    required MessageKind kind,
    AttachmentReference? attachment,
    DateTime? expiresAt,
  }) async {
    final now = DateTime.now();
    final record = MessageContentRecord(
      messageKey: localMessageContentKey(clientMessageId),
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      senderDeviceId: senderDeviceId,
      body: body,
      kind: kind,
      attachment: attachment,
      innerExpiresAt: expiresAt,
      status: MessageContentStatus.ok,
      createdAt: now,
      updatedAt: now,
    );
    _memo.remove(record.messageKey);
    _remember(
      record.messageKey,
      (conversationId: conversationId, senderDeviceId: senderDeviceId),
      Future.value(record.toDecryptedMessage()),
    );
    await _store.put(record);
  }

  /// Content of a notice this device wrote itself. It was never encrypted,
  /// so it is stored as opened and no decrypt is ever attempted on it.
  Future<void> storeLocalNotice(ChatMessage notice, String code) async {
    final now = DateTime.now();
    final record = MessageContentRecord(
      messageKey: notice.id,
      conversationId: notice.envelope.conversationId,
      senderDeviceId: notice.envelope.senderDeviceId,
      body: code,
      kind: MessageKind.system,
      status: MessageContentStatus.ok,
      createdAt: now,
      updatedAt: now,
    );
    _memo.remove(notice.id);
    _remember(notice.id, _labelsOf(notice), Future.value(record.toDecryptedMessage()));
    await _store.put(record);
  }

  /// Drops the plaintext of an outbound message that never reached the
  /// outbox, so text that was never sent does not stay at rest.
  Future<void> discardOutbound(String clientMessageId) async {
    final key = localMessageContentKey(clientMessageId);
    _memo.remove(key);
    await _store.deleteExpired(_now(), messageKeys: [key]);
  }

  /// Moves an outbound message's content to the id the relay acked it under
  /// and returns it, so the caller can apply its authenticated expiry.
  Future<MessageContentRecord?> acknowledge({
    required String clientMessageId,
    required String serverMessageId,
  }) async {
    await _store.rekeyLocalToServer(
      clientMessageId: clientMessageId,
      serverMessageId: serverMessageId,
    );
    final record = await _store.get(serverMessageId);
    // The store does not move our content over content another message
    // opened under that id; then the id is not ours to show our text under.
    if (record == null || record.clientMessageId != clientMessageId) return null;
    final memoized = _memo.remove(localMessageContentKey(clientMessageId));
    // Without our own content in memory (evicted, or stored by an earlier
    // run), the server id may still be memoized with a failed attempt to
    // open our own echo that arrived without its clientMessageId.
    _memo.remove(serverMessageId);
    _remember(
      serverMessageId,
      memoized?.labels ?? (conversationId: record.conversationId, senderDeviceId: record.senderDeviceId ?? ''),
      memoized?.future ?? Future.value(record.toDecryptedMessage()),
    );
    return record;
  }

  /// Stored content for [messages], by message id. Never decrypts.
  Future<Map<String, MessageContentRecord>> storedFor(Iterable<ChatMessage> messages) async {
    final list = messages.toList(growable: false);
    final byKey = await _store.getMany(list.map(_keyOf));
    return {
      for (final message in list)
        if (byKey[_keyOf(message)] case final record? when _belongs(record, message)) message.id: record,
    };
  }

  /// [messages] minus those this device already expired. A relay that strips
  /// the outer expiry, or sweeps late, serves them again; their content is
  /// gone and their keys are spent, so they must not come back.
  Future<List<ChatMessage>> withoutRetired(List<ChatMessage> messages) async {
    final retired = await _store.retiredAmong(messages.map(_keyOf));
    return [
      for (final message in messages)
        if (!retired.contains(_keyOf(message))) message,
    ];
  }

  /// Authenticated inner expiries of [messages] that have one, by message id.
  Future<Map<String, DateTime>> innerExpiriesFor(Iterable<ChatMessage> messages) async {
    final list = messages.toList(growable: false);
    final byKey = await _store.innerExpiries(list.map(_keyOf));
    return {
      for (final message in list)
        if (byKey[_keyOf(message)] case final expiresAt?) message.id: expiresAt,
    };
  }

  Future<void> deleteExpired(DateTime now, Iterable<ChatMessage> expired) async {
    final keys = expired.map(_keyOf).toList(growable: false);
    keys.forEach(_memo.remove);
    await _store.deleteExpired(now, messageKeys: keys);
  }

  /// Forgets everything held for the signed-out identity. Durable rows are
  /// wiped with the rest of the cache by the session owner.
  void reset() {
    _memo.clear();
    _inFlight.clear();
    _ingestTails.clear();
    _uncommitted.clear();
    final store = _store;
    if (store is InMemoryMessageContentStore) {
      store.clear();
    }
  }

  Future<DecryptedMessage> _loadOrIngest(ChatMessage message, String key) async {
    final stored = await _storedRecord(message, key);
    if (stored != null) {
      return (_belongs(stored, message) ? stored : _relabelled(key, message)).toDecryptedMessage();
    }
    return (await _enqueueIngest(message, key)).toDecryptedMessage();
  }

  Future<MessageContentRecord?> _storedRecord(ChatMessage message, String key) async {
    final record = await _store.get(key);
    final clientMessageId = message.clientMessageId;
    if (record != null || !message.isMine || clientMessageId == null || key != message.id) {
      return record;
    }
    // Our own message, acked, but its content still sits under the local
    // key because the echo raced the ack.
    await _store.rekeyLocalToServer(clientMessageId: clientMessageId, serverMessageId: key);
    final rekeyed = await _store.get(key);
    if (rekeyed != null && _belongs(rekeyed, message)) {
      _onContentStored(message, rekeyed);
    }
    return rekeyed;
  }

  Future<MessageContentRecord> _enqueueIngest(
    ChatMessage message,
    String key, {
    bool retryNonFinal = false,
  }) {
    final conversationId = message.envelope.conversationId;
    final previous = _ingestTails[conversationId] ?? Future<void>.value();
    final result = previous.then((_) => _decryptAndStore(message, key, retryNonFinal));
    _ingestTails[conversationId] = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<MessageContentRecord> _decryptAndStore(
    ChatMessage message,
    String key,
    bool retryNonFinal,
  ) async {
    final existing = await _store.get(key);
    if (existing != null && !_belongs(existing, message)) {
      return _relabelled(key, message);
    }
    if (existing != null && (existing.status.isFinal || !retryNonFinal)) {
      return existing;
    }
    // Opened content is stored before the engine commits: once the commit
    // spends the message key, this row is the only copy of the text.
    MessageContentRecord? storedBeforeCommit;
    final decrypted = await _decrypt(
      message.envelope,
      beforeCommit: (opened) async {
        final record = _recordOf(message, key, opened, existing);
        await _store.put(record);
        storedBeforeCommit = record;
      },
    );
    if (storedBeforeCommit case final record?) {
      // Stored even if the commit after it failed: the frame then stays
      // decryptable, but its text is already here.
      _onContentStored(message, record);
      return record;
    }
    if (decrypted.failureReason == _persistFailed) {
      // Nothing committed and nothing stored: the frame is not spent, so it
      // is decrypted again on the next read instead of ending as failed.
      _uncommitted.add(key);
      return _recordOf(message, key, decrypted, existing);
    }
    final record = _recordOf(message, key, decrypted, existing);
    await _store.put(record);
    _onContentStored(message, record);
    return record;
  }

  static const _persistFailed = 'persist_failed';

  MessageContentRecord _recordOf(
    ChatMessage message,
    String key,
    DecryptedMessage decrypted,
    MessageContentRecord? existing,
  ) {
    final status = MessageContentStatus.of(decrypted.status);
    final opened = status == MessageContentStatus.ok || status == MessageContentStatus.legacyUnauthenticated;
    final now = DateTime.now();
    return MessageContentRecord(
      messageKey: key,
      conversationId: message.envelope.conversationId,
      clientMessageId: message.clientMessageId,
      serverMessageId: _isLocalEcho(message) ? null : message.id,
      // The frame's AEAD authenticated this sender when it opened.
      senderDeviceId: message.envelope.senderDeviceId,
      // Whatever an adapter put in a failed result is not the peer's text.
      body: opened ? decrypted.body : '',
      // Kind, expiry and attachment are trusted only from an authenticated
      // payload; a placeholder echoes unauthenticated envelope fields.
      kind: opened ? decrypted.messageKind : MessageKind.text,
      attachment: opened ? _innerAttachment(decrypted, message.envelope) : null,
      innerExpiresAt: opened ? decrypted.expiresAt : null,
      status: status,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  // Adapters fall back to the outer, server-visible pointer when the payload
  // carries none; that object is passed through as-is, so identity tells
  // the two apart.
  static AttachmentReference? _innerAttachment(
    DecryptedMessage decrypted,
    CryptoEnvelope envelope,
  ) {
    final attachment = decrypted.attachment;
    return identical(attachment, envelope.attachment) ? null : attachment;
  }

  Future<DecryptedMessage> _track(String key, _Labels labels, Future<DecryptedMessage> future) {
    _inFlight[key] = (labels: labels, future: future);
    future.whenComplete(() {
      if (identical(_inFlight[key]?.future, future)) {
        _inFlight.remove(key);
      }
    }).ignore();
    return future;
  }

  void _remember(String key, _Labels labels, Future<DecryptedMessage> future) {
    _memo[key] = (labels: labels, future: future);
    while (_memo.length > _maxMemoEntries) {
      _memo.remove(_memo.keys.first);
    }
  }
}
