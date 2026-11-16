import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../contacts/data/contact_names.dart';
import '../data/conversation_models.dart';
import '../data/messenger/conversation_peer_bindings.dart';
import '../data/veil_messenger_controller.dart';

/// What the screens call the people in chats: the nickname the user gave a
/// handle on this phone (ContactNameBook), or else the handle. The server
/// keeps no name for an account, so there is nothing else to show.
///
/// A nickname is kept by handle, and names the account the user talks to
/// under that handle: the one this phone bound the handle to when a 1:1
/// under it first had a session (ConversationPeerBindings), not whatever
/// account a listing puts under it now. So an account gets the nickname of
/// a handle only when this phone has bound neither that handle to another
/// account nor that account to another handle; and a 1:1 held for its
/// handle (PeerAccountHold) gets none, as its banner says it is not the
/// account the user knew.
class PeerNames {
  PeerNames(
    Map<String, String> nicknames, {
    Map<String, ConversationPeer> bound = const {},
    bool Function(String conversationId)? isHeld,
  })  : _nicknames = {for (final MapEntry(:key, :value) in nicknames.entries) key.toLowerCase(): value},
        _bound = bound,
        _isHeld = isHeld {
    for (final peer in bound.values) {
      if (peer.userId.isEmpty) continue;
      final handle = peer.handle.toLowerCase();
      (_accountsOf[handle] ??= {}).add(peer.userId);
      (_handlesOf[peer.userId] ??= {}).add(handle);
    }
  }

  final Map<String, String> _nicknames;
  final Map<String, ConversationPeer> _bound;
  final bool Function(String conversationId)? _isHeld;
  // The accounts each handle is bound to, and the handles each account is
  // bound under (lower case).
  final Map<String, Set<String>> _accountsOf = {};
  final Map<String, Set<String>> _handlesOf = {};

  /// The nickname of [handle], or null when the user gave it none.
  String? nicknameOf(String handle) => _nicknames[handle.toLowerCase()];

  /// The name of the peer of the 1:1 [chat], or null: their handle has no
  /// nickname, it names another account here, or the chat is held.
  String? peerName(ConversationPreview chat) =>
      directName(chat.id, chat.peerHandle, userId: chat.recipientBundle.userId);

  /// [peerName] for the 1:1 [conversationId] listed with [handle] and the
  /// account [userId]; without one, the account it is bound to. With
  /// neither, only a handle bound to no account gets its nickname.
  String? directName(String conversationId, String handle, {String? userId}) {
    if (_isHeld?.call(conversationId) ?? false) return null;
    final account = (userId == null || userId.isEmpty) ? _bound[conversationId]?.userId : userId;
    if (account == null) return _accountsOf.containsKey(handle.toLowerCase()) ? null : nicknameOf(handle);
    return accountName(account, handle);
  }

  /// The name of a group [member], or null: their handle has no nickname,
  /// or it names another account here.
  String? memberName(GroupMember member) => accountName(member.userId, member.handle);

  /// The name of the account [userId], listed under [handle]: the nickname
  /// of [handle], unless this phone bound [handle] to another account or
  /// [userId] under another handle.
  String? accountName(String userId, String handle) {
    final key = handle.toLowerCase();
    if (_accountsOf[key]?.any((account) => account != userId) ?? false) return null;
    if (_handlesOf[userId]?.any((other) => other != key) ?? false) return null;
    return _nicknames[key];
  }

  /// What a group member is called: their name, or their handle with its
  /// "@".
  String memberTitle(GroupMember member) => memberName(member) ?? '@${member.handle}';
}

/// The names [messenger] shows, from [nicknames] and whom each 1:1 on this
/// device is bound to.
PeerNames peerNamesFor(VeilMessengerController messenger, Map<String, String> nicknames) => PeerNames(
      nicknames,
      bound: messenger.boundPeers,
      isHeld: (conversationId) => messenger.peerAccountHoldFor(conversationId) != null,
    );

/// The names for the chats the messenger lists now, from the nicknames on
/// this phone.
final peerNamesProvider = Provider<PeerNames>((ref) {
  final messenger = ref.watch(messengerControllerProvider);
  return peerNamesFor(messenger, ref.watch(contactNameBookProvider).nicknames);
});
