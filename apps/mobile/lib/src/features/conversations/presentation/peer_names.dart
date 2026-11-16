import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../contacts/data/contact_names.dart';
import '../data/conversation_models.dart';

/// What the screens call the people in chats: the nickname the user gave a
/// handle on this phone (ContactNameBook), or else the handle. The server
/// keeps no name for an account, so there is nothing else to show.
///
/// A nickname is kept by handle, and names the account the user talks to
/// under that handle. So it is not put on a 1:1 held for its handle
/// (PeerAccountHold): that chat is with another account than the one the
/// user knew as @sam, and its banner says so. Nor on a group member whose
/// handle a 1:1 on this phone is with another account.
class PeerNames {
  PeerNames(
    Map<String, String> nicknames, {
    Iterable<ConversationPreview> chats = const [],
    bool Function(String conversationId)? isHeld,
  }) : _nicknames = {for (final MapEntry(:key, :value) in nicknames.entries) key.toLowerCase(): value} {
    for (final chat in chats) {
      if (chat.type != ConversationType.direct) continue;
      if (isHeld?.call(chat.id) ?? false) {
        _held.add(chat.id);
        continue;
      }
      final userId = chat.recipientBundle.userId;
      if (userId.isNotEmpty) (_accounts[chat.peerHandle.toLowerCase()] ??= {}).add(userId);
    }
  }

  final Map<String, String> _nicknames;
  final Set<String> _held = {};
  // The accounts the 1:1s that are not held are with, by handle.
  final Map<String, Set<String>> _accounts = {};

  /// The nickname of [handle], or null when the user gave it none.
  String? nicknameOf(String handle) => _nicknames[handle.toLowerCase()];

  /// The name of the peer of the 1:1 [chat], or null: their handle has no
  /// nickname, or the chat is held for its handle.
  String? peerName(ConversationPreview chat) => directName(chat.id, chat.peerHandle);

  /// [peerName] for the 1:1 [conversationId] with [handle].
  String? directName(String conversationId, String handle) =>
      _held.contains(conversationId) ? null : nicknameOf(handle);

  /// The name of a group [member], or null: their handle has no nickname,
  /// or a 1:1 on this phone under that handle is with another account.
  String? memberName(GroupMember member) => accountName(member.userId, member.handle);

  /// The name of the account [userId], listed under [handle], by the same
  /// rule as [memberName].
  String? accountName(String userId, String handle) {
    final accounts = _accounts[handle.toLowerCase()];
    if (accounts != null && !accounts.contains(userId)) return null;
    return nicknameOf(handle);
  }

  /// What a group member is called: their name, or their handle with its
  /// "@".
  String memberTitle(GroupMember member) => memberName(member) ?? '@${member.handle}';
}

/// The names for the chats the messenger lists now, from the nicknames on
/// this phone.
final peerNamesProvider = Provider<PeerNames>((ref) {
  final messenger = ref.watch(messengerControllerProvider);
  return PeerNames(
    ref.watch(contactNameBookProvider).nicknames,
    chats: messenger.conversations,
    isHeld: (conversationId) => messenger.peerAccountHoldFor(conversationId) != null,
  );
});
