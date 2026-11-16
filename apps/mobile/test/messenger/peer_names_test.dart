import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_names.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/presentation/peer_names.dart';

import '../support/memory_secure_store.dart';

// What the screens call people: the nickname the user gave a handle on this
// phone, or else the handle. The server keeps no names, so these are the
// only ones; and a nickname names the account the user talks to under that
// handle, not whatever account a listing puts under it.

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

ConversationPeer _peer(String handle, {String? userId}) => ConversationPeer(userId: userId ?? 'user-$handle', handle: handle);

void main() {
  group('PeerNames', () {
    test('a 1:1 is named by the nickname of its peer\'s handle, whatever its case', () {
      final names = PeerNames(const {'Sam': 'Sam Rivera'}, bound: {'conv-sam': _peer('sam')});
      expect(names.peerName(_direct('conv-sam', 'sam')), 'Sam Rivera');
      expect(names.nicknameOf('SAM'), 'Sam Rivera');
      expect(names.peerName(_direct('conv-tom', 'tom_walsh')), isNull);
    });

    test('a 1:1 held for its handle gets no nickname: it is another account', () {
      final held = _direct('conv-sam-2', 'sam', userId: 'user-mallory');
      final names = PeerNames(
        const {'sam': 'Sam Rivera'},
        bound: {'conv-sam': _peer('sam')},
        isHeld: (conversationId) => conversationId == held.id,
      );
      expect(names.peerName(held), isNull);
      expect(names.peerName(_direct('conv-sam', 'sam')), 'Sam Rivera');
    });

    test('a group member gets the nickname unless this phone bound that handle to another account', () {
      final names = PeerNames(const {'sam': 'Sam Rivera', 'priya': 'Priya Nair'}, bound: {'conv-sam': _peer('sam')});
      expect(names.memberTitle(const GroupMember(userId: 'user-sam', handle: 'sam')), 'Sam Rivera');
      // No 1:1 with priya: her nickname is all there is to go by.
      expect(names.memberTitle(const GroupMember(userId: 'user-priya', handle: 'priya')), 'Priya Nair');
      // Listed as @sam, but not the account the user talks to as @sam.
      expect(names.memberName(const GroupMember(userId: 'user-mallory', handle: 'sam')), isNull);
      expect(names.memberTitle(const GroupMember(userId: 'user-mallory', handle: 'sam')), '@sam');
      expect(names.memberTitle(const GroupMember(userId: 'user-omar', handle: 'omar_h')), '@omar_h');
    });

    // What the relay lists now is not what this phone bound: a bound 1:1
    // relisted under another handle, or the real 1:1 left out of the list,
    // leaves the bindings as they were.
    test('an account bound under another handle gets no nickname under this one, in a 1:1 or a group', () {
      final names = PeerNames(
        const {'sam': 'Sam Rivera'},
        bound: {'conv-sam': _peer('sam'), 'conv-mal': _peer('mallory')},
      );
      // Mallory's bound 1:1, relisted as @sam.
      expect(names.peerName(_direct('conv-mal', 'sam', userId: 'user-mallory')), isNull);
      expect(names.memberTitle(const GroupMember(userId: 'user-mallory', handle: 'sam')), '@sam');
      expect(names.peerName(_direct('conv-sam', 'sam')), 'Sam Rivera');
      // Sam's 1:1 left out of the list: the binding still names sam.
      final unlisted = PeerNames(const {'sam': 'Sam Rivera'}, bound: {'conv-sam': _peer('sam')});
      expect(unlisted.accountName('user-mallory', 'sam'), isNull);
      expect(unlisted.accountName('user-sam', 'sam'), 'Sam Rivera');
    });

    test('a handle bound to two accounts names neither, as after a held account was acknowledged', () {
      final names = PeerNames(
        const {'sam': 'Sam Rivera'},
        bound: {'conv-sam': _peer('sam'), 'conv-sam-2': _peer('sam', userId: 'user-sam-2')},
      );
      expect(names.peerName(_direct('conv-sam', 'sam')), isNull);
      expect(names.peerName(_direct('conv-sam-2', 'sam', userId: 'user-sam-2')), isNull);
    });

    test('a chat known only by its id is named by whom it is bound to, else only by a handle bound to no one', () {
      final names = PeerNames(
        const {'sam': 'Sam Rivera', 'priya': 'Priya Nair'},
        bound: {'conv-sam': _peer('sam'), 'conv-mal': _peer('mallory')},
      );
      expect(names.directName('conv-sam', 'sam'), 'Sam Rivera');
      expect(names.directName('conv-mal', 'sam'), isNull);
      expect(names.directName('conv-gone', 'sam'), isNull, reason: 'sam is bound to an account it may not be');
      expect(names.directName('conv-gone', 'priya'), 'Priya Nair');
    });
  });

  group('ContactNameBook', () {
    late SecureStorageService storage;
    late ContactNameBook book;

    setUp(() {
      storage = SecureStorageService(MemorySecureStore());
      book = ContactNameBook(ContactNicknames(storage.scoped(SecureScope.contacts)));
    });

    test('keeps what it writes in the keystore, by lower-case handle, and tells the screens', () async {
      var changes = 0;
      book.addListener(() => changes++);
      await book.write('Sam', 'Sam Rivera');
      expect(book.nicknames, {'sam': 'Sam Rivera'});
      expect(await ContactNicknames(storage.scoped(SecureScope.contacts)).readAll(), {'sam': 'Sam Rivera'});
      expect(changes, 1);

      await book.remove('sam');
      expect(book.nicknames, isEmpty);
      expect(changes, 2);
    });

    test('a read that ends after a sign-out leaves nothing behind', () async {
      await ContactNicknames(storage.scoped(SecureScope.contacts)).write('sam', 'Sam Rivera');
      final reading = book.load();
      book.forget();
      await reading;
      expect(book.nicknames, isEmpty);
    });
  });
}
