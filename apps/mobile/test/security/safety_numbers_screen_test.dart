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

void main() {
  testWidgets('directory key differing from pin shows warning', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late IdentityTrust trust;
    late SecureStorageService storage;
    late LibCryptoAdapter adapter;
    late FakeRelay relay;
    await tester.runAsync(() async {
      adapter = LibCryptoAdapter();
      relay = FakeRelay();
      seedMockParties(relay, conv, ['atlas', 'selene']);
      // Real identities: safety numbers take 32-byte keys.
      final local = await adapter.identity.generateDeviceIdentity('dev-atlas');
      final pinned = await LibCryptoAdapter().identity.generateDeviceIdentity('dev-selene');
      final served = await LibCryptoAdapter().identity.generateDeviceIdentity('dev-selene');
      storage = SecureStorageService(MemorySecureStore());
      await storage.persistDeviceSecretRefs(
        identityPrivateRef: local.identityPrivateKeyRef,
        authPrivateKey: 'auth',
        authPublicKey: 'auth-pub',
      );
      trust = IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend())));
      await trust.resolver.evaluate('user-selene', 'dev-selene', pinned.identityPublicKey);
      relay.bundleOverrides['selene'] = {
        ...relay.partiesByHandle['selene']!.bundleJson,
        'identityPublicKey': served.identityPublicKey,
      };
    });
    // Disposed by the provider that owns it.
    final controller = mockPartyController(relay, 'atlas', identityTrust: trust);
    await tester.runAsync(() => controller.applySession(mockPartySession('atlas')));

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
    // The number is derived on a background isolate.
    for (var i = 0; i < 100 && find.text('SAFETY NUMBER').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(find.text('The key server lists a different key'), findsOneWidget);
    expect(find.text('SAFETY NUMBER'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
  });
}
