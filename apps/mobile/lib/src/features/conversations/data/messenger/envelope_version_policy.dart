import 'dart:convert';

import '../../../../core/storage/secure_storage_service.dart';

const String _authenticatedVersion = 'veil-envelope-v2';
const Set<String> _legacyVersions = {'veil-envelope-v1', 'veil-envelope-v1-dev'};

/// Which envelope versions each 1:1 conversation still accepts.
///
/// The version is outer metadata the relay can rewrite. A conversation
/// starts open; once a protocol v2 frame has authenticated in it, only v2 is
/// accepted from then on, so a relay cannot walk it back to the legacy
/// protocol, whose handshake authenticates nobody. The pins live in the
/// keystore, apart from session state that a failed restore could lose.
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
    final allowed = await _load();
    if (allowed[conversationId]?.length == 1) return;
    allowed[conversationId] = const [_authenticatedVersion];
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
