import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/network/veil_api_client.dart';

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

  static ContactEntry fromJson(Map<String, dynamic> json) {
    return ContactEntry(
      handle: (json['handle'] as String?) ?? '',
      displayName: json['displayName'] as String?,
      nickname: json['nickname'] as String?,
      avatarPath: json['avatarPath'] as String?,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}

class ContactsController extends ChangeNotifier {
  ContactsController({required this.apiClient, required this.ref});

  final VeilApiClient apiClient;
  final Ref ref;

  List<ContactEntry> _contacts = const [];
  bool _loading = false;
  bool _mutating = false;
  String? _errorMessage;

  List<ContactEntry> get contacts => _contacts;
  bool get isLoading => _loading;
  bool get isMutating => _mutating;
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
      _contacts = raw
          .whereType<Map<String, dynamic>>()
          .map(ContactEntry.fromJson)
          .toList();
    } catch (error) {
      _errorMessage = formatUserFacingError(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> addContact({required String handle, String? nickname}) async {
    final token = _accessToken;
    if (token == null) return false;
    _mutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await apiClient.addContact(token, {
        'handle': handle.trim(),
        if (nickname != null && nickname.trim().isNotEmpty)
          'nickname': nickname.trim(),
      });
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

  Future<Map<String, dynamic>?> fetchPublicProfile(String handle) async {
    final token = _accessToken;
    if (token == null) return null;
    try {
      return await apiClient.getPublicProfile(token, handle);
    } catch (_) {
      return null;
    }
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
  );

  ref.listen(appSessionProvider, (previous, next) {
    if (previous?.isAuthenticated != next.isAuthenticated) {
      unawaited(controller.refresh());
    }
  });

  unawaited(controller.refresh());
  return controller;
});
