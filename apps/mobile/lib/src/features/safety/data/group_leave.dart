import '../../../core/network/veil_api_client.dart';

/// Leaves a group through the relay's existing route (POST
/// conversations/group/:id/leave), then lists the chats again so it drops
/// out. It sends nothing else: no reason, no message.
class GroupLeave {
  GroupLeave({
    required VeilApiClient api,
    required String? Function() accessToken,
    required Future<void> Function() refreshConversations,
  })  : _api = api,
        _accessToken = accessToken,
        _refreshConversations = refreshConversations;

  final VeilApiClient _api;
  final String? Function() _accessToken;
  final Future<void> Function() _refreshConversations;

  /// Leaves [conversationId]. False when the relay refused or could not be
  /// reached; then nothing changed here.
  Future<bool> leave(String conversationId) async {
    final token = _accessToken();
    if (token == null) return false;
    try {
      await _api.leaveGroup(token, conversationId);
    } catch (_) {
      return false;
    }
    await _refreshConversations();
    return true;
  }
}
