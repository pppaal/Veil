import 'package:flutter/foundation.dart';

import '../../../core/network/veil_api_client.dart';

/// An account the user blocked, as the server lists it: who, and since when.
/// The server keeps no name for it; a screen shows the one this phone knows.
class BlockedAccount {
  const BlockedAccount({required this.userId, required this.handle, required this.blockedAt});

  final String userId;
  final String handle;
  final DateTime blockedAt;

  /// A BlockedUserSummary of the API; null when it lacks the id or handle.
  static BlockedAccount? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final userId = json['userId'];
    final handle = json['handle'];
    if (userId is! String || userId.isEmpty || handle is! String || handle.isEmpty) return null;
    return BlockedAccount(
      userId: userId,
      handle: handle,
      blockedAt: DateTime.tryParse(json['blockedAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

/// The accounts the user blocked. The server keeps the list and enforces
/// it (GET, POST and DELETE /safety/blocks): a blocked account can't send
/// to the user in a 1:1, the user can't send to it, and neither finds the
/// other by handle. This mirrors the list for the screens that ask whether
/// someone is blocked; a change is made on the server first and shown once
/// the server took it.
class BlockedAccounts extends ChangeNotifier {
  BlockedAccounts({required VeilApiClient api, required String? Function() accessToken})
      : _api = api,
        _accessToken = accessToken;

  final VeilApiClient _api;
  final String? Function() _accessToken;

  List<BlockedAccount> _accounts = const [];
  bool _loaded = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _disposed = false;

  /// Newest block first, as the server lists them.
  List<BlockedAccount> get accounts => _accounts;

  /// Whether the list has been read from the server at least once.
  bool get loaded => _loaded;
  bool get isLoading => _loading;

  /// Whether the last read of the list failed. What is shown then is the
  /// list as it was before.
  bool get loadFailed => _loadFailed;

  bool isBlocked(String userId) => userId.isNotEmpty && _accounts.any((account) => account.userId == userId);

  BlockedAccount? byHandle(String handle) {
    for (final account in _accounts) {
      if (account.handle == handle) return account;
    }
    return null;
  }

  Future<void> refresh() async {
    final token = _accessToken();
    if (token == null) {
      clear();
      return;
    }
    _loading = true;
    _notify();
    try {
      final response = await _api.listBlockedUsers(token);
      final items = response['items'];
      _accounts = [
        if (items is List)
          for (final item in items)
            if (BlockedAccount.fromJson(item) case final account?) account,
      ];
      _loaded = true;
      _loadFailed = false;
    } catch (_) {
      _loadFailed = true;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Blocks [userId] ([handle] stands in until the server answers with its
  /// own). False when the server refused or could not be reached; then
  /// nothing changed.
  Future<bool> block(String userId, {required String handle}) async {
    final token = _accessToken();
    if (token == null) return false;
    try {
      final response = await _api.blockUser(token, userId);
      final account = BlockedAccount.fromJson(response['blocked']) ??
          BlockedAccount(userId: userId, handle: handle, blockedAt: DateTime.now());
      _accounts = [account, ..._accounts.where((each) => each.userId != userId)];
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Unblocks [userId]. False when the server refused or could not be
  /// reached; then nothing changed. Unblocking someone not blocked is no
  /// error: the server treats it as done.
  Future<bool> unblock(String userId) async {
    final token = _accessToken();
    if (token == null) return false;
    try {
      await _api.unblockUser(token, userId);
      _accounts = [for (final account in _accounts) if (account.userId != userId) account];
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Forgets the list, as when the account signs out.
  void clear() {
    _accounts = const [];
    _loaded = false;
    _loadFailed = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
