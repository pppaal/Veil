import 'dart:convert';

import '../../../../core/storage/secure_storage_service.dart';

const String _authenticatedVersion = 'veil-envelope-v2';
const String _senderKeysVersion = 'veil-group-v1';
const Set<String> _legacyVersions = {'veil-envelope-v1', 'veil-envelope-v1-dev'};

/// Which envelope versions each 1:1 conversation still accepts.
///
/// The version is outer metadata the relay can rewrite. A conversation
/// starts open; once a protocol v2 frame has authenticated in it, only v2 is
/// accepted from then on, so a relay cannot walk it back to the legacy
/// protocol, whose handshake authenticates nobody. A Sender Keys group is
/// pinned the same way, to group frames only, so that a relay that reports
/// it as a pairwise group can neither route its sends nor its frames through
/// the 1:1 engine. The pins live in the keystore, apart from session state
/// that a failed restore could lose.
class EnvelopeVersionPolicy {
  EnvelopeVersionPolicy({ScopedSecureStore? store}) : _store = store;

  static const _documentKey = 'envelope_versions.v1';

  final ScopedSecureStore? _store;
  // Shared by every caller, so a pin recorded while the first read is still
  // in flight is not replaced by a second, older copy of the document.
  Future<Map<String, List<String>>>? _allowed;
  // Set when the stored document cannot be read: every conversation is then
  // treated as pinned, so corruption never reopens a downgrade.
  bool _unreadable = false;

  /// Whether a frame of [version] must be refused in [conversationId].
  Future<bool> rejects(String conversationId, String version) async {
    final allowed = (await _load())[conversationId];
    if (allowed != null) return !allowed.contains(version);
    return _unreadable && _legacyVersions.contains(version);
  }

  /// Records that a frame of [version] authenticated in [conversationId].
  Future<void> noteAuthenticated(String conversationId, String version) async {
    if (version != _authenticatedVersion) return;
    await _pin(conversationId, _authenticatedVersion);
  }

  /// Records that [conversationId] is a Sender Keys group. It stays one: an
  /// honest relay never turns Sender Keys off again (the API refuses to).
  Future<void> pinSenderKeys(String conversationId) => _pin(conversationId, _senderKeysVersion);

  /// Whether [conversationId] was ever seen as a Sender Keys group.
  Future<bool> isSenderKeysPinned(String conversationId) async =>
      (await _load())[conversationId]?.contains(_senderKeysVersion) ?? false;

  // A conversation is pinned once, to a single version, and never re-pinned.
  Future<void> _pin(String conversationId, String version) async {
    final allowed = await _load();
    if (allowed[conversationId] != null) return;
    allowed[conversationId] = [version];
    // Writing over an unreadable document would leave only this pin, and
    // reopen every other conversation after a restart. It already pins them
    // all, so it is kept as it is.
    if (_unreadable) return;
    await _store?.write(_documentKey, json.encode(allowed));
  }

  /// Drops what was read for the previous identity; the stored pins are
  /// wiped with the rest of the device state.
  void reset() {
    _allowed = null;
    _unreadable = false;
  }

  Future<Map<String, List<String>>> _load() async {
    final loading = _allowed ??= _read();
    try {
      return await loading;
    } catch (_) {
      // A keystore error is retried by the next call.
      if (identical(_allowed, loading)) _allowed = null;
      rethrow;
    }
  }

  Future<Map<String, List<String>>> _read() async {
    final loaded = <String, List<String>>{};
    final raw = await _store?.read(_documentKey);
    if (raw != null) {
      final decoded = _tryDecode(raw);
      if (decoded == null) {
        _unreadable = true;
      } else {
        loaded.addAll(decoded);
      }
    }
    return loaded;
  }

  static Map<String, List<String>>? _tryDecode(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return {
        for (final entry in decoded.entries) entry.key: List<String>.from(entry.value as List),
      };
    } on Object {
      return null;
    }
  }
}
