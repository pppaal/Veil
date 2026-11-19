import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_session_state.dart';
import '../../../app/session/session_providers.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/storage/secure_storage_service.dart';
import 'contact_nicknames.dart';

/// The nicknames the user gave their contacts, by handle, as this phone
/// keeps them (ContactNicknames), held for the screens that name people.
///
/// These are the only names the app has. The server keeps none: it lists
/// conversation members as an account and a handle, and contacts as a
/// handle, so anyone the user gave no nickname is shown by their handle.
/// Each nickname names one account ([ContactNickname.userId]); see
/// PeerNames for who is called by it.
class ContactNameBook extends ChangeNotifier {
  ContactNameBook(this._store);

  final ContactNicknames _store;
  Map<String, ContactNickname> _nicknames = const {};
  // A read that started before a later one, or before a sign-out, is
  // dropped when it ends.
  int _generation = 0;
  // The claims in flight, so a screen that redraws meanwhile does not
  // send the same one again.
  final Set<String> _claiming = {};

  /// Each nickname by handle, in lower case.
  Map<String, ContactNickname> get nicknames => _nicknames;

  /// Reads the nicknames from the keystore and returns them.
  Future<Map<String, ContactNickname>> load() async {
    final generation = ++_generation;
    final read = await _store.readAll();
    if (generation == _generation) _set(read);
    return read;
  }

  /// Sets [handle]'s nickname; an empty one removes it. A nickname changed
  /// names the account it named; one saved [anew], with a contact added,
  /// names the account PeerNames finds under the handle next ([claim]).
  Future<void> write(String handle, String nickname, {bool anew = false}) async {
    await _store.write(handle, nickname, anew: anew);
    await load();
  }

  Future<void> remove(String handle) => write(handle, '');

  /// Gives each nickname that names no account yet the account [accounts]
  /// gives for its handle (in lower case), for good.
  Future<void> claim(Map<String, String> accounts) async {
    final fresh = {
      for (final MapEntry(key: handle, value: userId) in accounts.entries)
        if (!_claiming.contains(handle)) handle: userId,
    };
    if (fresh.isEmpty) return;
    _claiming.addAll(fresh.keys);
    try {
      await _store.claim(fresh);
      await load();
    } finally {
      _claiming.removeAll(fresh.keys);
    }
  }

  /// Forgets what was read, when the account signs out (the keystore is
  /// wiped with the rest of the device's state).
  void forget() {
    _generation++;
    _set(const {});
  }

  void _set(Map<String, ContactNickname> next) {
    if (mapEquals(next, _nicknames)) return;
    _nicknames = Map.unmodifiable(next);
    notifyListeners();
  }
}

final contactNameBookProvider = ChangeNotifierProvider<ContactNameBook>((ref) {
  final book = ContactNameBook(ContactNicknames(ref.read(secureStorageProvider).scoped(SecureScope.contacts)));
  // A keystore that can't be read now leaves the names as they were: people
  // are shown by their handles until it is read again: when the contact
  // list is fetched (ContactsController.refresh), a nickname is saved, or
  // the account signs in again. Nothing retries it on a timer.
  void load() => unawaited(book.load().then((_) {}, onError: (Object _) {}));
  ref.listen<AppSessionState>(appSessionProvider, (previous, next) {
    if (previous?.isAuthenticated == next.isAuthenticated) return;
    if (next.isAuthenticated) {
      load();
    } else {
      book.forget();
    }
  });
  load();
  return book;
});
