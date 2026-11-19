import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/decrypted_message_cache.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/message_content_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_state_store.dart';

// Which conversations the list cannot preview yet, and the pass that fetches
// them (DecryptedMessageCache.loadUnheld).

final _now = DateTime.utc(2026, 4, 1, 12);

CryptoEnvelope _envelope(String conversationId, {DateTime? expiresAt}) => CryptoEnvelope(
      version: 'veil-envelope-v2',
      conversationId: conversationId,
      senderDeviceId: 'dev-selene',
      recipientUserId: 'user-atlas',
      ciphertext: 'ct-$conversationId',
      nonce: 'n-$conversationId',
      messageKind: MessageKind.text,
      expiresAt: expiresAt,
    );

/// A listed conversation, [minutesAgo] old; [last] false lists it without a
/// message.
ConversationPreview _conversation(String id, {int minutesAgo = 0, bool last = true, DateTime? expiresAt}) =>
    ConversationPreview(
      id: id,
      peerHandle: id,
      peerDisplayName: null,
      recipientBundle: KeyBundle(
        userId: 'user-$id',
        deviceId: '',
        handle: id,
        identityPublicKey: '',
        signedPrekeyBundle: '',
      ),
      lastEnvelope: last ? _envelope(id, expiresAt: expiresAt) : null,
      updatedAt: _now.subtract(Duration(minutes: minutesAgo)),
    );

ChatMessage _message(String conversationId) => ChatMessage(
      id: 'srv-$conversationId',
      senderDeviceId: 'dev-selene',
      sentAt: _now,
      conversationOrder: 1,
      envelope: _envelope(conversationId),
    );

Future<MessengerStateStore> _storeListing(List<ConversationPreview> conversations) async {
  final store = MessengerStateStore(onChanged: () {});
  await store.replaceConversations(conversations, bound: const {}, pin: (merged) async => (merged, <String>[]));
  return store;
}

DecryptedMessageCache _cacheOver(MessengerStateStore store) => DecryptedMessageCache(
      contents: MessageContentService(
        cache: null,
        decrypt: (envelope, {beforeCommit}) => throw StateError('nothing is decrypted here'),
        onContentStored: (_, __) {},
      ),
      store: store,
    );

void main() {
  test('only a listed last message this device never loaded, and that has not expired, waits for a fetch', () async {
    final store = await _storeListing([
      _conversation('older', minutesAgo: 30),
      _conversation('newest'),
      _conversation('no-message', minutesAgo: 5, last: false),
      _conversation('expired', minutesAgo: 10, expiresAt: _now.subtract(const Duration(seconds: 1))),
      _conversation('still-kept', minutesAgo: 15, expiresAt: _now.add(const Duration(minutes: 1))),
      _conversation('loaded', minutesAgo: 20),
      _conversation('loaded-empty', minutesAgo: 25),
    ]);
    store.mergeMessages('loaded', [_message('loaded')]);
    // Fetched before and found empty: fetching it again is the resync's job.
    store.setMessages('loaded-empty', []);

    expect(store.unloadedWithLastMessage(_now), ['newest', 'still-kept', 'older'], reason: 'newest first');
  });

  test('a pass fetches each of them once, newest first, and one that fails does not stop the rest', () async {
    final store = await _storeListing([
      _conversation('a'),
      _conversation('b', minutesAgo: 1),
      _conversation('c', minutesAgo: 2),
    ]);
    final fetched = <String>[];
    await _cacheOver(store).loadUnheld(
      (conversationId) async {
        fetched.add(conversationId);
        if (conversationId == 'b') throw StateError('relay said no');
        store.mergeMessages(conversationId, [_message(conversationId)]);
      },
      now: _now,
      stillWanted: () => true,
    );

    expect(fetched, ['a', 'b', 'c']);
    expect(store.unloadedWithLastMessage(_now), ['b'], reason: 'the one that failed waits for the next pass');
  });

  test('a pass ends after three fetches in a row failed, and when it is no longer wanted', () async {
    final listed = [for (var i = 0; i < 6; i++) _conversation('c$i', minutesAgo: i)];
    final fetched = <String>[];
    await _cacheOver(await _storeListing(listed)).loadUnheld(
      (conversationId) async {
        fetched.add(conversationId);
        throw StateError('relay unreachable');
      },
      now: _now,
      stillWanted: () => true,
    );
    expect(fetched, ['c0', 'c1', 'c2']);

    // Signed out, or another account's list, after the first fetch.
    fetched.clear();
    final store = await _storeListing(listed);
    await _cacheOver(store).loadUnheld(
      (conversationId) async {
        fetched.add(conversationId);
        store.mergeMessages(conversationId, [_message(conversationId)]);
      },
      now: _now,
      stillWanted: () => fetched.isEmpty,
    );
    expect(fetched, ['c0']);
  });

  test('one pass runs at a time, and skips what was loaded while it ran', () async {
    final store = await _storeListing([_conversation('a'), _conversation('b', minutesAgo: 1)]);
    final cache = _cacheOver(store);
    final gate = Completer<void>();
    final fetched = <String>[];
    Future<void> sync(String conversationId) async {
      fetched.add(conversationId);
      await gate.future;
      store.mergeMessages(conversationId, [_message(conversationId)]);
    }

    final first = cache.loadUnheld(sync, now: _now, stillWanted: () => true);
    await cache.loadUnheld(sync, now: _now, stillWanted: () => true);
    expect(fetched, ['a'], reason: 'the second pass found one under way and left');

    // The user opens b, or a frame of it arrives, before the pass gets there.
    store.mergeMessages('b', [_message('b')]);
    gate.complete();
    await first;
    expect(fetched, ['a']);

    // Once the pass is over, another may run.
    final again = await _storeListing([_conversation('z')]);
    final calls = <String>[];
    final other = _cacheOver(again);
    await other.loadUnheld((id) async => calls.add(id), now: _now, stillWanted: () => true);
    await other.loadUnheld((id) async => calls.add(id), now: _now, stillWanted: () => true);
    expect(calls, ['z', 'z']);
  });
}
