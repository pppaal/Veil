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

  final ScopedSecureStore? _store;
  // Shared by every caller, so a binding recorded while the first read is
  // still in flight is not replaced by a second, older copy of the document.
  Future<Map<String, ConversationPeer>>? _bound;
  // Set when the stored document cannot be read. Nothing is written over it
  // then: that would drop every binding it holds.
  bool _unreadable = false;

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
