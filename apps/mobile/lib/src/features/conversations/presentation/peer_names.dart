import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/identity/issued_handle.dart';
import '../../contacts/data/contact_names.dart';
import '../../contacts/data/contact_nicknames.dart';
import '../../safety/data/blocked_accounts.dart';
import '../../safety/data/safety_providers.dart';
import '../data/conversation_models.dart';
import '../data/messenger/conversation_peer_bindings.dart';
import '../data/veil_messenger_controller.dart';

/// What the screens call the people in chats: the nickname the user gave a
/// handle on this phone (ContactNameBook), or else the handle. The server
/// keeps no name for an account, so there is nothing else to show.
///
/// A nickname is kept by handle, but names one account
/// ([ContactNickname.userId]): the one this phone knew under the handle
/// when it was saved, or else the first one a list showed under it after
/// that ([claims]). Any other account listed under the handle is called by
/// the handle: one that took the handle over after the first was deleted,
/// or one a lying server puts there. The nickname's own account is called
/// by the handle too when this phone has bound the handle to another
/// account as well, or that account under another handle, when a 1:1
/// first had a session (ConversationPeerBindings); and a 1:1 held for its
/// handle (PeerAccountHold) gets no nickname, as its banner says it is not
/// the account the user knew.
class PeerNames {
  PeerNames(
    Map<String, ContactNickname> nicknames, {
    Map<String, ConversationPeer> bound = const {},
    bool Function(String conversationId)? isHeld,
    Iterable<ConversationPreview> listed = const [],
    Iterable<BlockedAccount> blocked = const [],
    String? selfUserId,
    bool bindingsRead = true,
  })  : _nicknames = {for (final MapEntry(:key, :value) in nicknames.entries) key.toLowerCase(): value},
        _bound = bound,
        _bindingsRead = bindingsRead,
        _isHeld = isHeld,
        _listed = listed,
        _blocked = blocked,
        _selfUserId = selfUserId {
    for (final peer in bound.values) {
      if (peer.userId.isEmpty) continue;
      final handle = peer.handle.toLowerCase();
      (_accountsOf[handle] ??= {}).add(peer.userId);
      (_handlesOf[peer.userId] ??= {}).add(handle);
    }
  }

  final Map<String, ContactNickname> _nicknames;
  final Map<String, ConversationPeer> _bound;
  // Whether [_bound] is what this phone recorded, not the nothing it holds
  // before the stored bindings are read.
  final bool _bindingsRead;
  final bool Function(String conversationId)? _isHeld;
  final Iterable<ConversationPreview> _listed;
  final Iterable<BlockedAccount> _blocked;
  final String? _selfUserId;
  // The accounts each handle is bound to, and the handles each account is
  // bound under (lower case).
  final Map<String, Set<String>> _accountsOf = {};
  final Map<String, Set<String>> _handlesOf = {};

  /// The name of the peer of the 1:1 [chat], or null: their handle has no
  /// nickname, it names another account, or the chat is held.
  String? peerName(ConversationPreview chat) =>
      directName(chat.id, chat.peerHandle, userId: chat.recipientBundle.userId);

  /// [peerName] for the 1:1 [conversationId] listed with [handle] and the
  /// account [userId]; without one, the account it is bound to. With
  /// neither, there is no account to name: null.
  String? directName(String conversationId, String handle, {String? userId}) {
    if (_isHeld?.call(conversationId) ?? false) return null;
    final account = (userId == null || userId.isEmpty) ? _bound[conversationId]?.userId : userId;
    if (account == null) return null;
    return accountName(account, handle);
  }

  /// The name of a group [member], or null: their handle has no nickname,
  /// or it names another account.
  String? memberName(GroupMember member) => accountName(member.userId, member.handle);

  /// The name of the account [userId], listed under [handle]: the nickname
  /// of [handle] when it names [userId], unless this phone bound [handle]
  /// to another account too or [userId] under another handle.
  String? accountName(String userId, String handle) {
    final key = handle.toLowerCase();
    final nickname = _nicknames[key];
    if (nickname == null || nickname.userId != userId) return null;
    if (_accountsOf[key]?.any((account) => account != userId) ?? false) return null;
    if (_handlesOf[userId]?.any((other) => other != key) ?? false) return null;
    return nickname.name;
  }

