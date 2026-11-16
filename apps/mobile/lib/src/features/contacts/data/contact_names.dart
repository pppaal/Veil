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
class ContactNameBook extends ChangeNotifier {
  ContactNameBook(this._store);

  final ContactNicknames _store;
  Map<String, String> _nicknames = const {};
  // A read that started before a later one, or before a sign-out, is
  // dropped when it ends.
  int _generation = 0;

  /// Each nickname by handle, in lower case.
  Map<String, String> get nicknames => _nicknames;

  /// Reads the nicknames from the keystore and returns them.
  Future<Map<String, String>> load() async {
    final generation = ++_generation;
    final read = await _store.readAll();
    if (generation == _generation) _set(read);
    return read;
  }

  /// Sets [handle]'s nickname; an empty one removes it.
  Future<void> write(String handle, String nickname) async {
    await _store.write(handle, nickname);
    await load();
  }

  Future<void> remove(String handle) => write(handle, '');

  /// Forgets what was read, when the account signs out (the keystore is
  /// wiped with the rest of the device's state).
  void forget() {
    _generation++;
    _set(const {});
  }

  void _set(Map<String, String> next) {
    if (mapEquals(next, _nicknames)) return;
    _nicknames = Map.unmodifiable(next);
    notifyListeners();
  }
}

final contactNameBookProvider = ChangeNotifierProvider<ContactNameBook>((ref) {
  final book = ContactNameBook(ContactNicknames(ref.read(secureStorageProvider).scoped(SecureScope.contacts)));
  // A keystore that can't be read now leaves the names as they were: people
  // are shown by their handles until a later read works.
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
