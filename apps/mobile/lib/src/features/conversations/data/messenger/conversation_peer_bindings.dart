import 'dart:convert';

import '../../../../core/storage/secure_storage_service.dart';

/// The contact a 1:1 conversation is with.
class ConversationPeer {
  const ConversationPeer({required this.userId, required this.handle});

  final String userId;
  final String handle;
}

/// Whom each 1:1 conversation is with, recorded once it has a session and
/// never changed after that.
///
/// The ratchet session stays with its conversation id for as long as the
/// device keeps it, and a direct conversation never changes members. A
/// server list that left the conversation out once and then lists it with
/// another user, or as a group, would otherwise have this device show one
/// contact while it reads and writes the other's session. The bindings live
/// in the keystore, apart from the conversation cache the relay's lists
/// overwrite.
class ConversationPeerBindings {
  ConversationPeerBindings({ScopedSecureStore? store}) : _store = store;

  static const _documentKey = 'direct_peers.v1';
  static const _groupsKey = 'group_members.v1';

  final ScopedSecureStore? _store;
  // Shared by every caller, so a binding recorded while the first read is
  // still in flight is not replaced by a second, older copy of the document.
  Future<Map<String, ConversationPeer>>? _bound;
  // Set when the stored document cannot be read. Nothing is written over it
  // then: that would drop every binding it holds.
  bool _unreadable = false;
  Future<Map<String, Set<String>>>? _groups;
  bool _groupsUnreadable = false;

  /// The member user ids each group was last shown with on this device, by
  /// conversation id. Kept with the bindings, apart from the conversation
  /// cache, so a change the relay made while the app was closed is still
  /// told apart from the first listing of a group.
  Future<Map<String, Set<String>>> groupMembers() async => Map.unmodifiable(await _loadGroups());

  /// Records [members] as what each of those groups is shown with now.
  Future<void> recordGroupMembers(Map<String, Set<String>> members) async {
    if (members.isEmpty) return;
    final recorded = await _loadGroups();
    recorded.addAll({for (final entry in members.entries) entry.key: Set.of(entry.value)});
    if (_groupsUnreadable) return;
    await _store?.write(_groupsKey, json.encode({
      for (final entry in recorded.entries) entry.key: (entry.value.toList()..sort()),
    }));
  }

  /// Every binding recorded so far, by conversation id.
  Future<Map<String, ConversationPeer>> all() async => Map.unmodifiable(await _load());

  /// Records whom each conversation in [peers] is with, unless it is bound
  /// already: a binding is never replaced.
  Future<void> bindAll(Map<String, ConversationPeer> peers) async {
    final bound = await _load();
    final fresh = {
      for (final entry in peers.entries)
        if (!bound.containsKey(entry.key) && entry.value.userId.isNotEmpty) entry.key: entry.value,
    };
    if (fresh.isEmpty) return;
    bound.addAll(fresh);
    if (_unreadable) return;
    await _store?.write(_documentKey, json.encode({
      for (final entry in bound.entries) entry.key: {'userId': entry.value.userId, 'handle': entry.value.handle},
    }));
  }

  /// Drops what was read for the previous identity; the stored bindings are
  /// wiped with the rest of the device state.
  void reset() {
    _bound = null;
    _unreadable = false;
    _groups = null;
    _groupsUnreadable = false;
  }

  Future<Map<String, Set<String>>> _loadGroups() async {
    final loading = _groups ??= _readGroups();
    try {
      return await loading;
    } catch (_) {
      if (identical(_groups, loading)) _groups = null;
      rethrow;
    }
  }

  Future<Map<String, Set<String>>> _readGroups() async {
    final raw = await _store?.read(_groupsKey);
    if (raw == null) return {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries) entry.key: {for (final id in entry.value as List<dynamic>) id as String},
      };
    } on Object {
      _groupsUnreadable = true;
      return {};
    }
  }

  Future<Map<String, ConversationPeer>> _load() async {
    final loading = _bound ??= _read();
    try {
      return await loading;
    } catch (_) {
      // A keystore error is retried by the next call.
      if (identical(_bound, loading)) _bound = null;
      rethrow;
    }
  }

  Future<Map<String, ConversationPeer>> _read() async {
    final raw = await _store?.read(_documentKey);
    if (raw == null) return {};
    final decoded = _tryDecode(raw);
    if (decoded == null) {
      _unreadable = true;
      return {};
    }
    return decoded;
  }

  static Map<String, ConversationPeer>? _tryDecode(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return {
        for (final entry in decoded.entries)
          entry.key: ConversationPeer(
            userId: (entry.value as Map<String, dynamic>)['userId'] as String,
            handle: (entry.value as Map<String, dynamic>)['handle'] as String,
          ),
      };
    } on Object {
      return null;
    }
  }
}