  /// What a group member is called: their name, or their handle with its
  /// "@".
  String memberTitle(GroupMember member) => memberName(member) ?? '@${member.handle}';

  /// The account each nickname that names none yet is to name, by handle:
  /// the account this phone bound exactly that handle to; with no binding,
  /// the one account the chats listed now (in a 1:1 not held, or as a
  /// group member) and the Blocked accounts list show under it. Not an
  /// account bound or listed under another handle too (an account has one
  /// handle), nor one bound or listed only in a form no server issues; and
  /// a handle bound or listed with two accounts gets none yet. None at all
  /// before the bindings are read: until then any handle may be bound.
  Map<String, String> claims() {
    if (!_bindingsRead) return const {};
    final unclaimed = {
      for (final MapEntry(:key, :value) in _nicknames.entries)
        if (value.userId == null) key,
    };
    if (unclaimed.isEmpty) return const {};
    final accountsUnder = <String, Set<String>>{};
    final handlesOf = <String, Set<String>>{};
    void list(String userId, String handle) {
      if (userId.isEmpty || userId == _selfUserId) return;
      // As it was listed: 'Bob' is no handle a server gives out.
      if (!isIssuableHandle(handle)) return;
      (accountsUnder[handle] ??= {}).add(userId);
      (handlesOf[userId] ??= {}).add(handle);
    }

    for (final chat in _listed) {
      if (chat.type == ConversationType.direct) {
        if (!(_isHeld?.call(chat.id) ?? false)) list(chat.recipientBundle.userId, chat.peerHandle);
      } else {
        for (final member in chat.members) {
          list(member.userId, member.handle);
        }
      }
    }
    for (final account in _blocked) {
      list(account.userId, account.handle);
    }
    // Bound under exactly the handle: a 1:1 the user let through under
    // 'Bob' is no binding of 'bob'.
    final boundUnder = <String, Set<String>>{};
    for (final peer in _bound.values) {
      if (peer.userId.isNotEmpty) (boundUnder[peer.handle] ??= {}).add(peer.userId);
    }
    bool underOneHandle(String userId, String handle) =>
        {...?_handlesOf[userId], ...?handlesOf[userId]}.every((other) => other == handle);
    return {
      for (final handle in unclaimed)
        if ((boundUnder[handle] ?? accountsUnder[handle]) case final accounts?
            when accounts.length == 1 && underOneHandle(accounts.single, handle))
          handle: accounts.single,
    };
  }
}

/// The names [messenger] shows, from [nicknames], whom each 1:1 on this
/// device is bound to, and the accounts the user [blocked].
PeerNames peerNamesFor(
  VeilMessengerController messenger,
  Map<String, ContactNickname> nicknames, {
  Iterable<BlockedAccount> blocked = const [],
}) =>
    PeerNames(
      nicknames,
      bound: messenger.boundPeers,
      isHeld: (conversationId) => messenger.peerAccountHoldFor(conversationId) != null,
      listed: messenger.conversations,
      blocked: blocked,
      selfUserId: messenger.localUserId,
      bindingsRead: messenger.bindingsRead,
    );

/// Records in [book] the account each nickname saved with none is to name
/// ([PeerNames.claims]), for good.
Future<void> claimNicknameAccounts(ContactNameBook book, PeerNames names) async {
  final claims = names.claims();
  if (claims.isNotEmpty) await book.claim(claims);
}

/// The names for the chats the messenger lists now and the accounts the
/// user blocked, from the nicknames on this phone. Each time any of them
/// changes once the messenger has read its bindings, a nickname saved with
/// no account (with a contact added, or before nicknames named accounts)
/// is given the one [PeerNames.claims] finds for its handle; until that is
/// written, a moment later, it names no one.
final peerNamesProvider = Provider<PeerNames>((ref) {
  final messenger = ref.watch(messengerControllerProvider);
  final book = ref.watch(contactNameBookProvider);
  final blocked = ref.watch(blockedAccountsProvider);
  final names = peerNamesFor(messenger, book.nicknames, blocked: blocked.accounts);
  // Written after this build: the book tells its listeners once it has. A
  // keystore that refuses it leaves the nickname naming no one, and the
  // next change tries again.
  unawaited(claimNicknameAccounts(book, names).then((_) {}, onError: (Object _) {}));
  return names;
});
