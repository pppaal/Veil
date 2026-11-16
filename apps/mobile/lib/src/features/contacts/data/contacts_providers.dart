import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import 'contact_nicknames.dart';

class ContactEntry {
  const ContactEntry({
    required this.handle,
    required this.displayName,
    required this.nickname,
    required this.avatarPath,
    required this.addedAt,
  });

  final String handle;
  final String? displayName;
  final String? nickname;
  final String? avatarPath;
  final DateTime addedAt;

  String get label {
    final trimmedNickname = nickname?.trim();
    if (trimmedNickname != null && trimmedNickname.isNotEmpty) {
      return trimmedNickname;
    }
    final trimmedDisplayName = displayName?.trim();
    if (trimmedDisplayName != null && trimmedDisplayName.isNotEmpty) {
      return trimmedDisplayName;
    }
    return handle;
  }

  /// A relay contact row with the nickname this device keeps for it.
  static ContactEntry fromJson(Map<String, dynamic> json, {String? nickname}) {
    return ContactEntry(
      handle: (json['handle'] as String?) ?? '',
      displayName: json['displayName'] as String?,
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
  final ContactNicknames nicknames;

  List<ContactEntry> _contacts = const [];
  bool _loading = false;
  bool _mutating = false;
  bool _loadFailed = false;
  String? _errorMessage;

  List<ContactEntry> get contacts => _contacts;
  bool get isLoading => _loading;
  bool get isMutating => _mutating;

  /// Whether the last load of the list from the relay failed. What is
  /// shown then is the list as it was before.
  bool get loadFailed => _loadFailed;
  String? get errorMessage => _errorMessage;

  String? get _accessToken => ref.read(appSessionProvider).accessToken;

  Future<void> refresh() async {
    final token = _accessToken;
    if (token == null) {
      _contacts = const [];
      notifyListeners();
      return;
    }
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final raw = await apiClient.getContacts(token);
      final labels = await nicknames.readAll();
      _contacts = [
        for (final json in raw.whereType<Map<String, dynamic>>())
          ContactEntry.fromJson(json, nickname: labels[json['handle']]),
      ];
      _loadFailed = false;
    } catch (error) {
      _loadFailed = true;
      _errorMessage = formatUserFacingError(error);
    } finally {
      _loading = false;
      notifyListeners();
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
      await nicknames.write(handle.trim(), nickname ?? '');
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
  /// it. The relay never learns it.
  Future<void> renameContact(String handle, String nickname) async {
    final label = nickname.trim();
    await nicknames.write(handle, label);
    _contacts = [
      for (final contact in _contacts)
        if (contact.handle == handle)
          ContactEntry(
            handle: contact.handle,
            displayName: contact.displayName,
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
    nicknames: ContactNicknames(ref.read(secureStorageProvider).scoped(SecureScope.contacts)),
  );

  ref.listen(appSessionProvider, (previous, next) {
    if (previous?.isAuthenticated != next.isAuthenticated) {
      unawaited(controller.refresh());
    }
  });

  unawaited(controller.refresh());
  return controller;
});
