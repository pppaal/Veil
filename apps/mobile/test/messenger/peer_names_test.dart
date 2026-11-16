import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_names.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
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

void main() {
  group('PeerNames', () {
    test('a 1:1 is named by the nickname of its peer\'s handle, whatever its case', () {
      final names = PeerNames(const {'Sam': 'Sam Rivera'}, chats: [_direct('conv-sam', 'sam')]);
      expect(names.peerName(_direct('conv-sam', 'sam')), 'Sam Rivera');
      expect(names.nicknameOf('SAM'), 'Sam Rivera');
      expect(names.peerName(_direct('conv-tom', 'tom_walsh')), isNull);
    });

    test('a 1:1 held for its handle gets no nickname: it is another account', () {
      final held = _direct('conv-sam-2', 'sam', userId: 'user-mallory');
      final names = PeerNames(
        const {'sam': 'Sam Rivera'},
        chats: [_direct('conv-sam', 'sam'), held],
        isHeld: (conversationId) => conversationId == held.id,
      );
      expect(names.peerName(held), isNull);
      expect(names.peerName(_direct('conv-sam', 'sam')), 'Sam Rivera');
    });

    test('a group member gets the nickname unless a 1:1 here under that handle is with another account', () {
      final names = PeerNames(const {'sam': 'Sam Rivera', 'priya': 'Priya Nair'}, chats: [_direct('conv-sam', 'sam')]);
      expect(names.memberTitle(const GroupMember(userId: 'user-sam', handle: 'sam')), 'Sam Rivera');
      // No 1:1 with priya: her nickname is all there is to go by.
      expect(names.memberTitle(const GroupMember(userId: 'user-priya', handle: 'priya')), 'Priya Nair');
      // Listed as @sam, but not the account the user talks to as @sam.
      expect(names.memberName(const GroupMember(userId: 'user-mallory', handle: 'sam')), isNull);
      expect(names.memberTitle(const GroupMember(userId: 'user-mallory', handle: 'sam')), '@sam');
      expect(names.memberTitle(const GroupMember(userId: 'user-omar', handle: 'omar_h')), '@omar_h');
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
