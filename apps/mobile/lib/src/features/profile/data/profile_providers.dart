import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/network/veil_api_client.dart';

class ProfileSnapshot {
  const ProfileSnapshot({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.bio,
    required this.statusMessage,
    required this.statusEmoji,
    required this.avatarPath,
    required this.lastStatusAt,
    required this.createdAt,
  });

  final String id;
  final String handle;
  final String? displayName;
  final String? bio;
  final String? statusMessage;
  final String? statusEmoji;
  final String? avatarPath;
  final DateTime? lastStatusAt;
  final DateTime createdAt;

  String get accountAgeLabel {
    final days = DateTime.now().difference(createdAt).inDays;
    if (days <= 1) return '1 day';
    if (days < 30) return '$days days';
    if (days < 365) return '${days ~/ 30} months';
    return '${days ~/ 365} years';
  }

  static ProfileSnapshot fromJson(Map<String, dynamic> json) {
    return ProfileSnapshot(
      id: (json['id'] as String?) ?? '',
      handle: (json['handle'] as String?) ?? '',
      displayName: json['displayName'] as String?,
      bio: json['bio'] as String?,
      statusMessage: json['statusMessage'] as String?,
      statusEmoji: json['statusEmoji'] as String?,
      avatarPath: json['avatarPath'] as String?,
      lastStatusAt: DateTime.tryParse(json['lastStatusAt'] as String? ?? '')
          ?.toLocal(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}

class ProfileController extends ChangeNotifier {
  ProfileController({required this.apiClient, required this.ref});

  final VeilApiClient apiClient;
  final Ref ref;

  ProfileSnapshot? _profile;
  bool _loading = false;
  bool _saving = false;
  String? _errorMessage;

  ProfileSnapshot? get profile => _profile;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  String? get errorMessage => _errorMessage;

  String? get _accessToken => ref.read(appSessionProvider).accessToken;

  Future<void> refresh() async {
    final token = _accessToken;
    if (token == null) {
      _profile = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final raw = await apiClient.getProfile(token);
      _profile = ProfileSnapshot.fromJson(raw);
    } catch (error) {
      _errorMessage = formatUserFacingError(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfile({
    String? displayName,
    String? bio,
    String? statusMessage,
  }) async {
    final token = _accessToken;
    if (token == null) return false;
    _saving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final body = <String, dynamic>{};
      if (displayName != null) body['displayName'] = displayName;
      if (bio != null) body['bio'] = bio;
      if (statusMessage != null) body['statusMessage'] = statusMessage;
      final raw = await apiClient.updateProfile(token, body);
      _profile = ProfileSnapshot.fromJson(raw);
      return true;
    } catch (error) {
      _errorMessage = formatUserFacingError(error);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}

final profileControllerProvider =
    ChangeNotifierProvider<ProfileController>((ref) {
  final controller = ProfileController(
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
