import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_adapter_registry.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart' show LibCryptoAdapter, kLibCryptoAdapterId;
import 'package:veil_mobile/src/core/crypto/libsignal_bridge_adapter.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/security_status/presentation/security_signal_rows.dart';
import 'package:veil_mobile/src/features/security_status/presentation/security_status_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';
import '../support/mock_relay_parties.dart';

class _SignedIn extends AppSessionController {
  _SignedIn(SecureStorageService storage, FakeRelay relay, CryptoAdapter adapter)
      : super(storage, relay.clientFor('atlas'), adapter) {
    state = mockPartySession('atlas');
  }
}

// The screen says it reflects this device and build, so what it shows for
// the crypto in use and the relay's TLS pins must come from them.
void main() {
  Future<void> pumpStatus(
    WidgetTester tester, {
    required CryptoAdapter adapter,
    String tlsPins = '',
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final relay = FakeRelay();
    seedMockParties(relay, 'conv-1', ['atlas', 'selene']);
    final storage = SecureStorageService(MemorySecureStore());
    final controller = mockPartyController(relay, 'atlas');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        messengerControllerProvider.overrideWith((ref) => controller),
        secureStorageProvider.overrideWithValue(storage),
        cryptoAdapterProvider.overrideWithValue(adapter),
        appSessionProvider.overrideWith((ref) => _SignedIn(storage, relay, adapter)),
        conversationCacheProvider.overrideWith((ref) async => null),
        localSecuritySnapshotProvider.overrideWith(
          (ref) async => const LocalSecuritySnapshot(
            hasDeviceSecretRefs: true,
            hasPin: true,
            biometricsAvailable: false,
            integrityCompromised: false,
            integrityReasons: [],
            screenCaptureProtectionSupported: true,
            screenCaptureProtectionEnabled: true,
            appPreviewProtectionEnabled: true,
          ),
        ),
      ],
      child: MaterialApp(
        theme: VeilTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SecurityStatusScreen(tlsPins: tlsPins),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('VEIL\'s own ratchet is named as such, with its adapter id', (tester) async {
    await pumpStatus(tester, adapter: LibCryptoAdapter());

    expect(find.text('Production (unaudited)'), findsWidgets);
    expect(find.textContaining(kLibCryptoAdapterId), findsOneWidget);
  });

  testWidgets('the libsignal bridge is not shown as VEIL\'s ratchet', (tester) async {
    await pumpStatus(tester, adapter: createCryptoAdapterFor('libsignal'));

    expect(find.text('libsignal bridge (unaudited)'), findsWidgets);
    expect(find.textContaining(kLibsignalAdapterId), findsOneWidget);
    expect(find.textContaining('AES-256-GCM'), findsNothing);
    expect(find.text('Production (unaudited)'), findsNothing);
  });

  testWidgets('a development adapter is flagged, not shown as production crypto', (tester) async {
    await pumpStatus(tester, adapter: createDefaultCryptoAdapter());

    expect(find.text('Development only'), findsWidgets);
    expect(find.text('Production (unaudited)'), findsNothing);
  });

  testWidgets('the TLS row warns when the build pins nothing', (tester) async {
    await pumpStatus(tester, adapter: LibCryptoAdapter());

    expect(find.text('Not pinned'), findsOneWidget);
    expect(find.text('Any certificate the phone trusts is accepted.'), findsOneWidget);
    expect(find.textContaining('VEIL'), findsNothing, reason: 'the build variable is not the user\'s business');
  });

  testWidgets('says that push notifications are not connected in a build without a push service', (tester) async {
    await pumpStatus(tester, adapter: LibCryptoAdapter());

    final l10n = lookupAppLocalizations(const Locale('en'));
    final row = find.ancestor(of: find.text(l10n.securityStatusPushDelivery), matching: find.byType(SecuritySignalRow));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(l10n.securityStatusPushDeliveryOff)), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(l10n.securityStatusPushDeliveryOffDetail)), findsOneWidget);
    final status = tester.widget<Text>(find.descendant(of: row, matching: find.text(l10n.securityStatusPushDeliveryOff)));
    expect(status.style?.color, VeilPalette.dark.warning, reason: 'a warning, not a fact in green');
  });

  testWidgets('the TLS row counts the pins the build has', (tester) async {
    await pumpStatus(tester, adapter: LibCryptoAdapter(), tlsPins: 'pin-one, pin-two');

    expect(find.text('Pinned'), findsOneWidget);
    expect(find.textContaining("pins the server's TLS keys (2)"), findsOneWidget);
  });
}
