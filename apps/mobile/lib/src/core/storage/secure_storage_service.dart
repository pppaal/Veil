import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _identityKey = 'veil.identity.private_ref';
  static const _authPrivateKey = 'veil.auth.private_key';
  static const _authPublicKey = 'veil.auth.public_key';
  static const _pinKey = 'veil.app_lock.pin_verifier';
  static const _cacheKey = 'veil.cache.encryption_key';
  static const _accessTokenKey = 'veil.session.access_token';
  static const _userIdKey = 'veil.session.user_id';
  static const _deviceIdKey = 'veil.session.device_id';
  static const _handleKey = 'veil.session.handle';
  static const _displayNameKey = 'veil.session.display_name';
  static const _onboardingAcceptedKey = 'veil.onboarding.accepted';

  Future<void> persistDeviceSecretRefs({
    required String identityPrivateRef,
    required String authPrivateKey,
    required String authPublicKey,
  }) async {
    await _storage.write(key: _identityKey, value: identityPrivateRef);
    await _storage.write(key: _authPrivateKey, value: authPrivateKey);
    await _storage.write(key: _authPublicKey, value: authPublicKey);
  }

  Future<bool> hasDeviceSecretRefs() async {
    final identityPrivateRef = await _storage.read(key: _identityKey);
    final authPrivateKey = await _storage.read(key: _authPrivateKey);
    return (identityPrivateRef?.isNotEmpty ?? false) && (authPrivateKey?.isNotEmpty ?? false);
  }

  Future<StoredAuthKeyMaterial?> readAuthKeyMaterial() async {
    final privateKey = await _storage.read(key: _authPrivateKey);
    final publicKey = await _storage.read(key: _authPublicKey);

    if (privateKey == null || publicKey == null) {
      return null;
    }

    return StoredAuthKeyMaterial(
      privateKey: privateKey,
      publicKey: publicKey,
    );
  }

  Future<void> persistPin(String pin) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final verifier = await _derivePinVerifier(pin, salt);
    await _storage.write(
      key: _pinKey,
      value: 'v1.${_encodeBytes(salt)}.${_encodeBytes(verifier)}',
    );
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    if (stored == null || stored.isEmpty) {
      return false;
    }

    final parts = stored.split('.');
    if (parts.length != 3 || parts[0] != 'v1') {
      return false;
    }

    final salt = _decodeBytes(parts[1]);
    final expected = parts[2];
    final derived = _encodeBytes(await _derivePinVerifier(pin, salt));
    return derived == expected;
  }

  Future<bool> hasPin() async => (await _storage.read(key: _pinKey))?.isNotEmpty ?? false;

  Future<String> readOrCreateCacheKey() async {
    final existing = await _storage.read(key: _cacheKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = _encodeBytes(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    await _storage.write(key: _cacheKey, value: generated);
    return generated;
  }

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

  static Future<List<int>> _derivePinVerifier(String pin, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final key = await pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    return key.extractBytes();
  }

  static String _encodeBytes(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _decodeBytes(String value) {
    final normalized = value.padRight(
      value.length + ((4 - value.length % 4) % 4),
      '=',
    );
    return base64Url.decode(normalized);
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

class StoredAuthKeyMaterial {
  const StoredAuthKeyMaterial({
    required this.privateKey,
    required this.publicKey,
  });

  final String privateKey;
  final String publicKey;
}
