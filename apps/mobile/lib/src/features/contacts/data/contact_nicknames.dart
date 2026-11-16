import 'dart:convert';

import '../../../core/storage/secure_storage_service.dart';

/// Private labels the user gives contacts. They never leave this device:
/// the relay only ever learns which handles are in the contact list.
///
/// Kept by handle in lower case, as the relay lists handles (it registers
/// and looks them up lower-cased), so a contact added as "Sam" is found as
/// the @sam of a chat.
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
        if (value is String) key.toLowerCase(): value,
    };
  }

  /// Sets [handle]'s nickname; an empty one removes it.
  Future<void> write(String handle, String nickname) async {
    final next = Map<String, String>.of(await readAll());
    final key = handle.trim().toLowerCase();
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) {
      next.remove(key);
    } else {
      next[key] = trimmed;
    }
    await _store.write(_documentKey, json.encode(next));
  }

  Future<void> remove(String handle) => write(handle, '');
}
