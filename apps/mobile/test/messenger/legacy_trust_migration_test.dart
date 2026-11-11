import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/legacy_trust_migration.dart';

import '../support/memory_secure_store.dart';

String _key(int fill) => base64Url.encode(List<int>.filled(32, fill)).replaceAll('=', '');

const _legacyVerificationsKey = 'veil.security.safety_verifications';

ConversationPreview _direct(String id, {required String userId, required String deviceId, required String key}) =>
    ConversationPreview(
      id: id,
      peerHandle: userId,
      peerDisplayName: null,
      recipientBundle: KeyBundle(
        userId: userId,
        deviceId: deviceId,
        handle: userId,
        identityPublicKey: key,
        signedPrekeyBundle: '',
      ),
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 1, 1),
      sessionState: ConversationSessionState(
        sessionLocator: 'session://$id',
        sessionEnvelopeVersion: 'veil-envelope-v2',
        requiresLocalPersistence: true,
        sessionSchemaVersion: 4,
        localDeviceId: 'dev-me',
        remoteDeviceId: deviceId,
        remoteIdentityFingerprint: 'fp',
        bootstrappedAt: DateTime.utc(2026, 1, 1),
        remoteIdentityPublicKey: key,
      ),
    );

void main() {
  late MemorySecureStore keystore;
  late SecureStorageService storage;
  late TrustedIdentityResolver resolver;

  setUp(() {
    keystore = MemorySecureStore();
    storage = SecureStorageService(keystore);
    resolver = TrustedIdentityResolver(store: TrustedIdentityStore(storage.scoped(SecureScope.identity)));
  });

  Future<void> writeLegacyVerifications(Map<String, Map<String, String>> records) =>
      keystore.write(key: _legacyVerificationsKey, value: json.encode(records));

  test('a verification of the session key becomes the pin verifiedAt', () async {
    final verifiedAt = DateTime.utc(2026, 4, 23, 8);
    await writeLegacyVerifications({
      'conv-alice': {
        'peerIdentityPublicKey': _key(1),
        'safetyNumber': '1' * 60,
        'verifiedAt': verifiedAt.toIso8601String(),
      },
      // A group member's record names no device and cannot be placed.
      'conv-group:user-carol': {'peerIdentityPublicKey': _key(3), 'verifiedAt': verifiedAt.toIso8601String()},
    });

    await migrateLegacyTrust(
      storage: storage,
      resolver: resolver,
      conversations: [_direct('conv-alice', userId: 'user-alice', deviceId: 'dev-alice', key: _key(1))],
    );

    final pin = (await resolver.pinFor('user-alice', 'dev-alice'))!;
    expect(pin.identityKey, _key(1));
    expect(pin.verifiedAt, verifiedAt);
    expect(await resolver.pinsForUser('user-carol'), isEmpty);
    expect(await storage.readAllSafetyVerifications(), isEmpty);
  });

  test('session keys are pinned unverified, and a verification of another key is dropped', () async {
    await writeLegacyVerifications({
      'conv-bob': {'peerIdentityPublicKey': _key(9), 'verifiedAt': DateTime.utc(2026, 4, 1).toIso8601String()},
    });

    await migrateLegacyTrust(
      storage: storage,
      resolver: resolver,
      conversations: [_direct('conv-bob', userId: 'user-bob', deviceId: 'dev-bob', key: _key(2))],
    );

    final pin = (await resolver.pinFor('user-bob', 'dev-bob'))!;
    expect(pin.identityKey, _key(2));
    expect(pin.isVerified, isFalse);
  });

  test('an existing pin is never replaced and the migration runs once', () async {
    await resolver.evaluate('user-bob', 'dev-bob', _key(5));
    await migrateLegacyTrust(
      storage: storage,
      resolver: resolver,
      conversations: [_direct('conv-bob', userId: 'user-bob', deviceId: 'dev-bob', key: _key(2))],
    );
    expect((await resolver.pinFor('user-bob', 'dev-bob'))!.identityKey, _key(5));

    await migrateLegacyTrust(
      storage: storage,
      resolver: resolver,
      conversations: [_direct('conv-dave', userId: 'user-dave', deviceId: 'dev-dave', key: _key(6))],
    );
    expect(await resolver.pinsForUser('user-dave'), isEmpty);
  });

  test('wiping the device forgets every pin', () async {
    await resolver.evaluate('user-alice', 'dev-alice', _key(1));

    await storage.wipeLocalDeviceState();

    expect(await resolver.pinsForUser('user-alice'), isEmpty);
    expect(keystore.values.keys.where((key) => key.startsWith(SecureScope.identity.namespace)), isEmpty);
  });
}
