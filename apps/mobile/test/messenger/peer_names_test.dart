import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_labels.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_names.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/presentation/peer_names.dart';
import 'package:veil_mobile/src/features/safety/data/blocked_accounts.dart';

import '../support/memory_secure_store.dart';

// What the screens call people: the nickname the user gave a handle on this
// phone, or else the handle. The server keeps no names, so these are the
// only ones; and a nickname names one account, the one this phone knew
// under that handle when it was saved (or else the first one listed after),
// not whatever account a listing puts under the handle later.

ConversationPreview _direct(String id, String handle, {String userId = ''}) => ConversationPreview(
      id: id,
      peerHandle: handle,
      peerDisplayName: null,
      recipientBundle: KeyBundle(
        userId: userId.isEmpty ? 'user-$handle' : userId,
        deviceId: 'dev-$handle',
        handle: handle,
        identityPublicKey: '',
        signedPrekeyBundle: '',
      ),
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 4, 7),
    );

ConversationPreview _group(String id, List<GroupMember> members) => ConversationPreview(
      id: id,
      peerHandle: members.first.handle,
      peerDisplayName: null,
      recipientBundle: _direct(id, members.first.handle).recipientBundle,
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 4, 7),
      type: ConversationType.group,
      members: members,
    );

ConversationPeer _peer(String handle, {String? userId}) => ConversationPeer(userId: userId ?? 'user-$handle', handle: handle);

/// [name], naming the account of [handle] as this file lists it.
ContactNickname _of(String handle, String name) => ContactNickname(name, userId: 'user-$handle');

