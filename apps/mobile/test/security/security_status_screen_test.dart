import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_adapter_registry.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart' show LibCryptoAdapter;
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart' show MockCryptoAdapter;
import 'package:veil_mobile/src/core/notifications/remote_push_service.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';
import '../support/mock_relay_parties.dart';

class _SignedIn extends AppSessionController {
  _SignedIn(SecureStorageService storage, FakeRelay relay, CryptoAdapter adapter)
      : super(storage, relay.clientFor('atlas'), adapter) {
    state = mockPartySession('atlas');
  }
}

/// A push service that has a token: notifications reach a closed app.
class _ConnectedPush implements RemotePushService {
  @override
  Future<String?> fetchToken() async => 'token';

  @override
  Stream<String> get tokenRefresh => const Stream.empty();

  @override
  Stream<RemotePushHint> get onMessage => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

const _android = LocalSecuritySnapshot(
  hasDeviceSecretRefs: true,
  hasPin: true,
  biometricsAvailable: false,
  integrityCompromised: false,
  integrityReasons: [],
  screenCaptureProtectionSupported: true,
  screenCaptureProtectionEnabled: true,
  appPreviewProtectionEnabled: true,
);

const _iPhone = LocalSecuritySnapshot(
  hasDeviceSecretRefs: true,
  hasPin: true,
  biometricsAvailable: true,
  integrityCompromised: false,
  integrityReasons: [],
  screenCaptureProtectionSupported: false,
  screenCaptureProtectionEnabled: false,
  appPreviewProtectionEnabled: false,
);

// The Security section of Settings (the Security details screen is gone):
// what it says about this build's encryption, screenshots, the app
// switcher and notifications must come from the build and the phone.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  Future<void> pumpSettings(
    WidgetTester tester, {
    required CryptoAdapter adapter,
    LocalSecuritySnapshot local = _android,
    RemotePushService? push,
  }) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final relay = FakeRelay();
    seedMockParties(relay, 'conv-1', ['atlas', 'selene']);
    final storage = SecureStorageService(MemorySecureStore());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(relay.clientFor('atlas')),
        cryptoAdapterProvider.overrideWithValue(adapter),
        appSessionProvider.overrideWith((ref) => _SignedIn(storage, relay, adapter)),
        conversationCacheProvider.overrideWith((ref) async => null),
        localSecuritySnapshotProvider.overrideWith((ref) async => local),
        if (push != null) remotePushServiceProvider.overrideWithValue(push),
      ],
      child: MaterialApp(
        theme: VeilTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  VeilGroup security(WidgetTester tester) => tester
      .widgetList<VeilGroup>(find.byType(VeilGroup))
      .singleWhere((group) => group.header == en.settingsSectionSecurity);

  VeilRow row(WidgetTester tester, String key) => tester.widget<VeilRow>(find.byKey(ValueKey(key)));

  testWidgets('Veil\'s own ratchet: the footer says the encryption is not audited yet, and names no protocol',
      (tester) async {
    await pumpSettings(tester, adapter: LibCryptoAdapter());

    expect(security(tester).footer, en.securityFooterUnaudited);
    expect(find.text(en.securityFooterTestBuild), findsNothing);
    expect(find.textContaining('Ratchet'), findsNothing);
    expect(find.textContaining('X3DH'), findsNothing);
  });

  testWidgets('the libsignal bridge is not audited either, and is not called a test build', (tester) async {
    await pumpSettings(tester, adapter: createCryptoAdapterFor('libsignal'));

    expect(security(tester).footer, en.securityFooterUnaudited);
    expect(find.textContaining('libsignal'), findsNothing);
  });

  testWidgets('a development adapter says it is a test build, not production encryption', (tester) async {
    await pumpSettings(tester, adapter: MockCryptoAdapter());

    expect(security(tester).footer, en.securityFooterTestBuild);
    expect(find.text(en.securityFooterUnaudited), findsNothing);
  });

  testWidgets('without a push service, notifications come only while the app is open', (tester) async {
    await pumpSettings(tester, adapter: LibCryptoAdapter());

    final notifications = row(tester, 'settings-notifications');
    expect(notifications.title, en.securityStatusPushDelivery);
    expect(notifications.value, en.securityNotificationsWhileOpen);
    expect(notifications.onTap, isNull, reason: 'a value, not a setting');
  });

  testWidgets('with a push service, notifications are on', (tester) async {
    await pumpSettings(tester, adapter: LibCryptoAdapter(), push: _ConnectedPush());

    expect(row(tester, 'settings-notifications').value, en.securityStatusPushDeliveryOn);
  });

  testWidgets('where screenshots can be blocked they are, and the app switcher preview is hidden', (tester) async {
    await pumpSettings(tester, adapter: LibCryptoAdapter());

    final screenshots = row(tester, 'settings-screenshots');
    expect(screenshots.value, en.securityStatusBlocked);
    expect(screenshots.subtitle, isNull);
    expect(row(tester, 'settings-app-preview').value, en.securityStatusAppPreviewProtected);
  });

  testWidgets('on an iPhone screenshots are not blocked, and the row says the others are told', (tester) async {
    await pumpSettings(tester, adapter: LibCryptoAdapter(), local: _iPhone);

    final screenshots = row(tester, 'settings-screenshots');
    expect(screenshots.value, en.securityStatusScreenCaptureNotBlocked);
    expect(screenshots.subtitle, en.securityScreenshotsNotice);
    expect(row(tester, 'settings-app-preview').value, en.securityStatusAppPreviewPartial);
  });
}
