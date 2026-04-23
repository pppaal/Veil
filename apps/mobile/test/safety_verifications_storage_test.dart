import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';

// Exercises the composite-key layout for per-member Safety Number attestations.
// Direct conversations key off conversationId alone; group conversations
// key off "$conversationId:$memberUserId" — the two layouts must coexist in
// a single storage blob without collision.
void main() {
  SafetyVerificationRecord record(String pub) => SafetyVerificationRecord(
        peerIdentityPublicKey: pub,
        safetyNumber: '1' * 60,
        verifiedAt: DateTime.utc(2026, 4, 23),
      );

  group('safety verifications storage', () {
    test('direct read/write is keyed by conversationId alone', () async {
      final store = _InMemorySecureStore();
      final service = SecureStorageService(store);

      await service.writeSafetyVerification('conv-a', record('pub-a'));
      final got = await service.readSafetyVerification('conv-a');

      expect(got, isNotNull);
      expect(got!.peerIdentityPublicKey, 'pub-a');

      // A group-member read against the same conversationId must NOT hit
      // the direct record — composite keys live in a different namespace.
      final notFound = await service.readSafetyVerification(
        'conv-a',
        memberUserId: 'user-1',
      );
      expect(notFound, isNull);
    });

    test('group members share a conversationId without colliding', () async {
      final store = _InMemorySecureStore();
      final service = SecureStorageService(store);

      await service.writeSafetyVerification(
        'conv-g',
        record('pub-alice'),
        memberUserId: 'user-alice',
      );
      await service.writeSafetyVerification(
        'conv-g',
        record('pub-bob'),
        memberUserId: 'user-bob',
      );

      final alice = await service.readSafetyVerification(
        'conv-g',
        memberUserId: 'user-alice',
      );
      final bob = await service.readSafetyVerification(
        'conv-g',
        memberUserId: 'user-bob',
      );

      expect(alice?.peerIdentityPublicKey, 'pub-alice');
      expect(bob?.peerIdentityPublicKey, 'pub-bob');
    });

    test('readSafetyVerificationsForGroup returns only that group', () async {
      final store = _InMemorySecureStore();
      final service = SecureStorageService(store);

      await service.writeSafetyVerification(
        'conv-g',
        record('pub-alice'),
        memberUserId: 'user-alice',
      );
      await service.writeSafetyVerification(
        'conv-g',
        record('pub-bob'),
        memberUserId: 'user-bob',
      );
      // Direct verification under the SAME conversationId prefix must not
      // leak into the group member map.
      await service.writeSafetyVerification('conv-g', record('pub-direct'));
      // And a verification on a different conversation must not leak either.
      await service.writeSafetyVerification(
        'other',
        record('pub-other'),
        memberUserId: 'user-alice',
      );

      final forGroup =
          await service.readSafetyVerificationsForGroup('conv-g');

      expect(forGroup.keys, unorderedEquals(<String>['user-alice', 'user-bob']));
      expect(forGroup['user-alice']!.peerIdentityPublicKey, 'pub-alice');
      expect(forGroup['user-bob']!.peerIdentityPublicKey, 'pub-bob');
    });

    test('clearing a member does not touch the direct record', () async {
      final store = _InMemorySecureStore();
      final service = SecureStorageService(store);

      await service.writeSafetyVerification('conv-g', record('pub-direct'));
      await service.writeSafetyVerification(
        'conv-g',
        record('pub-alice'),
        memberUserId: 'user-alice',
      );

      await service.clearSafetyVerification(
        'conv-g',
        memberUserId: 'user-alice',
      );

      expect(
        await service.readSafetyVerification('conv-g', memberUserId: 'user-alice'),
        isNull,
      );
      final direct = await service.readSafetyVerification('conv-g');
      expect(direct?.peerIdentityPublicKey, 'pub-direct');
    });

    test('clearing the last entry deletes the storage blob entirely', () async {
      final store = _InMemorySecureStore();
      final service = SecureStorageService(store);

      await service.writeSafetyVerification(
        'conv-g',
        record('pub-alice'),
        memberUserId: 'user-alice',
      );
      expect(store.hasKey('veil.security.safety_verifications'), isTrue);

      await service.clearSafetyVerification(
        'conv-g',
        memberUserId: 'user-alice',
      );
      expect(store.hasKey('veil.security.safety_verifications'), isFalse);
    });
  });
}

class _InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String?> _values = <String, String?>{};

  bool hasKey(String key) => _values.containsKey(key);

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }
}
