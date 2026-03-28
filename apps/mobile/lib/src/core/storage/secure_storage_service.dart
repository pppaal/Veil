import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _identityKey = 'veil.identity.private_ref';
  static const _authKey = 'veil.auth.private_ref';
  static const _pinKey = 'veil.app_lock.pin';
  static const _accessTokenKey = 'veil.session.access_token';
  static const _userIdKey = 'veil.session.user_id';
  static const _deviceIdKey = 'veil.session.device_id';
  static const _handleKey = 'veil.session.handle';
  static const _displayNameKey = 'veil.session.display_name';
  static const _onboardingAcceptedKey = 'veil.onboarding.accepted';

  Future<void> persistDeviceSecretRefs({
    required String identityPrivateRef,
    required String authPrivateRef,
  }) async {
    await _storage.write(key: _identityKey, value: identityPrivateRef);
    await _storage.write(key: _authKey, value: authPrivateRef);
  }

  Future<bool> hasDeviceSecretRefs() async {
    final identityPrivateRef = await _storage.read(key: _identityKey);
    final authPrivateRef = await _storage.read(key: _authKey);
    return (identityPrivateRef?.isNotEmpty ?? false) && (authPrivateRef?.isNotEmpty ?? false);
  }

  Future<void> persistPin(String pin) => _storage.write(key: _pinKey, value: pin);

  Future<String?> readPin() => _storage.read(key: _pinKey);

  Future<bool> hasPin() async => (await readPin())?.isNotEmpty ?? false;

  Future<void> persistSession({
    required String accessToken,
    required String userId,
    required String deviceId,
    required String handle,
    String? displayName,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _deviceIdKey, value: deviceId);
    await _storage.write(key: _handleKey, value: handle);
    await _storage.write(key: _displayNameKey, value: displayName);
  }

  Future<StoredSession?> readSession() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final userId = await _storage.read(key: _userIdKey);
    final deviceId = await _storage.read(key: _deviceIdKey);
    final handle = await _storage.read(key: _handleKey);
    final displayName = await _storage.read(key: _displayNameKey);

    if (accessToken == null || userId == null || deviceId == null || handle == null) {
      return null;
    }

    return StoredSession(
      accessToken: accessToken,
      userId: userId,
      deviceId: deviceId,
      handle: handle,
      displayName: displayName,
    );
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _deviceIdKey);
    await _storage.delete(key: _handleKey);
    await _storage.delete(key: _displayNameKey);
  }

  Future<void> persistOnboardingAccepted(bool accepted) {
    return _storage.write(
      key: _onboardingAcceptedKey,
      value: accepted ? 'true' : 'false',
    );
  }

  Future<bool> readOnboardingAccepted() async {
    return (await _storage.read(key: _onboardingAcceptedKey)) == 'true';
  }
}

class StoredSession {
  const StoredSession({
    required this.accessToken,
    required this.userId,
    required this.deviceId,
    required this.handle,
    this.displayName,
  });

  final String accessToken;
  final String userId;
  final String deviceId;
  final String handle;
  final String? displayName;
}
