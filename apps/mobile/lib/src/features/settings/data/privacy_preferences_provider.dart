import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/storage/secure_storage_service.dart';
import 'privacy_preferences.dart';

final privacyPreferencesProvider = ChangeNotifierProvider<PrivacyPreferences>((ref) {
  final preferences = PrivacyPreferences(ref.read(secureStorageProvider).scoped(SecureScope.privacy));
  unawaited(preferences.load());
  return preferences;
});
