import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';
import '../support/mock_relay_parties.dart';

const conv = 'conv-1';

/// A signed-in atlas, as the screen reads the session.
class _SignedIn extends AppSessionController {
  _SignedIn(SecureStorageService storage, FakeRelay relay, CryptoAdapter adapter)
      : super(storage, relay.clientFor('atlas'), adapter) {
    state = mockPartySession('atlas');
  }
}

/// Atlas looking at selene's safety number. Selene's device is pinned under
/// one real identity key while the directory serves another.
class _Fixture {
  late final IdentityTrust trust;
  late final SecureStorageService storage;
  late final LibCryptoAdapter adapter;
  late final FakeRelay relay;
  late final String pinnedKey;
  late final String servedKey;
  late final VeilMessengerController controller;

  Future<void> setUp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      adapter = LibCryptoAdapter();
      relay = FakeRelay();
      seedMockParties(relay, conv, ['atlas', 'selene']);
      // Real identities: safety numbers take 32-byte keys.
      final local = await adapter.identity.generateDeviceIdentity('dev-atlas');
      pinnedKey = (await LibCryptoAdapter().identity.generateDeviceIdentity('dev-selene')).identityPublicKey;
      servedKey = (await LibCryptoAdapter().identity.generateDeviceIdentity('dev-selene')).identityPublicKey;
      storage = SecureStorageService(MemorySecureStore());
      await storage.persistDeviceSecretRefs(
        identityPrivateRef: local.identityPrivateKeyRef,
        authPrivateKey: 'auth',
        authPublicKey: 'auth-pub',
      );
      trust = IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend())));
      await trust.resolver.evaluate('user-selene', 'dev-selene', pinnedKey);
      relay.bundleOverrides['selene'] = {
        ...relay.partiesByHandle['selene']!.bundleJson,
        'identityPublicKey': servedKey,
      };
    });
    // Disposed by the provider that owns it.
    controller = mockPartyController(relay, 'atlas', identityTrust: trust);
    await tester.runAsync(() => controller.applySession(mockPartySession('atlas')));
  }

  Future<void> pumpScreen(WidgetTester tester, {required Finder until}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        messengerControllerProvider.overrideWith((ref) => controller),
        identityTrustProvider.overrideWithValue(trust),
        secureStorageProvider.overrideWithValue(storage),
        cryptoAdapterProvider.overrideWithValue(adapter),
        appSessionProvider.overrideWith((ref) => _SignedIn(storage, relay, adapter)),
      ],
      child: MaterialApp(
        theme: VeilTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SafetyNumbersScreen(conversationId: conv),
      ),
    ));
    await settleUntil(tester, () => until.evaluate().isNotEmpty);
  }

  // Safety numbers are derived on a background isolate and approvals touch
  // the keystore, so let real time pass between frames.
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }
}

void main() {
  testWidgets('directory key differing from pin shows warning', (tester) async {
    final fixture = _Fixture();
    await fixture.setUp(tester);

    await fixture.pumpScreen(tester, until: find.text('SAFETY NUMBER'));

    expect(find.text('The key server lists a different key'), findsOneWidget);
    expect(find.text('SAFETY NUMBER'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
  });

  testWidgets('verified contact key change is never accepted with one tap', (tester) async {
    final fixture = _Fixture();
    await fixture.setUp(tester);
    final resolver = fixture.trust.resolver;
    await tester.runAsync(() async {
      await resolver.markVerified('user-selene', 'dev-selene', fixture.pinnedKey);
      expect(await fixture.trust.admit(conv, 'user-selene', 'dev-selene', fixture.servedKey), isFalse);
    });
    expect(fixture.controller.pendingIdentityChangeFor(conv)!.requiresReverification, isTrue);

    final reverify = find.text('Re-verify with new key');
    await fixture.pumpScreen(tester, until: reverify);
    expect(find.text('Accept the new key'), findsNothing);

    // The tap only opens the comparison; nothing is accepted yet.
    await tester.tap(reverify);
    await tester.pumpAndSettle();
    expect(find.text('Compare the new safety number'), findsOneWidget);
    final accept = find.widgetWithText(TextButton, 'Accept as verified');
    expect(tester.widget<TextButton>(accept).onPressed, isNull);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(fixture.controller.pendingIdentityChangeFor(conv), isNotNull);

    // Cancelling keeps the old verified pin and the block.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Compare the new safety number'), findsNothing);
    final kept = (await tester.runAsync(() => resolver.pinFor('user-selene', 'dev-selene')))!;
    expect(kept.identityKey, fixture.pinnedKey);
    expect(kept.isVerified, isTrue);
    expect(fixture.controller.pendingIdentityChangeFor(conv), isNotNull);

    // Only an explicit affirmation of the comparison accepts the new key.
    await tester.tap(reverify);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(accept);
    await tester.pump();
    await fixture.settleUntil(tester, () => fixture.controller.pendingIdentityChangeFor(conv) == null);

    final accepted = (await tester.runAsync(() => resolver.pinFor('user-selene', 'dev-selene')))!;
    expect(accepted.identityKey, fixture.servedKey);
    expect(accepted.isVerified, isTrue);
  });

  testWidgets('an unverified contact key change is accepted unverified', (tester) async {
    final fixture = _Fixture();
    await fixture.setUp(tester);
    await tester.runAsync(() => fixture.trust.admit(conv, 'user-selene', 'dev-selene', fixture.servedKey));

    final acceptNewKey = find.text('Accept the new key');
    await fixture.pumpScreen(tester, until: acceptNewKey);
    expect(find.text('Re-verify with new key'), findsNothing);

    await tester.tap(acceptNewKey);
    await tester.pump();
    await fixture.settleUntil(tester, () => fixture.controller.pendingIdentityChangeFor(conv) == null);

    final accepted = (await tester.runAsync(() => fixture.trust.resolver.pinFor('user-selene', 'dev-selene')))!;
    expect(accepted.identityKey, fixture.servedKey);
    expect(accepted.isVerified, isFalse);
  });
}
