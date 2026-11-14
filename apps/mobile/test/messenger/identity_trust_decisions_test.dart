import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/util/base64url.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';

/// A keystore whose reads or deletes can be held back, the way a platform
/// keystore answers late and does not order a read after a delete. A held
/// read answers with what was stored when it was asked.
class _SlowKeystore extends InMemoryIdentityKeyValueBackend {
  Completer<void>? reads;
  Completer<void>? deletes;

  @override
  Future<String?> read(String key) async {
    final value = await super.read(key);
    await reads?.future;
    return value;
  }

  @override
  Future<void> delete(String key) async {
    await deletes?.future;
    return super.delete(key);
  }
}

Future<void> _turns() => Future<void>.delayed(const Duration(milliseconds: 20));

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

  // Bob declined [forged], and a third key is pending in conv-1 after it.
  Future<void> declineAndHoldAnother(IdentityTrust trust) async {
    await trust.decline('conv-1', reviewed: await forgedChange(trust));
    expect(await trust.admit('conv-1', 'user-bob', 'dev-bob', key(3)), isFalse);
    expect(trust.pendingFor('conv-1')?.presentedKey, key(3));
  }

  Future<void> expectKept(IdentityTrust trust) async {
    expect(trust.pendingFor('conv-1')?.presentedKey, key(3), reason: 'the pending change was dropped');
    expect(await trust.admit('conv-1', 'user-bob', 'dev-bob', forged), isFalse);
    expect(trust.pendingFor('conv-1')?.presentedKey, key(3), reason: 'the declined key was raised again');
  }

  test('a sign-in forgets only what is in memory and reads the record back', () async {
    final trust = open();
    await declineAndHoldAnother(trust);

    trust.reset();
    expect(trust.pendingFor('conv-1'), isNull);
    await trust.ready;
    await expectKept(trust);
    trust.reset();
    await trust.ready;
    await expectKept(trust);
    final reopened = open()..reset();
    await reopened.ready;
    await expectKept(reopened);
  });

  test('a sign-in before the trust layer prepared still reads every decision back', () async {
    await declineAndHoldAnother(open());

    // As in the app: the pin migration waits for the database, which opens
    // only after the sign-in applied its session.
    final databaseOpened = Completer<void>();
    final trust = IdentityTrust(
      TrustedIdentityResolver(store: TrustedIdentityStore(keystore)),
      decisions: keystore,
      prepare: () => databaseOpened.future,
    );
    trust.reset();
    await _turns();
    databaseOpened.complete();
    await trust.ready;
    await expectKept(trust);
  });

  test('a decision made across a sign-in keeps the decisions stored', () async {
    final pins = _SlowKeystore();
    IdentityTrust openOverPins() =>
        IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(pins)), decisions: keystore);
    final trust = openOverPins();
    await trust.decline('conv-1', reviewed: await forgedChange(trust));
    expect(await trust.admit('conv-2', 'user-carol', 'dev-carol', key(5)), isTrue);

    // Carol's new key is being checked against her pin when the sign-in
    // resets the trust layer: the change it holds is made before the
    // record was read back, and must not be written over it.
    pins.reads = Completer<void>();
    final admitting = trust.admit('conv-2', 'user-carol', 'dev-carol', key(6));
    await _turns();
    trust.reset();
    pins.reads!.complete();
    pins.reads = null;
    expect(await admitting, isFalse);

    final reopened = openOverPins();
    await reopened.ready;
    expect(reopened.pendingFor('conv-2')?.presentedKey, key(6));
    expect(await reopened.admit('conv-1', 'user-bob', 'dev-bob', forged), isFalse);
    expect(reopened.pendingFor('conv-1'), isNull, reason: 'the decline was written over');
  });

  test('after sign-out nothing reads the record back before its delete landed', () async {
    final slow = _SlowKeystore();
    final trust = IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(keystore)), decisions: slow);
    await forgedChange(trust);

    slow.deletes = Completer<void>();
    final forgetting = trust.forgetDecisions();
    var prepared = false;
    final preparing = trust.ready.then((_) => prepared = true);
    await _turns();
    expect(prepared, isFalse, reason: 'the record was read while its delete was still pending');
    slow.deletes!.complete();
    await forgetting;
    await preparing;
    expect(trust.pendingFor('conv-1'), isNull);
    expect(await slow.read(IdentityTrust.decisionsKey), isNull);
  });

  test('a record still being read at sign-out is not applied after it', () async {
    await declineAndHoldAnother(open());
    final slow = _SlowKeystore()..reads = Completer<void>();
    await slow.write(IdentityTrust.decisionsKey, (await keystore.read(IdentityTrust.decisionsKey))!);
    final trust = IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(keystore)), decisions: slow);
    await _turns();

    final forgetting = trust.forgetDecisions();
    slow.reads!.complete();
    await forgetting;
    await trust.ready;
    await _turns();
    expect(trust.pendingFor('conv-1'), isNull, reason: 'the read from before the sign-out was applied');
    expect(await trust.admit('conv-1', 'user-bob', 'dev-bob', forged), isFalse);
    expect(trust.pendingFor('conv-1')?.presentedKey, forged, reason: 'the decline outlived the sign-out');
  });

  test('sign-out forgets kept decisions as well', () async {
    final trust = open();
    await forgedChange(trust);
    await trust.forgetDecisions();

    expect(await keystore.read(IdentityTrust.decisionsKey), isNull);
    final reopened = open();
    await reopened.ready;
    expect(reopened.pendingFor('conv-1'), isNull);
  });
}
