import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/util/base64url.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';

// Pending and declined identity changes are kept beside the pins, so a
// restart neither drops a change nor forgets a decline (C-DECLINE).
void main() {
  String key(int seed) => base64UrlNoPadEncode(List<int>.generate(32, (i) => (seed + i) % 256));
  final original = key(1);
  final forged = key(2);

  late InMemoryIdentityKeyValueBackend keystore;
  IdentityTrust open() => IdentityTrust(
        TrustedIdentityResolver(store: TrustedIdentityStore(keystore)),
        decisions: keystore,
      );

  setUp(() => keystore = InMemoryIdentityKeyValueBackend());

  Future<PendingIdentityChange> forgedChange(IdentityTrust trust) async {
    expect(await trust.admit('conv-1', 'user-bob', 'dev-bob', original), isTrue);
    expect(await trust.admit('conv-1', 'user-bob', 'dev-bob', forged), isFalse);
    return trust.pendingFor('conv-1')!;
  }

  test('a decline is kept across restarts until the same key is accepted', () async {
    final first = open();
    await first.decline('conv-1', reviewed: await forgedChange(first));

    final second = open();
    expect(await second.admit('conv-2', 'user-bob', 'dev-bob', forged), isFalse);
    expect(second.pendingFor('conv-2'), isNull, reason: 'declined keys are not asked about again');
    await expectLater(second.require('conv-2', 'user-bob', 'dev-bob', forged), throwsStateError);
  });

  test('verifying the declined key lifts the decline', () async {
    final trust = open();
    final change = await forgedChange(trust);
    await trust.decline('conv-1', reviewed: change);
    // bob did reinstall after all: the key is pinned and compared in person.
    await trust.resolver.approve('user-bob', 'dev-bob', forged);
    await trust.markVerified('user-bob', 'dev-bob', forged);
    // A later key replaces it, and then the verified one comes back.
    await trust.resolver.approve('user-bob', 'dev-bob', key(3));

    final reopened = open();
    expect(await reopened.admit('conv-1', 'user-bob', 'dev-bob', forged), isFalse);
    expect(reopened.pendingFor('conv-1')?.presentedKey, forged, reason: 'it is asked about again');
  });

  test('an unreadable record is dropped instead of holding decisions back', () async {
    await keystore.write(IdentityTrust.decisionsKey, '{"pending": "not a list"}');

    final trust = open();
    expect(await trust.admit('conv-1', 'user-bob', 'dev-bob', original), isTrue);
    expect(trust.pendingFor('conv-1'), isNull);
  });

  test('sign-out forgets kept decisions as well', () async {
    final trust = open();
    await forgedChange(trust);
    await trust.clearPending();

    expect(await keystore.read(IdentityTrust.decisionsKey), isNull);
    final reopened = open();
    await reopened.ready;
    expect(reopened.pendingFor('conv-1'), isNull);
  });
}