void main() {
  group('PeerNames', () {
    test('a 1:1 is named by the nickname of its peer\'s handle, whatever its case, as the account it names', () {
      final names = PeerNames({'Sam': _of('sam', 'Sam Rivera')}, bound: {'conv-sam': _peer('sam')});
      expect(names.peerName(_direct('conv-sam', 'sam')), 'Sam Rivera');
      expect(names.peerName(_direct('conv-sam', 'SAM', userId: 'user-sam')), 'Sam Rivera');
      expect(names.peerName(_direct('conv-tom', 'tom_walsh')), isNull);
    });

    test('a 1:1 held for its handle gets no nickname: it is another account', () {
      final held = _direct('conv-sam-2', 'sam', userId: 'user-mallory');
      final names = PeerNames(
        {'sam': _of('sam', 'Sam Rivera')},
        bound: {'conv-sam': _peer('sam')},
        isHeld: (conversationId) => conversationId == held.id,
      );
      expect(names.peerName(held), isNull);
      expect(names.peerName(_direct('conv-sam', 'sam')), 'Sam Rivera');
    });

    // Changed on purpose: a member used to get the nickname of their handle
    // whenever this phone had bound that handle to no account, so another
    // account listed under it (one that took the handle over after the
    // first was deleted, or one a lying server put there) got it too.
    test('a group member gets the nickname only as the account it names, and not when the handle is bound to another', () {
      final names = PeerNames(
        {'sam': _of('sam', 'Sam Rivera'), 'priya': _of('priya', 'Priya Nair')},
        bound: {'conv-sam': _peer('sam')},
      );
      expect(names.memberTitle(const GroupMember(userId: 'user-sam', handle: 'sam')), 'Sam Rivera');
      // No 1:1 with priya: the nickname names her account all the same.
      expect(names.memberTitle(const GroupMember(userId: 'user-priya', handle: 'priya')), 'Priya Nair');
      // Listed as @priya, but not the account the user named.
      expect(names.memberName(const GroupMember(userId: 'user-mallory', handle: 'priya')), isNull);
      expect(names.memberTitle(const GroupMember(userId: 'user-mallory', handle: 'priya')), '@priya');
      // Listed as @sam, but not the account the user talks to as @sam.
      expect(names.memberTitle(const GroupMember(userId: 'user-mallory', handle: 'sam')), '@sam');
      expect(names.memberTitle(const GroupMember(userId: 'user-omar', handle: 'omar_h')), '@omar_h');
      // A nickname that names no account yet names no one.
      final unclaimed = PeerNames(const {'priya': ContactNickname('Priya Nair')});
      expect(unclaimed.memberTitle(const GroupMember(userId: 'user-priya', handle: 'priya')), '@priya');
      expect(unclaimed.peerName(_direct('conv-priya', 'priya')), isNull);
    });

    // What the relay lists now is not what this phone bound: a bound 1:1
    // relisted under another handle, or the real 1:1 left out of the list,
    // leaves the bindings as they were.
    test('an account bound under another handle gets no nickname under this one, in a 1:1 or a group', () {
      final names = PeerNames(
        {'sam': ContactNickname('Sam Rivera', userId: 'user-mallory')},
        bound: {'conv-mal': _peer('mallory')},
      );
      // Mallory's bound 1:1, relisted as @sam: even a nickname that names
      // her account does not call her by it under a handle she is not
      // bound under.
      expect(names.peerName(_direct('conv-mal', 'sam', userId: 'user-mallory')), isNull);
      expect(names.memberTitle(const GroupMember(userId: 'user-mallory', handle: 'sam')), '@sam');
      // Sam's 1:1 left out of the list: the binding still names sam.
      final unlisted = PeerNames({'sam': _of('sam', 'Sam Rivera')}, bound: {'conv-sam': _peer('sam')});
      expect(unlisted.accountName('user-mallory', 'sam'), isNull);
      expect(unlisted.accountName('user-sam', 'sam'), 'Sam Rivera');
    });

    test('a handle bound to two accounts names neither, as after a held account was acknowledged', () {
      final names = PeerNames(
        {'sam': _of('sam', 'Sam Rivera')},
        bound: {'conv-sam': _peer('sam'), 'conv-sam-2': _peer('sam', userId: 'user-sam-2')},
      );
      expect(names.peerName(_direct('conv-sam', 'sam')), isNull);
      expect(names.peerName(_direct('conv-sam-2', 'sam', userId: 'user-sam-2')), isNull);
    });

    test('who is typing in a group is found by their handle whatever its case, and named as the bubbles name them', () {
      final group = _group('grp', const [GroupMember(userId: 'user-sam', handle: 'sam')]);
      final names = PeerNames({'sam': _of('sam', 'Sam Rivera')});
      expect(typingMemberTitle(group, 'Sam', names), 'Sam Rivera');
      expect(typingMemberTitle(group, 'omar_h', names), '@omar_h');
    });

    test('who is typing in a group is the account the typing event names, not another under the handle in capitals', () {
      final group = _group('grp', const [
        GroupMember(userId: 'user-bob', handle: 'bob'),
        GroupMember(userId: 'user-mallory', handle: 'Bob'),
      ]);
      final names = PeerNames({'bob': _of('bob', 'Bob Smith')});
      expect(typingMemberTitle(group, 'Bob', names, userId: 'user-mallory'), '@Bob');
      expect(typingMemberTitle(group, 'bob', names, userId: 'user-bob'), 'Bob Smith');
      // Changed on purpose: an account the group does not list is no member
      // typing, so nothing is shown for it (it was "@bob").
      expect(typingMemberTitle(group, 'bob', names, userId: 'user-gone'), isNull, reason: 'an account the group does not list');
    });

    // Changed on purpose: a chat with no account used to get the nickname
    // of a handle bound to no account.
    test('a chat known only by its id is named by whom it is bound to, else by no one', () {
      final names = PeerNames(
        {'sam': _of('sam', 'Sam Rivera'), 'priya': _of('priya', 'Priya Nair')},
        bound: {'conv-sam': _peer('sam'), 'conv-mal': _peer('mallory')},
      );
      expect(names.directName('conv-sam', 'sam'), 'Sam Rivera');
      expect(names.directName('conv-mal', 'sam'), isNull);
      expect(names.directName('conv-gone', 'sam'), isNull, reason: 'no account to name');
      expect(names.directName('conv-gone', 'priya'), isNull, reason: 'no account to name');
    });
  });

  group('PeerNames.claims: the account a nickname saved with none is to name', () {
    const bob = ContactNickname('Bob Smith');

    test('the account this phone bound the handle to, listed or not', () {
      final names = PeerNames(const {'bob': bob}, bound: {'conv-ab': _peer('bob')});
      expect(names.claims(), {'bob': 'user-bob'});
      // Even when the list now shows another account under the handle.
      final relisted = PeerNames(
        const {'bob': bob},
        bound: {'conv-ab': _peer('bob')},
        listed: [_direct('conv-am', 'bob', userId: 'user-mallory')],
      );
      expect(relisted.claims(), {'bob': 'user-bob'});
    });

    test('with no binding, the one account the list shows under the handle, in a 1:1 or a group', () {
      expect(PeerNames(const {'bob': bob}, listed: [_direct('conv-ab', 'bob')]).claims(), {'bob': 'user-bob'});
      final inGroup = PeerNames(
        const {'bob': bob},
        listed: [
          _group('grp', const [GroupMember(userId: 'user-alice', handle: 'alice'), GroupMember(userId: 'user-bob', handle: 'bob')]),
        ],
        selfUserId: 'user-alice',
      );
      expect(inGroup.claims(), {'bob': 'user-bob'});
    });

    test('with no binding or chat, the account the Blocked accounts list shows under the handle', () {
      final dana = BlockedAccount(userId: 'user-dana', handle: 'dana', blockedAt: DateTime.utc(2026, 4, 7));
      const nickname = {'dana': ContactNickname('Dana Park')};
      expect(PeerNames(nickname, blocked: [dana]).claims(), {'dana': 'user-dana'});
      // Counted with the chats: another account in a chat under the handle
      // makes two, and the blocked account under another handle too, two
      // handles.
      final twoAccounts = PeerNames(nickname, blocked: [dana], listed: [_direct('conv-x', 'dana', userId: 'user-x')]);
      expect(twoAccounts.claims(), isEmpty);
      final twoHandles = PeerNames(nickname, blocked: [dana], listed: [_direct('conv-d', 'dee', userId: 'user-dana')]);
      expect(twoHandles.claims(), isEmpty);
    });

    test('none before the bindings are read: any handle may be bound then', () {
      final dana = BlockedAccount(userId: 'user-dana', handle: 'dana', blockedAt: DateTime.utc(2026, 4, 7));
      const nickname = {'dana': ContactNickname('Dana Park')};
      expect(PeerNames(nickname, blocked: [dana], bindingsRead: false).claims(), isEmpty);
      expect(
        PeerNames(nickname, listed: [_direct('conv-d', 'dana', userId: 'user-dana')], bindingsRead: false).claims(),
        isEmpty,
      );
    });

    test('none while the list shows no account, or two, under the handle', () {
      expect(PeerNames(const {'bob': bob}).claims(), isEmpty);
      final two = PeerNames(
        const {'bob': bob},
        listed: [
          _group('grp', const [GroupMember(userId: 'user-bob', handle: 'bob')]),
          _direct('conv-am', 'bob', userId: 'user-mallory'),
        ],
      );
      expect(two.claims(), isEmpty);
    });

    test('never a held 1:1\'s account, an account under another handle too, a handle no server issues, or the user', () {
      final held = PeerNames(
        const {'bob': bob},
        listed: [_direct('conv-am', 'bob', userId: 'user-mallory')],
        isHeld: (conversationId) => conversationId == 'conv-am',
      );
      expect(held.claims(), isEmpty);
      // Mallory's 1:1 is bound under her own handle.
      final boundElsewhere = PeerNames(
        const {'bob': bob},
        bound: {'conv-am': _peer('mallory')},
        listed: [_direct('conv-am', 'bob', userId: 'user-mallory')],
      );
      expect(boundElsewhere.claims(), isEmpty);
      // One list showing one account under two handles is not one an
      // honest server sends.
      final twoHandles = PeerNames(
        const {'bob': bob},
        listed: [_direct('conv-1', 'bob', userId: 'user-x'), _direct('conv-2', 'carol', userId: 'user-x')],
      );
      expect(twoHandles.claims(), isEmpty);
      expect(PeerNames(const {'bob': bob}, listed: [_direct('conv-am', 'Bob', userId: 'user-mallory')]).claims(), isEmpty);
      final self = PeerNames(
        const {'alice': ContactNickname('Me')},
        listed: [_group('grp', const [GroupMember(userId: 'user-alice', handle: 'alice')])],
        selfUserId: 'user-alice',
      );
      expect(self.claims(), isEmpty);
    });

    test('a 1:1 bound under "Bob", a handle no server issues, is no binding of @bob', () {
      final mallory = {'conv-am': _peer('Bob', userId: 'user-mallory')};
      final names = PeerNames(
        const {'bob': bob},
        bound: mallory,
        listed: [_group('grp', const [GroupMember(userId: 'user-bob', handle: 'bob')])],
      );
      expect(names.claims(), {'bob': 'user-bob'});
      expect(PeerNames(const {'bob': bob}, bound: mallory).claims(), isEmpty);
    });

    test('nothing for a nickname that names an account already', () {
      final names = PeerNames({'bob': _of('bob', 'Bob Smith')}, listed: [_direct('conv-am', 'bob', userId: 'user-mallory')]);
      expect(names.claims(), isEmpty);
    });
  });

  // A contact's sheet finds the account it blocks or reports by a lookup
  // the server answers, and calls it by a nickname that names none yet
  // only when claims could give that nickname no other account.
  group('PeerNames.mayNameUnclaimed: whether a nickname that names no account yet may call one', () {
    const bob = ContactNickname('Bob Smith');

    test('an account no list shows, under a handle nothing is bound to, as Contacts adds one', () {
      expect(PeerNames(const {'bob': bob}).mayNameUnclaimed('user-bob', 'bob'), isTrue);
    });

    test('the account the handle is bound to, or the one the list shows under it', () {
      expect(PeerNames(const {'bob': bob}, bound: {'conv-ab': _peer('bob')}).mayNameUnclaimed('user-bob', 'Bob'), isTrue);
      expect(PeerNames(const {'bob': bob}, listed: [_direct('conv-ab', 'bob')]).mayNameUnclaimed('user-bob', 'bob'), isTrue);
    });

    test('not another account than the one this phone bound the handle to', () {
      final names = PeerNames(const {'bob': bob}, bound: {'conv-ab': _peer('bob')});
      expect(names.mayNameUnclaimed('user-mallory', 'bob'), isFalse);
    });

    test('not another account than one the chats or Blocked accounts show under the handle', () {
      final inGroup = PeerNames(
        const {'bob': bob},
        listed: [_group('grp', const [GroupMember(userId: 'user-bob', handle: 'bob')])],
      );
      expect(inGroup.mayNameUnclaimed('user-mallory', 'bob'), isFalse);
      final blocked = PeerNames(
        const {'bob': bob},
        blocked: [BlockedAccount(userId: 'user-mallory', handle: 'bob', blockedAt: DateTime.utc(2026, 4, 7))],
      );
      expect(blocked.mayNameUnclaimed('user-bob', 'bob'), isFalse);
    });

    test('not an account bound or listed under another handle', () {
      expect(
        PeerNames(const {'bob': bob}, bound: {'conv-am': _peer('mallory')}).mayNameUnclaimed('user-mallory', 'bob'),
        isFalse,
      );
      expect(
        PeerNames(const {'bob': bob}, listed: [_direct('conv-am', 'mallory')]).mayNameUnclaimed('user-mallory', 'bob'),
        isFalse,
      );
    });

    test('not while a 1:1 under the handle is held, nor before the bindings are read', () {
      final held = PeerNames(
        const {'bob': bob},
        listed: [_direct('conv-am', 'bob', userId: 'user-mallory')],
        isHeld: (conversationId) => conversationId == 'conv-am',
      );
      expect(held.mayNameUnclaimed('user-mallory', 'bob'), isFalse);
      expect(PeerNames(const {'bob': bob}, bindingsRead: false).mayNameUnclaimed('user-bob', 'bob'), isFalse);
    });
  });

  group('ContactNameBook', () {
    late SecureStorageService storage;
    late ContactNameBook book;
    ContactNicknames store() => ContactNicknames(storage.scoped(SecureScope.contacts));

    setUp(() {
      storage = SecureStorageService(MemorySecureStore());
      book = ContactNameBook(store());
    });

    test('keeps what it writes in the keystore, by lower-case handle, and tells the screens', () async {
      var changes = 0;
      book.addListener(() => changes++);
      await book.write('Sam', 'Sam Rivera', anew: true);
      expect(book.nicknames, {'sam': const ContactNickname('Sam Rivera')});
      expect(await store().readAll(), {'sam': const ContactNickname('Sam Rivera')});
      expect(changes, 1);

      await book.remove('sam');
      expect(book.nicknames, isEmpty);
      expect(changes, 2);
    });

    test('a nickname is given an account once, and keeps it when changed; a contact added anew drops it', () async {
      await book.write('bob', 'Bob Smith', anew: true);
      await book.claim({'bob': 'user-bob'});
      expect(book.nicknames['bob'], const ContactNickname('Bob Smith', userId: 'user-bob'));
      // A later list shows another account under @bob: never replaced.
      await book.claim({'bob': 'user-mallory'});
      expect(book.nicknames['bob']?.userId, 'user-bob');
      // Renamed in Contacts: the same account.
      await book.write('bob', 'Bobby');
      expect(book.nicknames['bob'], const ContactNickname('Bobby', userId: 'user-bob'));
      // Added as a contact again: the handle is named anew.
      await book.write('bob', 'Robert', anew: true);
      expect(book.nicknames['bob'], const ContactNickname('Robert'));
      expect(json.decode((await storage.scoped(SecureScope.contacts).read('nicknames.v2'))!), {
        'bob': {'name': 'Robert'},
      });
    });

    test('names kept by an earlier build are read with no account, and moved over by the first write', () async {
      final scope = storage.scoped(SecureScope.contacts);
      await scope.write('nicknames.v1', json.encode({'Sam': 'Sam Rivera', 'bob': 'Bob Smith'}));
      expect(await book.load(), {'sam': const ContactNickname('Sam Rivera'), 'bob': const ContactNickname('Bob Smith')});

      await book.claim({'sam': 'user-sam'});
      expect(book.nicknames, {
        'sam': const ContactNickname('Sam Rivera', userId: 'user-sam'),
        'bob': const ContactNickname('Bob Smith'),
      });
      expect(await scope.read('nicknames.v1'), isNull);
      expect(await store().readAll(), book.nicknames);
    });

    test('a read that ends after a sign-out leaves nothing behind', () async {
      await store().write('sam', 'Sam Rivera');
      final reading = book.load();
      book.forget();
      await reading;
      expect(book.nicknames, isEmpty);
    });

    test('an account recorded while the device is wiped does not write the nicknames back', () async {
      final keystore = _HeldReads();
      storage = SecureStorageService(keystore);
      book = ContactNameBook(store());
      await book.write('bob', 'Bob Smith', anew: true);
      // The claim reads the nicknames, and the keystore is slow to answer;
      // meanwhile the device is wiped (signed out).
      final held = keystore.holdReadsOf('veil.contacts.nicknames.v2');
      final claiming = book.claim({'bob': 'user-bob'});
      await pumpEventQueue();
      final wiping = storage.wipeLocalDeviceState();
      await pumpEventQueue();
      held.complete();
      await Future.wait([claiming, wiping]);
      expect(keystore.values.keys.where((key) => key.startsWith('veil.contacts')), isEmpty);
    });
  });
}

/// A keystore whose reads of one key answer, with the value it had when
/// asked, only once the test lets them.
class _HeldReads extends MemorySecureStore {
  String? _heldKey;
  Completer<void>? _held;

  Completer<void> holdReadsOf(String key) {
    _heldKey = key;
    return _held = Completer<void>();
  }

  @override
  Future<String?> read({required String key}) async {
    final value = await super.read(key: key);
    if (key == _heldKey) await _held!.future;
    return value;
  }
}
