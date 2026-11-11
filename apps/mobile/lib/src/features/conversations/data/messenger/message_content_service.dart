import 'dart:async';
import 'dart:collection';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../conversation_models.dart';
import 'decrypt_outcome.dart';
import 'in_memory_message_content_store.dart';

typedef EnvelopeDecrypter = Future<DecryptedMessage> Function(CryptoEnvelope envelope);

typedef ContentStoredListener = void Function(
  ChatMessage message,
  MessageContentRecord record,
);

/// Owns the plaintext of every message.
///
/// Ratchet message keys are single-use: a second decrypt of the same frame
/// yields a replay placeholder, not the text. So each inbound frame is
/// decrypted exactly once and the outcome is written to a
/// [MessageContentStore]; outbound text is stored before it is encrypted.
/// Everything that shows or searches a message reads that content and never
/// decrypts again. Rows that could not be opened yet (missing sender key or
/// session) are retried only when [retryPending] is called for their
/// conversation.
class MessageContentService {
  MessageContentService({
    required ConversationCacheService? cache,
    required EnvelopeDecrypter decrypt,
    required ContentStoredListener onContentStored,
  })  : _store = cache is MessageContentStore
            ? cache as MessageContentStore
            : InMemoryMessageContentStore(),
        _decrypt = decrypt,
        _onContentStored = onContentStored;

  // Bounds the memo of read futures. Evicted entries are reread from the
  // store, never re-decrypted.
  static const _maxMemoEntries = 600;

  final MessageContentStore _store;
  final EnvelopeDecrypter _decrypt;
  final ContentStoredListener _onContentStored;
  // Keeps one future per message alive across rebuilds so widgets keyed on
  // the future do not restart.
  final LinkedHashMap<String, Future<DecryptedMessage>> _memo =
      LinkedHashMap<String, Future<DecryptedMessage>>();
  // Unfinished reads are tracked outside the LRU: evicting one must not let
  // a second read start a second decrypt of the same frame.
  final Map<String, Future<DecryptedMessage>> _inFlight = {};
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

  /// Read-through: memo, then the store, then a first and only decrypt.
  Future<DecryptedMessage> read(ChatMessage message) {
    final key = _keyOf(message);
    final memoized = _memo.remove(key);
    if (memoized != null) {
      _memo[key] = memoized;
      return memoized;
    }
    final future = _inFlight[key] ?? _track(key, _loadOrIngest(message, key));
    _remember(key, future);
    return future;
  }

  /// Decrypts every message in [messages] that has no content yet, in the
  /// given order. Called when messages arrive, not when they are shown.
  Future<void> ingestAll(Iterable<ChatMessage> messages) async {
    final reads = [
      for (final message in messages)
        if (!_memo.containsKey(_keyOf(message))) read(message),
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
      if (record == null || record.status.isFinal || _inFlight.containsKey(key)) {
        continue;
      }
      final retry = _enqueueIngest(message, key, retryNonFinal: true)
          .then((record) => record.toDecryptedMessage());
      _memo.remove(key);
      _remember(key, _track(key, retry));
    }
  }

  /// Records the plaintext of an outbound message before it is encrypted.
  Future<void> storeOutbound({
    required String conversationId,
    required String clientMessageId,
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
      body: body,
      kind: kind,
      attachment: attachment,
      innerExpiresAt: expiresAt,
      status: MessageContentStatus.ok,
      createdAt: now,
      updatedAt: now,
    );
    _memo.remove(record.messageKey);
    _remember(record.messageKey, Future.value(record.toDecryptedMessage()));
    await _store.put(record);
  }

  /// Drops the plaintext of an outbound message that never reached the
  /// outbox, so text that was never sent does not stay at rest.
  Future<void> discardOutbound(String clientMessageId) async {
    final key = localMessageContentKey(clientMessageId);
    _memo.remove(key);
    await _store.deleteExpired(DateTime.now(), messageKeys: [key]);
  }

  /// Moves an outbound message's content to the id the relay acked it under.
  Future<void> acknowledge({
    required String clientMessageId,
    required String serverMessageId,
  }) async {
    final memoized = _memo.remove(localMessageContentKey(clientMessageId));
    if (memoized != null) {
      _remember(serverMessageId, memoized);
    }
    await _store.rekeyLocalToServer(
      clientMessageId: clientMessageId,
      serverMessageId: serverMessageId,
    );
  }

  /// Stored content for [messages], by message id. Never decrypts.
  Future<Map<String, MessageContentRecord>> storedFor(Iterable<ChatMessage> messages) async {
    final list = messages.toList(growable: false);
    final byKey = await _store.getMany(list.map(_keyOf));
    return {
      for (final message in list)
        if (byKey[_keyOf(message)] case final record?) message.id: record,
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
    final store = _store;
    if (store is InMemoryMessageContentStore) {
      store.clear();
    }
  }

  Future<DecryptedMessage> _loadOrIngest(ChatMessage message, String key) async {
    final stored = await _storedRecord(message, key);
    if (stored != null) {
      return stored.toDecryptedMessage();
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
    return _store.get(key);
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
    if (existing != null && (existing.status.isFinal || !retryNonFinal)) {
      return existing;
    }
    final decrypted = await _decrypt(message.envelope);
    final status = classifyDecryptOutcome(decrypted.body);
    final opened = status == MessageContentStatus.ok;
    final now = DateTime.now();
    final record = MessageContentRecord(
      messageKey: key,
      conversationId: message.envelope.conversationId,
      clientMessageId: message.clientMessageId,
      serverMessageId: _isLocalEcho(message) ? null : message.id,
      body: decrypted.body,
      // Kind, expiry and attachment are trusted only from an authenticated
      // payload; a placeholder echoes unauthenticated envelope fields.
      kind: opened ? decrypted.messageKind : MessageKind.text,
      attachment: opened ? _innerAttachment(decrypted, message.envelope) : null,
      innerExpiresAt: opened ? decrypted.expiresAt : null,
      status: status,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.put(record);
    _onContentStored(message, record);
    return record;
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

  Future<DecryptedMessage> _track(String key, Future<DecryptedMessage> future) {
    _inFlight[key] = future;
    future.whenComplete(() {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }).ignore();
    return future;
  }

  void _remember(String key, Future<DecryptedMessage> future) {
    _memo[key] = future;
    while (_memo.length > _maxMemoEntries) {
      _memo.remove(_memo.keys.first);
    }
  }
}
