import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/network/veil_api_client.dart';
import 'contact_names.dart';

/// A contact: a handle the relay lists for this account, with when it was
/// added (the relay keeps no name for it), and the nickname this phone gave
/// it.
class ContactEntry {
  const ContactEntry({
    required this.handle,
    required this.nickname,
    required this.avatarPath,
    required this.addedAt,
  });

  final String handle;
  final String? nickname;
  final String? avatarPath;
  final DateTime addedAt;

  /// Whether there is a name to show above the handle: the nickname this
  /// device gave them.
  bool get hasName => nickname?.trim().isNotEmpty ?? false;

  /// The first line of their row: the name, or with none the handle with its
  /// "@", alone (M26: never the bare handle over the same handle again).
  String get title => hasName ? label : '@$handle';

  /// The line under it: the handle, when the first line is a name.
  String? get handleLine => hasName ? '@$handle' : null;

  String get label {
    final trimmedNickname = nickname?.trim();
    if (trimmedNickname != null && trimmedNickname.isNotEmpty) {
      return trimmedNickname;
    }
    return handle;
  }

  /// A relay contact row with the nickname this device keeps for it.
  static ContactEntry fromJson(Map<String, dynamic> json, {String? nickname}) {
    return ContactEntry(
      handle: (json['handle'] as String?) ?? '',
      nickname: nickname,
      avatarPath: json['avatarPath'] as String?,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}

class ContactsController extends ChangeNotifier {
  ContactsController({required this.apiClient, required this.ref, required this.nicknames});

  final VeilApiClient apiClient;
  final Ref ref;
  final ContactNameBook nicknames;

  List<ContactEntry> _contacts = const [];
  bool _loading = false;
  bool _mutating = false;
  bool _loadFailed = false;
  String? _errorMessage;
  // Moves on at every refresh: an answer to an earlier one, made for the
  // account signed in then or overtaken by a later read, is dropped.
  int _generation = 0;

  List<ContactEntry> get contacts => _contacts;
  bool get isLoading => _loading;
  bool get isMutating => _mutating;

  /// Whether the last load of the list from the relay failed. What is
  /// shown then is the list as it was before.
  bool get loadFailed => _loadFailed;
  String? get errorMessage => _errorMessage;

  String? get _accessToken => ref.read(appSessionProvider).accessToken;

  Future<void> refresh() async {
    final generation = ++_generation;
    final token = _accessToken;
    if (token == null) {
      _contacts = const [];
      _loading = false;
      notifyListeners();
      return;
    }
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final raw = await apiClient.getContacts(token);
      final labels = await nicknames.load();
      if (generation != _generation) return;
      _contacts = [
        for (final json in raw.whereType<Map<String, dynamic>>())
          ContactEntry.fromJson(json, nickname: labels[(json['handle'] as String?)?.toLowerCase()]?.name),
      ];
      _loadFailed = false;
    } catch (error) {
      if (generation != _generation) return;
      _loadFailed = true;
      _errorMessage = formatUserFacingError(error);
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Whether the last failure was the server not finding the account.
  bool get failedAsNotFound => userFacingErrorCodeOf(_errorMessage ?? '') == UserFacingErrorCode.notFound;

  Future<bool> addContact({required String handle, String? nickname}) async {
    final token = _accessToken;
    if (token == null) return false;
    _mutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await apiClient.addContact(token, {'handle': handle.trim()});
      // Saved anew, naming no account: PeerNames.claims gives it the
      // account this phone bound the handle to, even one an earlier
      // nickname of the handle named, or else the one account the chats
      // and Blocked accounts show under the handle.
      await nicknames.write(handle.trim(), nickname ?? '', anew: true);
      await refresh();
      return true;
    } catch (error) {
      _errorMessage = formatUserFacingError(error);
      return false;
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<bool> removeContact(String handle) async {
    final token = _accessToken;
    if (token == null) return false;
    _mutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await apiClient.removeContact(token, handle);
      await nicknames.remove(handle);
      _contacts =
          _contacts.where((contact) => contact.handle != handle).toList();
      return true;
    } catch (error) {
      _errorMessage = formatUserFacingError(error);
      return false;
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  /// Changes the name this device calls a contact by; an empty one clears
  /// it. It names the same account as before. The relay never learns it.
  Future<void> renameContact(String handle, String nickname) async {
    final label = nickname.trim();
    await nicknames.write(handle, label);
    _contacts = [
      for (final contact in _contacts)
        if (contact.handle == handle)
          ContactEntry(
            handle: contact.handle,
            nickname: label.isEmpty ? null : label,
            avatarPath: contact.avatarPath,
            addedAt: contact.addedAt,
          )
        else
          contact,
    ];
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}

final contactsControllerProvider =
    ChangeNotifierProvider<ContactsController>((ref) {
  final controller = ContactsController(
    apiClient: ref.read(apiClientProvider),
    ref: ref,
    nicknames: ref.read(contactNameBookProvider),
  );

  ref.listen(appSessionProvider, (previous, next) {
    if (previous?.isAuthenticated != next.isAuthenticated) {
      unawaited(controller.refresh());
    }
  });

  unawaited(controller.refresh());
  return controller;
});
