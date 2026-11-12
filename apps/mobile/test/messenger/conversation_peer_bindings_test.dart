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

  test('a binding the keystore refuses is not kept, so a held 1:1 stays held', () async {
    final refusing = _RefusingWrites();
    final bindings = ConversationPeerBindings(store: SecureStorageService(refusing).scoped(SecureScope.conversationPolicy));
    await bindings.bindAll({'conv-1': const ConversationPeer(userId: 'user-selene', handle: 'selene')});
    const listed = ConversationPeer(userId: 'user-mallory', handle: 'selene');
    expect((await bindings.holdFor('conv-2', listed))?.reason, PeerAccountHoldReason.otherAccount);

    refusing.refuse = true;
    await expectLater(bindings.acknowledge('conv-2', listed), throwsA(isA<StateError>()));

    expect((await bindings.all()).keys, ['conv-1']);
    expect((await bindings.holdFor('conv-2', listed))?.reason, PeerAccountHoldReason.otherAccount);

    // Once the keystore takes it, the acknowledgement binds as usual.
    refusing.refuse = false;
    await bindings.acknowledge('conv-2', listed);
    expect(await bindings.holdFor('conv-2', listed), isNull);
    expect(refusing.values.keys.where((key) => key.endsWith('direct_peers.v1')), hasLength(1));
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

/// A keystore that refuses writes while [refuse] is set.
class _RefusingWrites extends MemorySecureStore {
  bool refuse = false;

  @override
  Future<void> write({required String key, required String? value}) {
    if (refuse) throw StateError('keystore unavailable');
    return super.write(key: key, value: value);
  }
}
