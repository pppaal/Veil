import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';

import '../support/memory_secure_store.dart';

void main() {
  late MemorySecureStore platform;
  late SecureStorageService keystore;

  ConversationPeerBindings open() => ConversationPeerBindings(store: keystore.scoped(SecureScope.conversationPolicy));

  setUp(() {
    platform = MemorySecureStore();
    keystore = SecureStorageService(platform);
  });

  test('a binding outlives the instance that recorded it and is never replaced', () async {
    await open().bindAll({'conv-1': const ConversationPeer(userId: 'user-selene', handle: 'selene')});

    final reopened = open();
    await reopened.bindAll({'conv-1': const ConversationPeer(userId: 'user-lyra', handle: 'lyra')});

    expect((await reopened.all())['conv-1']!.userId, 'user-selene');
    expect((await open().all())['conv-1']!.handle, 'selene');
  });

  test('a peer without a user id binds nothing', () async {
    final bindings = open();
    await bindings.bindAll({'conv-1': const ConversationPeer(userId: '', handle: 'ghost')});

    expect(await bindings.all(), isEmpty);
  });

  test('an unreadable document is not overwritten', () async {
    await open().bindAll({'conv-1': const ConversationPeer(userId: 'user-selene', handle: 'selene')});
    final stored = platform.values.entries.singleWhere((entry) => entry.key.endsWith('direct_peers.v1'));
    platform.values[stored.key] = '{not json';

    final bindings = open();
    await bindings.bindAll({'conv-2': const ConversationPeer(userId: 'user-lyra', handle: 'lyra')});

    expect(platform.values[stored.key], '{not json');
  });
}
