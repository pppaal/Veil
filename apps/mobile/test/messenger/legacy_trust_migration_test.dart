import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/legacy_trust_migration.dart';

import '../support/memory_secure_store.dart';

String _key(int fill) => base64Url.encode(List<int>.filled(32, fill)).replaceAll('=', '');

const _legacyVerificationsKey = 'veil.security.safety_verifications';

/// A direct conversation as an earlier build cached it. [sessionKey] is
/// the identity key its session recorded: empty for sessions from builds
/// that did not record one; a null [sessionDeviceId] means no session.
ConversationPreview _direct(
  String id, {
  required String userId,
  required String key,
  String bundleDeviceId = 'dev-bundle',
  String? sessionDeviceId,
  String? sessionKey,
}) =>
    ConversationPreview(
      id: id,
      peerHandle: userId,
      peerDisplayName: null,
      recipientBundle: KeyBundle(
        userId: userId,
        deviceId: bundleDeviceId,
        handle: userId,
        identityPublicKey: key,
        signedPrekeyBundle: '',
      ),
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 1, 1),
      sessionState: sessionDeviceId == null
          ? null
          : ConversationSessionState(
              sessionLocator: 'session://$id',
              sessionEnvelopeVersion: 'veil-envelope-v2',
              requiresLocalPersistence: true,
              sessionSchemaVersion: 4,
              localDeviceId: 'dev-me',
              remoteDeviceId: sessionDeviceId,
              remoteIdentityFingerprint: 'fp',
              bootstrappedAt: DateTime.utc(2026, 1, 1),
              remoteIdentityPublicKey: sessionKey ?? key,
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

  Future<void> migrate(List<ConversationPreview> conversations) => migrateLegacyTrust(
        storage: storage,
        resolver: resolver,
        readConversations: () async => conversations,
      );

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

    await migrate([_direct('conv-alice', userId: 'user-alice', sessionDeviceId: 'dev-alice', key: _key(1))]);

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

    await migrate([_direct('conv-bob', userId: 'user-bob', sessionDeviceId: 'dev-bob', key: _key(2))]);

    final pin = (await resolver.pinFor('user-bob', 'dev-bob'))!;
    expect(pin.identityKey, _key(2));
    expect(pin.isVerified, isFalse);
  });

  test('a verification survives a session that recorded no key, on the session device', () async {
    final verifiedAt = DateTime.utc(2026, 3, 2);
    await writeLegacyVerifications({
      'conv-erin': {'peerIdentityPublicKey': _key(4), 'verifiedAt': verifiedAt.toIso8601String()},
      'conv-finn': {'peerIdentityPublicKey': _key(5), 'verifiedAt': verifiedAt.toIso8601String()},
    });

    await migrate([
      _direct('conv-erin', userId: 'user-erin', key: _key(4), sessionDeviceId: 'dev-erin', sessionKey: ''),
      // No session at all: the device of the bundle that was verified.
      _direct('conv-finn', userId: 'user-finn', key: _key(5), bundleDeviceId: 'dev-finn'),
    ]);

    final erin = (await resolver.pinFor('user-erin', 'dev-erin'))!;
    expect(erin.identityKey, _key(4));
    expect(erin.verifiedAt, verifiedAt);
    expect(await resolver.pinsForUser('user-erin'), hasLength(1));
    final finn = (await resolver.pinFor('user-finn', 'dev-finn'))!;
    expect(finn.identityKey, _key(5));
    expect(finn.isVerified, isTrue);
  });

  test('an inbound handshake before the migration finishes meets the migrated pin', () async {
    await writeLegacyVerifications({
      'conv-erin': {'peerIdentityPublicKey': _key(4), 'verifiedAt': DateTime.utc(2026, 3, 2).toIso8601String()},
    });
    final cached = Completer<List<ConversationPreview>>();
    final trust = IdentityTrust(
      resolver,
      ready: migrateLegacyTrust(storage: storage, resolver: resolver, readConversations: () => cached.future),
    );
    addTearDown(trust.dispose);

    // A forged PreKey frame for erin's device arrives while the cache opens.
    final forged = trust.admit('conv-erin', 'user-erin', 'dev-erin', _key(7));
    cached.complete([_direct('conv-erin', userId: 'user-erin', key: _key(4), sessionDeviceId: 'dev-erin', sessionKey: '')]);

    expect(await forged, isFalse);
    expect(trust.pendingFor('conv-erin')!.requiresReverification, isTrue);
    final pin = (await resolver.pinFor('user-erin', 'dev-erin'))!;
    expect(pin.identityKey, _key(4));
    expect(pin.isVerified, isTrue);
  });

  test('a migration that fails holds every decision back', () async {
    final trust = IdentityTrust(
      resolver,
      ready: migrateLegacyTrust(
        storage: storage,
        resolver: resolver,
        readConversations: () async => throw StateError('cache unavailable'),
      ),
    );
    addTearDown(trust.dispose);

    await expectLater(trust.admit('conv-erin', 'user-erin', 'dev-erin', _key(7)), throwsStateError);
    expect(await resolver.pinsForUser('user-erin'), isEmpty);
  });

  test('a legacy key that does not decode is skipped', () async {
    await writeLegacyVerifications({
      'conv-gus': {'peerIdentityPublicKey': '!!', 'verifiedAt': DateTime.utc(2026, 3, 2).toIso8601String()},
    });

    await migrate([
      _direct('conv-gus', userId: 'user-gus', key: '!!', sessionDeviceId: 'dev-gus', sessionKey: ''),
      _direct('conv-bob', userId: 'user-bob', sessionDeviceId: 'dev-bob', key: _key(2)),
    ]);

    expect(await resolver.pinsForUser('user-gus'), isEmpty);
    expect((await resolver.pinFor('user-bob', 'dev-bob'))!.identityKey, _key(2));
  });

  test('an existing pin is never replaced and the migration runs once', () async {
    await resolver.evaluate('user-bob', 'dev-bob', _key(5));
    await migrate([_direct('conv-bob', userId: 'user-bob', sessionDeviceId: 'dev-bob', key: _key(2))]);
    expect((await resolver.pinFor('user-bob', 'dev-bob'))!.identityKey, _key(5));

    await migrate([_direct('conv-dave', userId: 'user-dave', sessionDeviceId: 'dev-dave', key: _key(6))]);
    expect(await resolver.pinsForUser('user-dave'), isEmpty);
  });

  test('wiping the device forgets every pin', () async {
    await resolver.evaluate('user-alice', 'dev-alice', _key(1));

    await storage.wipeLocalDeviceState();

    expect(await resolver.pinsForUser('user-alice'), isEmpty);
    expect(keystore.values.keys.where((key) => key.startsWith(SecureScope.identity.namespace)), isEmpty);
  });
}
