import 'dart:convert';

import '../../../core/storage/secure_storage_service.dart';

/// A nickname the user gave a handle, and the account it names.
class ContactNickname {
  const ContactNickname(this.name, {this.userId});

  final String name;

  /// The account the nickname names: the one this phone knew under the
  /// handle when the nickname was saved, or else the first one the chats
  /// or Blocked accounts showed under it afterwards
  /// ([ContactNicknames.claim]). Null until then, and no account is called
  /// by the nickname while it is. Never replaced: another account later
  /// listed under the handle (one that took it over after the first was
  /// deleted, or one a lying server puts there) is not the one the user
  /// named.
  final String? userId;

  @override
  bool operator ==(Object other) => other is ContactNickname && other.name == name && other.userId == userId;

  @override
  int get hashCode => Object.hash(name, userId);

  @override
  String toString() => 'ContactNickname($name, userId: $userId)';
}

/// Private labels the user gives contacts. They never leave this device:
/// the relay only ever learns which handles are in the contact list.
///
/// Kept by handle in lower case, as the relay lists handles (it registers
/// and looks them up lower-cased), so a contact added as "Sam" is found as
/// the @sam of a chat; and each with the account it names
/// ([ContactNickname.userId]).
class ContactNicknames {
  ContactNicknames(this._store);

  static const _documentKey = 'nicknames.v2';
  // Names alone, by handle, as builds before a nickname named an account
  // kept them: read until the first write, which moves them over with no
  // account, for the first list that shows each handle to fill in.
  static const _namesOnlyKey = 'nicknames.v1';

  final ScopedSecureStore _store;

  Future<Map<String, ContactNickname>> readAll() async =>
      _decode(await _store.read(_documentKey) ?? await _store.read(_namesOnlyKey));

  /// Sets [handle]'s nickname; an empty one removes it. A nickname changed
  /// keeps the account it named; one saved [anew] (a contact added with
  /// it) names none until [claim] gives it one.
  Future<void> write(String handle, String nickname, {bool anew = false}) => _update((all) {
        final key = handle.trim().toLowerCase();
        final trimmed = nickname.trim();
        if (trimmed.isEmpty) return all.remove(key) != null;
        final next = ContactNickname(trimmed, userId: anew ? null : all[key]?.userId);
        if (all[key] == next) return false;
        all[key] = next;
        return true;
      });

  /// Gives each nickname that names no account yet the account [accounts]
  /// gives for its handle (in lower case). One that names an account keeps
  /// it.
  Future<void> claim(Map<String, String> accounts) => _update((all) {
        var changed = false;
        for (final MapEntry(key: handle, value: userId) in accounts.entries) {
          final nickname = all[handle.toLowerCase()];
          if (nickname == null || nickname.userId != null || userId.isEmpty) continue;
          all[handle.toLowerCase()] = ContactNickname(nickname.name, userId: userId);
          changed = true;
        }
        return changed;
      });

  Future<void> remove(String handle) => write(handle, '');

  // Reads, changes and writes the document in one step of the keystore
  // (ScopedSecureStore.update), so a wipe in between is never undone.
  Future<void> _update(bool Function(Map<String, ContactNickname> all) change) => _store.update(
        _documentKey,
        (raw) {
          final all = _decode(raw);
          if (!change(all)) return null;
          return json.encode({
            for (final MapEntry(key: handle, value: nickname) in all.entries)
              handle: {'name': nickname.name, if (nickname.userId != null) 'userId': nickname.userId},
          });
        },
        previousKey: _namesOnlyKey,
      );

  static Map<String, ContactNickname> _decode(String? raw) {
    if (raw == null) return {};
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) return {};
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (_entry(value) case final nickname?) key.toLowerCase(): nickname,
    };
  }

  static ContactNickname? _entry(Object? value) => switch (value) {
        // A name alone, as the first version of the document kept it.
        final String name => ContactNickname(name),
        {'name': final String name, 'userId': final String userId} when userId.isNotEmpty =>
          ContactNickname(name, userId: userId),
        {'name': final String name} => ContactNickname(name),
        _ => null,
      };
}
