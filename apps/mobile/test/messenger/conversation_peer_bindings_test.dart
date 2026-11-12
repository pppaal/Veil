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

  group('group members', () {
    test('and the count of their changes outlive the instance that recorded them', () async {
      await open().recordGroupMembers({
        'grp': const GroupMembership({'user-a', 'user-b'}, changes: 3),
      });

      final reopened = (await open().groupMembers())['grp']!;
      expect(reopened.members, {'user-a', 'user-b'});
      expect(reopened.changes, 3);
    });

    test('recorded by the first version of the record read back with no changes counted', () async {
      await open().recordGroupMembers({'grp': const GroupMembership({'user-a'})});
      final stored = platform.values.entries.singleWhere((entry) => entry.key.endsWith('group_members.v1'));
      platform.values[stored.key] = '{"grp":["user-a","user-b"]}';

      final read = (await open().groupMembers())['grp']!;
      expect(read.members, {'user-a', 'user-b'});
      expect(read.changes, 0);
    });

    test('an unreadable record is replaced, so later starts tell changes apart again', () async {
      await open().recordGroupMembers({'grp': const GroupMembership({'user-a'})});
      final stored = platform.values.entries.singleWhere((entry) => entry.key.endsWith('group_members.v1'));
      platform.values[stored.key] = '{not json';

      final bindings = open();
      expect(await bindings.groupMembers(), isEmpty);
      await bindings.recordGroupMembers({'grp': const GroupMembership({'user-a', 'user-b'}, changes: 1)});

      expect((await open().groupMembers())['grp']!.members, {'user-a', 'user-b'});
    });
  });
}
