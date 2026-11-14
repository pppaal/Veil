import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../config/veil_config.dart';
import '../crypto/crypto_adapter_registry.dart';
import '../crypto/crypto_engine.dart';
import '../notifications/local_notification_service.dart';
import '../realtime/realtime_service.dart';
import '../security/app_lock_service.dart';
import '../security/local_data_cipher.dart';
import '../security/platform_security_service.dart';
import '../storage/app_database.dart';
import '../storage/cache_handle.dart';
import '../storage/conversation_cache_service.dart';
import '../storage/database_provider.dart';
import '../storage/secure_storage_service.dart';

// Providers for platform services, storage and crypto: everything here
// depends on core alone, so features and app composition build on it.

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final platformSecurityServiceProvider =
    Provider<PlatformSecurityService>((ref) {
  return MethodChannelPlatformSecurityService();
});

final platformSecurityStatusProvider =
    FutureProvider<PlatformSecurityStatus>((ref) async {
  final service = ref.read(platformSecurityServiceProvider);
  await service.applyPrivacyProtections();
  return service.getStatus();
});

final appDatabaseFutureProvider = FutureProvider<AppDatabase>((ref) async {
  final database = await createAppDatabase(
    secureStorage: ref.read(secureStorageProvider),
    platformSecurityService: ref.read(platformSecurityServiceProvider),
  );
  ref.onDispose(database.close);
  return database;
});

final cacheEpochProvider = StateProvider<int>((ref) => 0);

final conversationCacheProvider =
    FutureProvider<DriftConversationCacheService?>((ref) async {
  ref.watch(cacheEpochProvider);
  if (!VeilConfig.enableLocalCache) {
    return null;
  }

  final database = await ref.watch(appDatabaseFutureProvider.future);
  final secureStorage = ref.read(secureStorageProvider);
  final cacheKey = await secureStorage.readOrCreateCacheKey();
  final cipher = await LocalDataCipher.fromBase64Key(cacheKey);
  return DriftConversationCacheService(
    database,
    envelopeCodec: ref.read(cryptoAdapterProvider).envelopeCodec,
    cipher: cipher,
  );
});

/// The conversation cache as long-lived consumers hold it: one object for
/// the app's life that always reaches the current database. Null when the
/// local cache is turned off.
final cacheHandleProvider = Provider<CacheHandle?>((ref) {
  if (!VeilConfig.enableLocalCache) return null;
  return CacheHandle(() async {
    final cache = await openConversationCache(ref);
    return cache!;
  });
});

/// Opens the conversation cache for a caller that tries again after a
/// failure (CacheHandle, the trust migration). A FutureProvider keeps a
/// failed open as its value until it is invalidated, so the failure is
/// forgotten here and the next call opens the database again, as on an iOS
/// launch before first unlock. An open database is never invalidated: that
/// would close it under its other users.
Future<DriftConversationCacheService?> openConversationCache(Ref ref) async {
  try {
    return await ref.read(conversationCacheProvider.future);
  } catch (_) {
    if (ref.read(appDatabaseFutureProvider).hasError) ref.invalidate(appDatabaseFutureProvider);
    ref.invalidate(conversationCacheProvider);
    rethrow;
  }
}

final cryptoAdapterProvider = Provider<CryptoAdapter>((ref) {
  return createConfiguredCryptoAdapter();
});

final messagingCryptoProvider = Provider<MessageCryptoEngine>((ref) {
  return ref.read(cryptoAdapterProvider).messaging;
});

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  return RealtimeService();
});

final localNotificationServiceProvider =
    Provider<LocalNotificationService>((ref) {
  final service = LocalNotificationService();
  unawaited(service.initialize());
  return service;
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(
    DeviceLocalUnlockAuthenticator(LocalAuthentication()),
    ref.read(secureStorageProvider),
  );
});

class LocalSecuritySnapshot {
  const LocalSecuritySnapshot({
    required this.hasDeviceSecretRefs,
    required this.hasPin,
    required this.biometricsAvailable,
    required this.integrityCompromised,
    required this.integrityReasons,
    required this.screenCaptureProtectionSupported,
    required this.screenCaptureProtectionEnabled,
    required this.appPreviewProtectionEnabled,
  });

  final bool hasDeviceSecretRefs;
  final bool hasPin;
  final bool biometricsAvailable;
  final bool integrityCompromised;
  final List<String> integrityReasons;
  final bool screenCaptureProtectionSupported;
  final bool screenCaptureProtectionEnabled;
  final bool appPreviewProtectionEnabled;
}

final localSecuritySnapshotProvider =
    FutureProvider<LocalSecuritySnapshot>((ref) async {
  final storage = ref.read(secureStorageProvider);
  final appLock = ref.read(appLockServiceProvider);
  final platformSecurityService = ref.read(platformSecurityServiceProvider);
  await platformSecurityService.applyPrivacyProtections();
  final platformSecurity = await platformSecurityService.getStatus();
  final values = await Future.wait<bool>([
    storage.hasDeviceSecretRefs(),
    appLock.hasPin(),
    appLock.canUseBiometrics(),
  ]);

  return LocalSecuritySnapshot(
    hasDeviceSecretRefs: values[0],
    hasPin: values[1],
    biometricsAvailable: values[2],
    integrityCompromised: platformSecurity.integrityCompromised,
    integrityReasons: platformSecurity.integrityReasons,
    screenCaptureProtectionSupported:
        platformSecurity.screenCaptureProtectionSupported,
    screenCaptureProtectionEnabled:
        platformSecurity.screenCaptureProtectionEnabled,
    appPreviewProtectionEnabled: platformSecurity.appPreviewProtectionEnabled,
  );
});
