import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureKeyValueStore {
  Future<void> write({required String key, required String? value});

  Future<String?> read({required String key});

  Future<void> delete({required String key});
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String? value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}

class SecureStorageService {
  static const int currentPinIterations = 210000;

  SecureStorageService([SecureKeyValueStore? storage])
      : _storage = storage ??
            const FlutterSecureKeyValueStore(
              FlutterSecureStorage(
                aOptions: AndroidOptions(
                  encryptedSharedPreferences: true,
                  resetOnError: true,
                ),
                iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.unlocked_this_device,
                  synchronizable: false,
                  accountName: 'veil.mobile.secure_storage',
                ),
                mOptions: MacOsOptions(
                  accessibility: KeychainAccessibility.unlocked_this_device,
                  synchronizable: false,
                  accountName: 'veil.mobile.secure_storage',
                ),
              ),
            );

  final SecureKeyValueStore _storage;

  static const _identityKey = 'veil.identity.private_ref';
  static const _authPrivateKey = 'veil.auth.private_key';
  static const _authPublicKey = 'veil.auth.public_key';
  static const _pinKey = 'veil.app_lock.pin_verifier';
  static const _pinFailuresKey = 'veil.app_lock.pin_failures';
  static const _pinLockoutUntilKey = 'veil.app_lock.pin_lockout_until';
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
    return (identityPrivateRef?.isNotEmpty ?? false) &&
        (authPrivateKey?.isNotEmpty ?? false);
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
    final verifier = await _derivePinVerifier(
      pin,
      salt,
      iterations: currentPinIterations,
    );
    await _storage.write(
      key: _pinKey,
      value:
          'v2.$currentPinIterations.${_encodeBytes(salt)}.${_encodeBytes(verifier)}',
    );
    await clearPinThrottleState();
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    if (stored == null || stored.isEmpty) {
      return false;
    }

    final parts = stored.split('.');
    if (parts.isEmpty) {
      return false;
    }

    switch (parts[0]) {
      case 'v1':
        if (parts.length != 3) {
          return false;
        }

        final salt = _decodeBytes(parts[1]);
        final expected = _decodeBytes(parts[2]);
        final derived = await _derivePinVerifier(
          pin,
          salt,
          iterations: 120000,
        );
        final valid = _constantTimeEquals(derived, expected);
        if (valid) {
          await persistPin(pin);
        }
        return valid;
      case 'v2':
        if (parts.length != 4) {
          return false;
        }

        final iterations = int.tryParse(parts[1]);
        if (iterations == null || iterations < 120000) {
          return false;
        }
        final salt = _decodeBytes(parts[2]);
        final expected = _decodeBytes(parts[3]);
        final derived = await _derivePinVerifier(
          pin,
          salt,
          iterations: iterations,
        );
        return _constantTimeEquals(derived, expected);
      default:
        return false;
    }
  }

  Future<bool> hasPin() async =>
      (await _storage.read(key: _pinKey))?.isNotEmpty ?? false;

  Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
    await clearPinThrottleState();
  }

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

  Future<String> readOrCreateDatabaseKeyHex() async {
    final cacheKey = await readOrCreateCacheKey();
    final derived = await _deriveScopedKey(
      _decodeBytes(cacheKey),
      'veil.local-database.v1',
    );
    return _encodeHex(derived);
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

    if (accessToken == null ||
        userId == null ||
        deviceId == null ||
        handle == null) {
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

  Future<void> clearDeviceSecrets() async {
    await _storage.delete(key: _identityKey);
    await _storage.delete(key: _authPrivateKey);
    await _storage.delete(key: _authPublicKey);
  }

  Future<void> clearCacheKey() async {
    await _storage.delete(key: _cacheKey);
  }

  Future<void> persistOnboardingAccepted(bool accepted) {
    return _storage.write(
      key: _onboardingAcceptedKey,
      value: accepted ? 'true' : 'false',
    );
  }

  Future<void> clearOnboardingAccepted() async {
    await _storage.delete(key: _onboardingAcceptedKey);
  }

  Future<bool> readOnboardingAccepted() async {
    return (await _storage.read(key: _onboardingAcceptedKey)) == 'true';
  }

  Future<PinThrottleState> readPinThrottleState() async {
    final failuresRaw = await _storage.read(key: _pinFailuresKey);
    final lockoutUntilRaw = await _storage.read(key: _pinLockoutUntilKey);
    final failures = int.tryParse(failuresRaw ?? '') ?? 0;
    final lockoutUntil = lockoutUntilRaw == null || lockoutUntilRaw.isEmpty
        ? null
        : DateTime.tryParse(lockoutUntilRaw)?.toUtc();
    return PinThrottleState(
      failedAttempts: failures < 0 ? 0 : failures,
      lockoutUntil: lockoutUntil,
    );
  }

  Future<void> persistPinThrottleState(PinThrottleState state) async {
    await _storage.write(
      key: _pinFailuresKey,
      value: '${state.failedAttempts < 0 ? 0 : state.failedAttempts}',
    );
    await _storage.write(
      key: _pinLockoutUntilKey,
      value: state.lockoutUntil?.toUtc().toIso8601String(),
    );
  }

  Future<void> clearPinThrottleState() async {
    await _storage.delete(key: _pinFailuresKey);
    await _storage.delete(key: _pinLockoutUntilKey);
  }

  Future<void> wipeLocalDeviceState({
    bool preserveOnboardingAccepted = true,
    bool preservePin = false,
  }) async {
    await clearSession();
    await clearDeviceSecrets();
    await clearCacheKey();
    await clearPinThrottleState();
    if (!preservePin) {
      await clearPin();
    }
    if (!preserveOnboardingAccepted) {
      await clearOnboardingAccepted();
    }
  }

  static Future<List<int>> _derivePinVerifier(
    String pin,
    List<int> salt, {
    required int iterations,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
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

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static Future<List<int>> _deriveScopedKey(
    List<int> seed,
    String context,
  ) async {
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(seed),
      nonce: utf8.encode('veil-device-scope'),
      info: utf8.encode(context),
    );
    return key.extractBytes();
  }

  static String _encodeHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
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

class PinThrottleState {
  const PinThrottleState({
    this.failedAttempts = 0,
    this.lockoutUntil,
  });

  final int failedAttempts;
  final DateTime? lockoutUntil;

  bool get isLockedOut =>
      lockoutUntil != null && lockoutUntil!.isAfter(DateTime.now().toUtc());
}
