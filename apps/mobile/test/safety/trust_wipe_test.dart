import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/safety/application/contact_trust.dart';
import 'package:veil_mobile/src/features/safety/application/verified_accounts.dart';
import 'package:veil_mobile/src/features/safety/data/contact_trust_store.dart';
import 'package:veil_mobile/src/features/safety/data/safety_providers.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';
import '../support/messenger_party.dart';
import 'trust_support.dart';

// The trust document belongs to the account signed in. A sign-out or an
// account deletion wipes the keystore first and reads signed out only once
// the cache is cleared too; nothing the trust layer writes in between may
// land, or the next account on the phone would start from it (its baseline
// done, so every chat it has would be a message request). The trust layer
// here is the app's own (unattachedContactTrustProvider) on the app's
// keystore, attached to a real messenger over the fake relay.

/// The app's session controller, signed in as alice; [readSignedOut] is
/// the last step of a sign-out, once the wipe and the cache clear are done.
class _Session extends AppSessionController {
  _Session(super.storage, super.api, super.adapter) {
    state = const AppSessionState(
      accessToken: 'token-alice',
      userId: 'user-alice',
      deviceId: 'dev-alice',
      handle: 'alice',
      onboardingAccepted: true,
      privacyConsentAccepted: true,
      locked: false,
      initializing: false,
    );
  }

  void readSignedOut() => state = const AppSessionState(onboardingAccepted: true, locked: true, initializing: false);
}

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;
  late SecureStorageService storage;
  late ProviderContainer container;
  late ContactTrust trust;

  setUp(() async {
    relay = trustRelay();
    alice = await phone(relay, 'alice');
    bob = await phone(relay, 'bob');
    relay.addDirect('conv-bob', 'alice', 'bob');
    storage = SecureStorageService(MemorySecureStore());
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(alice.api),
      appSessionProvider.overrideWith((ref) => _Session(storage, alice.api, createDefaultCryptoAdapter())),
      verifiedAccountsProvider.overrideWith((ref) => VerifiedAccounts(alice.trust)),
    ]);
    // The messenger follows the session, as messengerControllerProvider
    // makes it.
    container.listen<AppSessionState>(appSessionProvider, (_, next) => unawaited(alice.controller.applySession(next)));
    trust = container.read(unattachedContactTrustProvider);
    trust.attach(alice.controller, trustEvents: alice.trust.events);
    await alice.signIn();
    await bob.signIn();
    await waitFor(() => trust.ready, reason: 'the trust document was not read or the baseline did not run');
    await trust.flush();
  });

  tearDown(() async {
    container.dispose();
    await alice.dispose();
    await bob.dispose();
  });

  _Session session() => container.read(appSessionProvider.notifier) as _Session;
  Future<String?> stored() => storage.scoped(SecureScope.conversationPolicy).read(ContactTrustStore.documentKey);

  test('a trust write between the sign-out wipe and the signed-out state does not land', () async {
    expect(await stored(), isNotNull, reason: 'the baseline was not written');

    // The sign-out's first step: the keystore is wiped.
    await storage.wipeLocalDeviceState();
    expect(await stored(), isNull);

    // While the cache is cleared, the trust layer still runs: a banner is
    // recorded (written at once) and a stranger's chat gets listed (written
    // after the short delay).
    await trust.noteClaim('conv-bob');
    final carol = await phone(relay, 'carol');
    addTearDown(carol.dispose);
    relay.addDirect('conv-carol', 'carol', 'alice');
    await alice.controller.refreshConversations();
    await waitFor(() => alice.controller.conversationById('conv-carol') != null, reason: 'the chat was not listed');
    await trust.flush();
    expect(await stored(), isNull, reason: 'the account signing out wrote its trust document back');

    // The session reads signed out: still nothing, so the next account on
    // this phone starts with its own baseline.
    session().readSignedOut();
    await pumpEventQueue();
    expect(await stored(), isNull);
    final next = await ContactTrustStore(storage.scoped(SecureScope.conversationPolicy)).read();
    expect(next?.baseline ?? false, isFalse, reason: 'the next account would inherit the baseline');
  });

  test('a trust document written after the wipe by any path is deleted when the session reads signed out', () async {
    final document = (await stored())!;
    await storage.wipeLocalDeviceState();
    // Written behind the wipe's back, as a write that does not check the
    // count of wipes would be.
    await storage.scoped(SecureScope.conversationPolicy).write(ContactTrustStore.documentKey, document);
    expect(await stored(), isNotNull);

    session().readSignedOut();
    await pumpEventQueue();
    expect(await stored(), isNull, reason: 'the document outlived the sign-out');
  });
}
