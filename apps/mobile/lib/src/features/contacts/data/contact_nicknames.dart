import 'dart:convert';

import '../../../core/storage/secure_storage_service.dart';

/// Private labels the user gives contacts. They never leave this device:
/// the relay only ever learns which handles are in the contact list.
class ContactNicknames {
  ContactNicknames(this._store);

  static const _documentKey = 'nicknames.v1';

  final ScopedSecureStore _store;

  Future<Map<String, String>> readAll() async {
    final raw = await _store.read(_documentKey);
    if (raw == null) return const {};
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) return const {};
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (value is String) key: value,
    };
  }

  /// Sets [handle]'s nickname; an empty one removes it.
  Future<void> write(String handle, String nickname) async {
    final next = Map<String, String>.of(await readAll());
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) {
      next.remove(handle);
    } else {
      next[handle] = trimmed;
    }
    await _store.write(_documentKey, json.encode(next));
  }

  Future<void> remove(String handle) => write(handle, '');
}
