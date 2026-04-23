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
  static const _refreshTokenKey = 'veil.session.refresh_token';
  static const _userIdKey = 'veil.session.user_id';
  static const _deviceIdKey = 'veil.session.device_id';
  static const _handleKey = 'veil.session.handle';
  static const _displayNameKey = 'veil.session.display_name';
  static const _onboardingAcceptedKey = 'veil.onboarding.accepted';
  static const _privacyConsentKey = 'veil.privacy.consent_accepted';
  // Double Ratchet per-conversation session snapshots, stored as a single
  // JSON blob {conversationId: <snapshot json string>}. Stored as one key so
  // we don't depend on backend enumeration, which FlutterSecureStorage can't
  // do portably.
  static const _sessionSnapshotsKey = 'veil.crypto.session_snapshots';
  // Safety-number verification attestations — records that a conversation's
  // peer identity key was human-verified at a point in time. Single-blob
  // layout for the same portability reason as session snapshots.
  static const _safetyVerificationsKey = 'veil.security.safety_verifications';

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

  Future<String?> readIdentityPrivateRef() async {
    return _storage.read(key: _identityKey);
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
    String? refreshToken,
    required String userId,
    required String deviceId,
    required String handle,
    String? displayName,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _deviceIdKey, value: deviceId);
    await _storage.write(key: _handleKey, value: handle);
    await _storage.write(key: _displayNameKey, value: displayName);
  }

  Future<void> updateAccessTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  Future<StoredSession?> readSession() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
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
      refreshToken: refreshToken,
      userId: userId,
      deviceId: deviceId,
      handle: handle,
      displayName: displayName,
    );
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
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

  Future<Map<String, Map<String, dynamic>>> readAllSessionSnapshots() async {
    final raw = await _storage.read(key: _sessionSnapshotsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final result = <String, Map<String, dynamic>>{};
      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          result[key] = value;
        }
      });
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> writeSessionSnapshot(
    String conversationId,
    Map<String, dynamic> snapshot,
  ) async {
    final all = await readAllSessionSnapshots();
    final next = Map<String, Map<String, dynamic>>.from(all);
    next[conversationId] = snapshot;
    await _storage.write(
      key: _sessionSnapshotsKey,
      value: json.encode(next),
    );
  }

  Future<void> clearSessionSnapshots() async {
    await _storage.delete(key: _sessionSnapshotsKey);
  }

  Future<Map<String, SafetyVerificationRecord>>
      readAllSafetyVerifications() async {
    final raw = await _storage.read(key: _safetyVerificationsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final result = <String, SafetyVerificationRecord>{};
      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final record = SafetyVerificationRecord.tryFromJson(value);
          if (record != null) result[key] = record;
        }
      });
      return result;
    } catch (_) {
      return const {};
    }
  }

  // Composite key format: direct conversations use the raw conversationId;
  // group per-member attestations use "$conversationId:$memberUserId". The
  // colon is safe because both halves are opaque server-generated IDs with
  // no colons of their own. Direct reads stay source-compatible.
  String _safetyVerificationKey(String conversationId, String? memberUserId) {
    if (memberUserId == null || memberUserId.isEmpty) return conversationId;
    return '$conversationId:$memberUserId';
  }

  Future<SafetyVerificationRecord?> readSafetyVerification(
    String conversationId, {
    String? memberUserId,
  }) async {
    final all = await readAllSafetyVerifications();
    return all[_safetyVerificationKey(conversationId, memberUserId)];
  }

  // Returns a map of memberUserId -> record for every per-member attestation
  // stashed against [conversationId]. Useful for rendering the group safety-
  // numbers list without N round-trips.
  Future<Map<String, SafetyVerificationRecord>>
      readSafetyVerificationsForGroup(String conversationId) async {
    final all = await readAllSafetyVerifications();
    final prefix = '$conversationId:';
    final result = <String, SafetyVerificationRecord>{};
    all.forEach((key, value) {
      if (key.startsWith(prefix)) {
        result[key.substring(prefix.length)] = value;
      }
    });
    return result;
  }

  Future<void> writeSafetyVerification(
    String conversationId,
    SafetyVerificationRecord record, {
    String? memberUserId,
  }) async {
    final all = await readAllSafetyVerifications();
    final next = <String, Map<String, dynamic>>{};
    all.forEach((key, value) {
      next[key] = value.toJson();
    });
    next[_safetyVerificationKey(conversationId, memberUserId)] = record.toJson();
    await _storage.write(
      key: _safetyVerificationsKey,
      value: json.encode(next),
    );
  }

  Future<void> clearSafetyVerification(
    String conversationId, {
    String? memberUserId,
  }) async {
    final all = await readAllSafetyVerifications();
    final target = _safetyVerificationKey(conversationId, memberUserId);
    if (!all.containsKey(target)) return;
    final next = <String, Map<String, dynamic>>{};
    all.forEach((key, value) {
      if (key != target) next[key] = value.toJson();
    });
    if (next.isEmpty) {
      await _storage.delete(key: _safetyVerificationsKey);
    } else {
      await _storage.write(
        key: _safetyVerificationsKey,
        value: json.encode(next),
      );
    }
  }

  Future<void> clearAllSafetyVerifications() async {
    await _storage.delete(key: _safetyVerificationsKey);
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

  Future<void> persistPrivacyConsent(bool accepted) {
    return _storage.write(
      key: _privacyConsentKey,
      value: accepted ? 'true' : 'false',
    );
  }

  Future<void> clearPrivacyConsent() async {
    await _storage.delete(key: _privacyConsentKey);
  }

  Future<bool> readPrivacyConsent() async {
    return (await _storage.read(key: _privacyConsentKey)) == 'true';
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
    await clearSessionSnapshots();
    await clearAllSafetyVerifications();
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
    this.refreshToken,
    required this.userId,
    required this.deviceId,
    required this.handle,
    this.displayName,
  });

  final String accessToken;
  final String? refreshToken;
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

class SafetyVerificationRecord {
  const SafetyVerificationRecord({
    required this.peerIdentityPublicKey,
    required this.safetyNumber,
    required this.verifiedAt,
  });

  /// Base64url (no padding) Ed25519 public key the user verified against.
  /// If the peer later rotates identity, the stored value won't match and
  /// the UI must warn.
  final String peerIdentityPublicKey;

  /// 60-digit safety number the user compared.
  final String safetyNumber;

  final DateTime verifiedAt;

  Map<String, dynamic> toJson() => {
        'peerIdentityPublicKey': peerIdentityPublicKey,
        'safetyNumber': safetyNumber,
        'verifiedAt': verifiedAt.toUtc().toIso8601String(),
      };

  static SafetyVerificationRecord? tryFromJson(Map<String, dynamic> json) {
    final peer = json['peerIdentityPublicKey'] as String?;
    final number = json['safetyNumber'] as String?;
    final verifiedAtRaw = json['verifiedAt'] as String?;
    if (peer == null || number == null || verifiedAtRaw == null) {
      return null;
    }
    final verifiedAt = DateTime.tryParse(verifiedAtRaw);
    if (verifiedAt == null) return null;
    return SafetyVerificationRecord(
      peerIdentityPublicKey: peer,
      safetyNumber: number,
      verifiedAt: verifiedAt.toUtc(),
    );
  }
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
