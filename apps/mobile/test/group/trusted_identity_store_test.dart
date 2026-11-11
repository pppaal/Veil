import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/identity_verdict.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';

String _key(int fill) => base64Url.encode(List<int>.filled(32, fill)).replaceAll('=', '');

void main() {
  final firstSeen = DateTime.utc(2026, 11, 1, 9);
  late InMemoryIdentityKeyValueBackend backend;
  late DateTime now;
  late TrustedIdentityResolver resolver;

  TrustedIdentityResolver newResolver() =>
      TrustedIdentityResolver(store: TrustedIdentityStore(backend), clock: () => now);

  setUp(() {
    backend = InMemoryIdentityKeyValueBackend();
    now = firstSeen;
    resolver = newResolver();
  });

  test('pins on first use', () async {
    final verdict = await resolver.evaluate('alice', 'dev-a', _key(1));
    expect(verdict, isA<FirstUse>());
    expect(verdict.isTrusted, isTrue);

    final pin = await resolver.pinFor('alice', 'dev-a');
    expect(pin?.identityKey, _key(1));
    expect(pin?.firstSeenAt, firstSeen);
    expect(pin?.isVerified, isFalse);

    expect(await resolver.evaluate('alice', 'dev-a', _key(1)), isA<PinMatch>());
  });

  test('changed key is KeyChanged and not auto-accepted', () async {
    await resolver.evaluate('alice', 'dev-a', _key(1));

    for (var attempt = 0; attempt < 2; attempt++) {
      final verdict = await resolver.evaluate('alice', 'dev-a', _key(2));
      expect(verdict.isTrusted, isFalse);
      final changed = verdict as KeyChanged;
      expect(changed.pinned.identityKey, _key(1));
      expect(changed.presentedKey, _key(2));
    }
    expect((await resolver.pinFor('alice', 'dev-a'))?.identityKey, _key(1));
    expect(await resolver.evaluate('alice', 'dev-a', _key(1)), isA<PinMatch>());
  });

  test('a device id pinned under one user is refused under another', () async {
    await resolver.evaluate('alice', 'dev-a', _key(1));

    final verdict = await resolver.evaluate('mallory', 'dev-a', _key(9));
    expect(verdict.isTrusted, isFalse);
    expect((verdict as DeviceOfAnotherUser).pinned.userId, 'alice');
    expect(await resolver.pinsForUser('mallory'), isEmpty);
    expect(await resolver.evaluate('alice', 'dev-a', _key(1)), isA<PinMatch>());
  });

  test('verified contact change is KeyChangedVerified', () async {
    await resolver.evaluate('alice', 'dev-a', _key(1));
    now = firstSeen.add(const Duration(hours: 1));
    final verified = await resolver.markVerified('alice', 'dev-a', _key(1));
    expect(verified.verifiedAt, now);

    final verdict = await resolver.evaluate('alice', 'dev-a', _key(2));
    expect(verdict, isA<KeyChangedVerified>());
    expect(verdict.isTrusted, isFalse);
    expect((verdict as KeyChangedVerified).pinned.identityKey, _key(1));

    // Verifying the new key is not a way to approve it.
    expect(resolver.markVerified('alice', 'dev-a', _key(2)), throwsStateError);
    expect(resolver.markVerified('alice', 'dev-unknown', _key(2)), throwsStateError);
  });

  test('new device for known user flagged', () async {
    await resolver.evaluate('alice', 'dev-a', _key(1));

    final unverified = await resolver.evaluate('alice', 'dev-b', _key(2));
    expect(unverified.isTrusted, isFalse);
    expect((unverified as NewDeviceForKnownUser).knownUserVerified, isFalse);
    expect(await resolver.pinFor('alice', 'dev-b'), isNull);

    await resolver.markVerified('alice', 'dev-a', _key(1));
    final verified = await resolver.evaluate('alice', 'dev-b', _key(2));
    expect((verified as NewDeviceForKnownUser).knownUserVerified, isTrue);

    // Another user's devices do not make this one "known".
    expect(await resolver.evaluate('bob', 'dev-c', _key(3)), isA<FirstUse>());
  });

  test('approve replaces pin', () async {
    await resolver.evaluate('alice', 'dev-a', _key(1));
    await resolver.markVerified('alice', 'dev-a', _key(1));

    now = firstSeen.add(const Duration(days: 1));
    final approved = await resolver.approve('alice', 'dev-a', _key(2));
    expect(approved.identityKey, _key(2));
    expect(approved.verifiedAt, isNull);
    expect(approved.approvedAt, now);
    expect(approved.firstSeenAt, now);

    expect(await resolver.evaluate('alice', 'dev-a', _key(2)), isA<PinMatch>());
    // The old key is now just a change against an unverified pin.
    expect(await resolver.evaluate('alice', 'dev-a', _key(1)), isA<KeyChanged>());

    await resolver.approve('alice', 'dev-b', _key(3));
    expect(await resolver.evaluate('alice', 'dev-b', _key(3)), isA<PinMatch>());
    expect(await resolver.pinsForUser('alice'), hasLength(2));
  });

  test('persists across resolver instances', () async {
    await resolver.evaluate('alice', 'dev-a', _key(1));
    await resolver.markVerified('alice', 'dev-a', _key(1));
    await resolver.evaluate('bob', 'dev-b', _key(2));

    final reopened = newResolver();
    final pin = await reopened.pinFor('alice', 'dev-a');
    expect(pin?.identityKey, _key(1));
    expect(pin?.firstSeenAt, firstSeen);
    expect(pin?.verifiedAt, firstSeen);
    expect(await reopened.evaluate('alice', 'dev-a', _key(9)), isA<KeyChangedVerified>());
    expect(await reopened.evaluate('bob', 'dev-b', _key(2)), isA<PinMatch>());

    final stored = json.decode((await backend.read(TrustedIdentityStore.storageKey))!) as Map<String, dynamic>;
    expect(TrustedIdentityStore.storageKey, 'pins.v1');
    expect(stored['v'], 1);
    expect(stored['pins'], hasLength(2));
  });

  test('an unreadable pin table fails closed instead of reading as empty', () async {
    await backend.write(TrustedIdentityStore.storageKey, json.encode({'v': 99, 'pins': []}));
    expect(resolver.evaluate('alice', 'dev-a', _key(1)), throwsFormatException);

    await backend.write(TrustedIdentityStore.storageKey, '{not json');
    expect(resolver.evaluate('alice', 'dev-a', _key(1)), throwsFormatException);

    await TrustedIdentityStore(backend).clear();
    expect(await resolver.evaluate('alice', 'dev-a', _key(1)), isA<FirstUse>());
  });

  test('concurrent first sightings pin exactly one device', () async {
    final verdicts = await Future.wait([
      resolver.evaluate('alice', 'dev-a', _key(1)),
      resolver.evaluate('alice', 'dev-b', _key(2)),
    ]);
    expect(verdicts[0], isA<FirstUse>());
    expect(verdicts[1], isA<NewDeviceForKnownUser>());
    expect(await resolver.pinsForUser('alice'), hasLength(1));
  });

  test('verifying a contact holds every device of theirs pinned before and never compared', () async {
    await resolver.evaluate('alice', 'dev-a', _key(1));
    await resolver.evaluate('alice', 'dev-b', _key(2), admitNewDeviceOfUnverifiedUser: true);
    expect(await resolver.evaluate('alice', 'dev-b', _key(2)), isA<PinMatch>());

    await resolver.markVerified('alice', 'dev-a', _key(1));

    final held = await resolver.evaluate('alice', 'dev-b', _key(2), admitNewDeviceOfUnverifiedUser: true);
    expect((held as NewDeviceForKnownUser).knownUserVerified, isTrue);
    expect(held.isTrusted, isFalse);
    // A new key for it takes a re-verification, like any key of a verified
    // contact; the verified device itself still matches.
    expect(await resolver.evaluate('alice', 'dev-b', _key(3)), isA<KeyChangedVerified>());
    expect(await resolver.evaluate('alice', 'dev-a', _key(1)), isA<PinMatch>());

    // Once the user verified it too, it is trusted again.
    await resolver.markVerified('alice', 'dev-b', _key(2));
    expect(await resolver.evaluate('alice', 'dev-b', _key(2)), isA<PinMatch>());
  });

  test('a new device is admitted only when asked, and only for an unverified user', () async {
    await resolver.evaluate('alice', 'dev-a', _key(1));
    expect(await resolver.evaluate('alice', 'dev-b', _key(2)), isA<NewDeviceForKnownUser>());
    expect(await resolver.pinFor('alice', 'dev-b'), isNull);

    final admitted = await resolver.evaluate('alice', 'dev-b', _key(2), admitNewDeviceOfUnverifiedUser: true);
    expect((admitted as NewDeviceForKnownUser).admitted!.approvedAt, isNotNull);
    expect(await resolver.evaluate('alice', 'dev-b', _key(2)), isA<PinMatch>());

    await resolver.markVerified('alice', 'dev-a', _key(1));
    final held = await resolver.evaluate('alice', 'dev-c', _key(3), admitNewDeviceOfUnverifiedUser: true);
    expect((held as NewDeviceForKnownUser).admitted, isNull);
    expect(held.knownUserVerified, isTrue);
    expect(await resolver.pinFor('alice', 'dev-c'), isNull);
  });

  test('key encodings that differ only in padding are the same key', () async {
    await resolver.evaluate('alice', 'dev-a', _key(1));
    final padded = base64Url.encode(List<int>.filled(32, 1));
    expect(padded, endsWith('='));
    expect(await resolver.evaluate('alice', 'dev-a', padded), isA<PinMatch>());
  });

  test('rejects empty addresses and undecodable keys', () async {
    expect(resolver.evaluate('', 'dev-a', _key(1)), throwsArgumentError);
    expect(resolver.evaluate('alice', 'dev-a', '***'), throwsArgumentError);
    expect(resolver.evaluate('alice', 'dev-a', ''), throwsArgumentError);
  });
}
