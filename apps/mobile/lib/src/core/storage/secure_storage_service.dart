import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/crypto_engine.dart';
import '../crypto/ratchet/session_lock.dart';
import '../identity/identity_key_value_backend.dart';

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
  // Persistent tier that survives a single lockout window. Each time the
  // user burns through `maxFailedPinAttempts`, tier is incremented and the
  // next lockout length grows exponentially. A successful unlock resets it.
  static const _pinLockoutTierKey = 'veil.app_lock.pin_lockout_tier';
  static const _cacheKey = 'veil.cache.encryption_key';
  static const _accessTokenKey = 'veil.session.access_token';
  static const _refreshTokenKey = 'veil.session.refresh_token';
  static const _userIdKey = 'veil.session.user_id';
  static const _deviceIdKey = 'veil.session.device_id';
  static const _handleKey = 'veil.session.handle';
  static const _displayNameKey = 'veil.session.display_name';
  static const _onboardingAcceptedKey = 'veil.onboarding.accepted';
  static const _privacyConsentKey = 'veil.privacy.consent_accepted';
  // User-selected theme mode, stored as a stable string ('light'|'dark'|
  // 'system'). Non-sensitive, but kept in the same store so the app does not
  // depend on an additional plain key-value plugin.
  static const _themeModeKey = 'veil.settings.theme_mode';
  // Pre-v4 layout: every conversation's session snapshot in ONE blob, so
  // concurrent writers lost each other's updates. Migrated once into the
  // per-conversation layout below, then deleted.
  static const _legacySessionSnapshotsKey = 'veil.crypto.session_snapshots';
  // One entry per conversation under 'veil.crypto.session.<sha256hex(id)>'
  // (the id is hashed so key names never carry it), plus an index listing
  // the ids, because FlutterSecureStorage cannot enumerate keys portably.
  static const _sessionIndexKey = 'veil.crypto.session_index';
  static const _sessionKeyPrefix = 'veil.crypto.session.';
  // Group Sender Keys per-group chain state, single-blob layout:
  // {groupId: <snapshot json>}. Wiped together with session snapshots.
  static const _groupSenderKeysKey = 'veil.crypto.group_sender_keys';
  // Prekey private halves: 'veil.crypto.opk.<id>' / 'veil.crypto.spk.<id>'
  // plus an index of ids and the next one-time prekey id.
  static const _prekeyIndexKey = 'veil.crypto.prekey_index';
  static const _oneTimePrekeyPrefix = 'veil.crypto.opk.';
  static const _signedPrekeyPrefix = 'veil.crypto.spk.';
  static const _cryptoQueueKey = 'crypto-state';
  // Safety-number verifications of earlier builds, keyed by conversation
  // ("conversationId" or "conversationId:memberUserId"). Only read once, to
  // carry them into the identity pin table, then deleted.
  static const _safetyVerificationsKey = 'veil.security.safety_verifications';

  // Every crypto-state read-modify-write goes through this one serial queue,
  // so index updates never interleave and a slower older write cannot land
  // after a newer one.
  final SessionLock _cryptoQueue = SessionLock();
  final Map<String, int> _sessionRevs = {};
  bool _legacySessionsMigrated = false;

  Future<T> _serialCrypto<T>(Future<T> Function() action) => _cryptoQueue.synchronized(_cryptoQueueKey, action);

  /// Read/write/delete confined to [scope]'s keys.
  ScopedSecureStore scoped(SecureScope scope) => ScopedSecureStore._(this, scope);

  /// Stores a new device identity. Prekeys of an earlier identity are
  /// dropped with it: once rotations fill the prekey store it takes
  /// precedence over the signed prekey embedded in the identity ref.
  Future<void> persistDeviceSecretRefs({
    required String identityPrivateRef,
    required String authPrivateKey,
    required String authPublicKey,
  }) async {
    await clearPrekeys();
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

  /// Replaces the identity ref with the same identity in a newer encoding
  /// (a v1 ref upgraded by its first signed-prekey rotation).
  Future<void> replaceIdentityPrivateRef(String identityPrivateRef) =>
      _storage.write(key: _identityKey, value: identityPrivateRef);

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

  /// The user's own nickname. Local only: the relay never stores one.
  Future<void> persistLocalNickname(String? nickname) => nickname == null || nickname.isEmpty
      ? _storage.delete(key: _displayNameKey)
      : _storage.write(key: _displayNameKey, value: nickname);

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

  Future<Map<String, Map<String, dynamic>>> readAllSessionSnapshots() => _serialCrypto(() async {
        await _migrateLegacySessionsOnce();
        final result = <String, Map<String, dynamic>>{};
        for (final conversationId in await _readSessionIndex()) {
          final snapshot = _decodeJsonObject(await _storage.read(key: _sessionKey(conversationId)));
          if (snapshot == null) continue;
          result[conversationId] = snapshot;
          final rev = (snapshot['rev'] as num?)?.toInt();
          if (rev != null) _sessionRevs[conversationId] = rev;
        }
        return result;
      });

  /// Refuses (throws [StateError]) when the stored snapshot already has a
  /// higher `rev`, so an older ratchet state can never overwrite a newer
  /// one. The refusal is loud because the caller treats completion as
  /// durability and would otherwise publish state that is not on disk.
  Future<void> writeSessionSnapshot(
    String conversationId,
    Map<String, dynamic> snapshot,
  ) =>
      _serialCrypto(() async {
        await _migrateLegacySessionsOnce();
        final incomingRev = (snapshot['rev'] as num?)?.toInt();
        final storedRev = await _storedSessionRev(conversationId);
        if (incomingRev != null && storedRev != null && incomingRev < storedRev) {
          throw StateError('Session snapshot rev $incomingRev is older than the stored rev $storedRev.');
        }
        final index = await _readSessionIndex();
        if (!index.contains(conversationId)) {
          await _writeSessionIndex([...index, conversationId]);
        }
        await _storage.write(key: _sessionKey(conversationId), value: json.encode(snapshot));
        if (incomingRev != null) _sessionRevs[conversationId] = incomingRev;
      });

  Future<void> clearSessionSnapshots() => _serialCrypto(() async {
        for (final conversationId in await _readSessionIndex()) {
          await _storage.delete(key: _sessionKey(conversationId));
        }
        await _storage.delete(key: _sessionIndexKey);
        await _storage.delete(key: _legacySessionSnapshotsKey);
        _sessionRevs.clear();
        _legacySessionsMigrated = true;
      });

  Future<void> _migrateLegacySessionsOnce() async {
    if (_legacySessionsMigrated) return;
    final legacy = _decodeJsonObject(await _storage.read(key: _legacySessionSnapshotsKey));
    if (legacy != null) {
      final index = await _readSessionIndex();
      for (final entry in legacy.entries) {
        if (entry.value is! Map<String, dynamic> || index.contains(entry.key)) continue;
        index.add(entry.key);
        await _writeSessionIndex(index);
        await _storage.write(key: _sessionKey(entry.key), value: json.encode(entry.value));
      }
      await _storage.delete(key: _legacySessionSnapshotsKey);
    }
    _legacySessionsMigrated = true;
  }

  Future<int?> _storedSessionRev(String conversationId) async {
    final cached = _sessionRevs[conversationId];
    if (cached != null) return cached;
    final stored = _decodeJsonObject(await _storage.read(key: _sessionKey(conversationId)));
    return (stored?['rev'] as num?)?.toInt();
  }

  Future<List<String>> _readSessionIndex() async {
    final raw = await _storage.read(key: _sessionIndexKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      return (json.decode(raw) as List<dynamic>).cast<String>().toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _writeSessionIndex(List<String> index) =>
      _storage.write(key: _sessionIndexKey, value: json.encode(index));

  static String _sessionKey(String conversationId) =>
      '$_sessionKeyPrefix${hash.sha256.convert(utf8.encode(conversationId))}';

  Future<Map<String, Map<String, dynamic>>> readAllGroupSenderKeySnapshots() =>
      _serialCrypto(_readGroupSenderKeySnapshots);

  Future<Map<String, Map<String, dynamic>>> _readGroupSenderKeySnapshots() async {
    final decoded = _decodeJsonObject(await _storage.read(key: _groupSenderKeysKey));
    if (decoded == null) return const {};
    final result = <String, Map<String, dynamic>>{};
    decoded.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        result[key] = value;
      }
    });
    return result;
  }

  /// `snapshot == null` deletes the group's entry (member left / wiped).
  Future<void> writeGroupSenderKeySnapshot(
    String groupId,
    Map<String, dynamic>? snapshot,
  ) =>
      _serialCrypto(() async {
        final next = Map<String, Map<String, dynamic>>.from(await _readGroupSenderKeySnapshots());
        if (snapshot == null) {
          next.remove(groupId);
        } else {
          next[groupId] = snapshot;
        }
        if (next.isEmpty) {
          await _storage.delete(key: _groupSenderKeysKey);
          return;
        }
        await _storage.write(key: _groupSenderKeysKey, value: json.encode(next));
      });

  Future<void> clearGroupSenderKeySnapshots() => _serialCrypto(() => _storage.delete(key: _groupSenderKeysKey));

  Future<void> clearPrekeys() => _serialCrypto(() async {
        final index = await _readPrekeyIndex();
        for (final keyId in index.oneTimeIds) {
          await _storage.delete(key: '$_oneTimePrekeyPrefix$keyId');
        }
        for (final keyId in index.signedIds) {
          await _storage.delete(key: '$_signedPrekeyPrefix$keyId');
        }
        await _storage.delete(key: _prekeyIndexKey);
      });

  Future<_PrekeyIndex> _readPrekeyIndex() async =>
      _PrekeyIndex.fromJson(_decodeJsonObject(await _storage.read(key: _prekeyIndexKey)));

  Future<void> _writePrekeyIndex(_PrekeyIndex index) =>
      _storage.write(key: _prekeyIndexKey, value: json.encode(index.toJson()));

  static Map<String, dynamic>? _decodeJsonObject(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
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

  /// Persist the selected theme mode as a stable string. Accepts one of
  /// 'light', 'dark', or 'system'.
  Future<void> persistThemeMode(String mode) {
    return _storage.write(key: _themeModeKey, value: mode);
  }

  /// Read the persisted theme mode string, or null if none has been saved.
  Future<String?> readThemeMode() async {
    return _storage.read(key: _themeModeKey);
  }

  Future<PinThrottleState> readPinThrottleState() async {
    final failuresRaw = await _storage.read(key: _pinFailuresKey);
    final lockoutUntilRaw = await _storage.read(key: _pinLockoutUntilKey);
    final tierRaw = await _storage.read(key: _pinLockoutTierKey);
    final failures = int.tryParse(failuresRaw ?? '') ?? 0;
    final tier = int.tryParse(tierRaw ?? '') ?? 0;
    final lockoutUntil = lockoutUntilRaw == null || lockoutUntilRaw.isEmpty
        ? null
        : DateTime.tryParse(lockoutUntilRaw)?.toUtc();
    return PinThrottleState(
      failedAttempts: failures < 0 ? 0 : failures,
      lockoutUntil: lockoutUntil,
      lockoutTier: tier < 0 ? 0 : tier,
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
    await _storage.write(
      key: _pinLockoutTierKey,
      value: '${state.lockoutTier < 0 ? 0 : state.lockoutTier}',
    );
  }

  Future<void> clearPinThrottleState() async {
    await _storage.delete(key: _pinFailuresKey);
    await _storage.delete(key: _pinLockoutUntilKey);
    await _storage.delete(key: _pinLockoutTierKey);
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
    await clearGroupSenderKeySnapshots();
    await clearPrekeys();
    await clearAllSafetyVerifications();
    for (final scope in SecureScope.values) {
      await scoped(scope).clear();
    }
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

/// Namespaces that features keep their own small documents under. Every one
/// is forgotten when the device's local state is wiped.
enum SecureScope {
  /// Contact identity pins (trust on first use).
  identity('veil.identity'),

  /// Per-conversation security policy, such as accepted envelope versions.
  conversationPolicy('veil.conversation_policy'),

  /// Privacy switches the user set on this device.
  privacy('veil.settings.privacy'),

  /// Private nicknames for contacts.
  contacts('veil.contacts');

  const SecureScope(this.namespace);

  final String namespace;
}

/// The keystore seen through one [SecureScope]. FlutterSecureStorage cannot
/// enumerate keys, so the scope records every key it writes in an index;
/// that is what lets [clear] forget all of them.
class ScopedSecureStore implements IdentityKeyValueBackend {
  ScopedSecureStore._(this._service, this._scope);

  final SecureStorageService _service;
  final SecureScope _scope;

  SecureKeyValueStore get _storage => _service._storage;

  String _qualified(String key) => '${_scope.namespace}.$key';

  String get _indexKey => '${_scope.namespace}#keys';

  Future<T> _serial<T>(Future<T> Function() action) =>
      _service._cryptoQueue.synchronized(_scope.namespace, action);

  @override
  Future<String?> read(String key) => _storage.read(key: _qualified(key));

  @override
  Future<void> write(String key, String value) => _serial(() async {
        final keys = await _readIndex();
        if (keys.add(key)) await _writeIndex(keys);
        await _storage.write(key: _qualified(key), value: value);
      });

  @override
  Future<void> delete(String key) => _serial(() async {
        await _storage.delete(key: _qualified(key));
        final keys = await _readIndex();
        if (keys.remove(key)) await _writeIndex(keys);
      });

  Future<void> clear() => _serial(() async {
        for (final key in await _readIndex()) {
          await _storage.delete(key: _qualified(key));
        }
        await _storage.delete(key: _indexKey);
      });

  Future<Set<String>> _readIndex() async {
    final raw = await _storage.read(key: _indexKey);
    final decoded = raw == null ? null : json.decode(raw);
    return {if (decoded is List) ...decoded.whereType<String>()};
  }

  Future<void> _writeIndex(Set<String> keys) =>
      _storage.write(key: _indexKey, value: json.encode(keys.toList()));
}

/// [LocalPrekeyStore] backed by the device keystore. Shares
/// [SecureStorageService]'s serial crypto queue so prekey index updates
/// never race session or group writes.
class SecureStorageLocalPrekeyStore implements LocalPrekeyStore {
  SecureStorageLocalPrekeyStore(this._service);

  final SecureStorageService _service;

  SecureKeyValueStore get _storage => _service._storage;

  static String _oneTimeKey(int keyId) => '${SecureStorageService._oneTimePrekeyPrefix}$keyId';

  static String _signedKey(int keyId) => '${SecureStorageService._signedPrekeyPrefix}$keyId';

  @override
  Future<int> reserveOneTimePrekeyIds(int count) => _service._serialCrypto(() async {
        final index = await _service._readPrekeyIndex();
        final first = index.nextOneTimeId;
        index.nextOneTimeId += count;
        await _service._writePrekeyIndex(index);
        return first;
      });

  @override
  Future<void> saveOneTimePrekey(int keyId, List<int> privateKey) => _service._serialCrypto(() async {
        final index = await _service._readPrekeyIndex();
        index.oneTimeIds.add(keyId);
        await _service._writePrekeyIndex(index);
        await _storage.write(key: _oneTimeKey(keyId), value: SecureStorageService._encodeBytes(privateKey));
      });

  @override
  Future<List<int>?> loadOneTimePrekey(int keyId) => _service._serialCrypto(() async {
        final raw = await _storage.read(key: _oneTimeKey(keyId));
        return raw == null || raw.isEmpty ? null : SecureStorageService._decodeBytes(raw);
      });

  @override
  Future<void> deleteOneTimePrekey(int keyId) => _service._serialCrypto(() async {
        await _storage.delete(key: _oneTimeKey(keyId));
        final index = await _service._readPrekeyIndex();
        if (index.oneTimeIds.remove(keyId)) await _service._writePrekeyIndex(index);
      });

  @override
  Future<void> saveSignedPrekey(StoredSignedPrekey prekey) => _service._serialCrypto(() async {
        final index = await _service._readPrekeyIndex();
        index.signedIds.add(prekey.keyId);
        await _service._writePrekeyIndex(index);
        await _storage.write(
          key: _signedKey(prekey.keyId),
          value: json.encode({
            'priv': SecureStorageService._encodeBytes(prekey.privateKey),
            'ts': prekey.createdAt.millisecondsSinceEpoch,
          }),
        );
      });

  @override
  Future<List<StoredSignedPrekey>> loadSignedPrekeys() => _service._serialCrypto(() async {
        final index = await _service._readPrekeyIndex();
        final prekeys = <StoredSignedPrekey>[];
        for (final keyId in index.signedIds) {
          final entry = SecureStorageService._decodeJsonObject(await _storage.read(key: _signedKey(keyId)));
          if (entry == null) continue;
          prekeys.add(StoredSignedPrekey(
            keyId: keyId,
            privateKey: SecureStorageService._decodeBytes(entry['priv'] as String),
            createdAt: DateTime.fromMillisecondsSinceEpoch((entry['ts'] as num).toInt(), isUtc: true),
          ));
        }
        return prekeys;
      });

  @override
  Future<void> deleteSignedPrekey(int keyId) => _service._serialCrypto(() async {
        await _storage.delete(key: _signedKey(keyId));
        final index = await _service._readPrekeyIndex();
        if (index.signedIds.remove(keyId)) await _service._writePrekeyIndex(index);
      });

  @override
  Future<SignedPrekeyPublication?> loadSignedPrekeyPublication() =>
      _service._serialCrypto(() async => (await _service._readPrekeyIndex()).publication);

  @override
  Future<void> saveSignedPrekeyPublication(SignedPrekeyPublication publication) => _service._serialCrypto(() async {
        final index = await _service._readPrekeyIndex();
        index.publication = publication;
        await _service._writePrekeyIndex(index);
      });
}

// Kept with the prekeys it describes, so a new identity, which clears them,
// also forgets which signed prekey the directory served for the old one.
class _PrekeyIndex {
  _PrekeyIndex(this.nextOneTimeId, this.oneTimeIds, this.signedIds, this.publication);

  factory _PrekeyIndex.fromJson(Map<String, dynamic>? json) {
    final published = json?['published'];
    return _PrekeyIndex(
      (json?['nextOpk'] as num?)?.toInt() ?? 1,
      {...(json?['opk'] as List<dynamic>? ?? const []).cast<int>()},
      {...(json?['spk'] as List<dynamic>? ?? const []).cast<int>()},
      published is Map<String, dynamic>
          ? SignedPrekeyPublication(
              spkId: (published['id'] as num).toInt(),
              publishedAt: DateTime.fromMillisecondsSinceEpoch((published['ts'] as num).toInt(), isUtc: true),
            )
          : null,
    );
  }

  int nextOneTimeId;
  final Set<int> oneTimeIds;
  final Set<int> signedIds;
  SignedPrekeyPublication? publication;

  Map<String, dynamic> toJson() => {
        'nextOpk': nextOneTimeId,
        'opk': oneTimeIds.toList(),
        'spk': signedIds.toList(),
        if (publication case final published?)
          'published': {'id': published.spkId, 'ts': published.publishedAt.millisecondsSinceEpoch},
      };
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

/// A safety-number verification as earlier builds stored it, before the
/// identity pin table recorded verifications itself.
class SafetyVerificationRecord {
  const SafetyVerificationRecord({
    required this.peerIdentityPublicKey,
    required this.verifiedAt,
  });

  /// Base64url (no padding) Ed25519 public key the user verified.
  final String peerIdentityPublicKey;

  final DateTime verifiedAt;

  static SafetyVerificationRecord? tryFromJson(Map<String, dynamic> json) {
    final peer = json['peerIdentityPublicKey'] as String?;
    final verifiedAtRaw = json['verifiedAt'] as String?;
    if (peer == null || verifiedAtRaw == null) {
      return null;
    }
    final verifiedAt = DateTime.tryParse(verifiedAtRaw);
    if (verifiedAt == null) return null;
    return SafetyVerificationRecord(peerIdentityPublicKey: peer, verifiedAt: verifiedAt.toUtc());
  }
}

class PinThrottleState {
  const PinThrottleState({
    this.failedAttempts = 0,
    this.lockoutUntil,
    this.lockoutTier = 0,
  });

  final int failedAttempts;
  final DateTime? lockoutUntil;
  // Number of lockout rounds served so far in this failure streak. Used by
  // AppLockService to grow the next lockout exponentially. Cleared on a
  // successful PIN entry.
  final int lockoutTier;

  bool get isLockedOut =>
      lockoutUntil != null && lockoutUntil!.isAfter(DateTime.now().toUtc());
}
