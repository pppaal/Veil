import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/presentation/peer_names.dart';
import '../data/safety_providers.dart';

/// Whose account a handle is, and what this phone calls it, for blocking
/// and reporting someone from outside a chat.
class SafetyAccounts {
  SafetyAccounts(this._ref);

  final Ref _ref;

  /// The account of [handle]: one the user blocked, the peer of a 1:1 with
  /// them, or else the server's answer (GET /users/:handle). Null when none
  /// is found; the server answers for an account blocked either way as for
  /// an unknown handle, which is why the first two come first.
  Future<String?> accountIdFor(String handle) async {
    final blocked = _ref.read(blockedAccountsProvider).byHandle(handle);
    if (blocked != null) return blocked.userId;
    final peer = _directPeer(handle);
    if (peer != null && peer.recipientBundle.userId.isNotEmpty) return peer.recipientBundle.userId;
    final token = _ref.read(appSessionProvider).accessToken;
    if (token == null) return null;
    try {
      final user = await _ref.read(apiClientProvider).getJson(
            '/users/${Uri.encodeComponent(handle)}',
            accessToken: token,
          );
      final id = user['id'];
      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// The name this phone shows for the account [userId], listed under
  /// [handle]: the nickname the user gave that handle (see PeerNames). Null
  /// when there is none, and the handle is all there is to show.
  String? knownNameFor({required String userId, required String handle}) =>
      _ref.read(peerNamesProvider).accountName(userId, handle);

  ConversationPreview? _directPeer(String handle) {
    for (final conversation in _ref.read(messengerControllerProvider).conversations) {
      if (conversation.type == ConversationType.direct && conversation.peerHandle == handle) return conversation;
    }
    return null;
  }
}

final safetyAccountsProvider = Provider<SafetyAccounts>(SafetyAccounts.new);
