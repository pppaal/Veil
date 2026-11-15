import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/security/app_lock_service.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/memory_secure_store.dart';
import '../support/copy_finder.dart';
import 'phone_app.dart';

// The lock screen on a phone: unlocking needs no scrolling, and the notice
// that nothing can be recovered is still there.

class _Biometrics implements LocalUnlockAuthenticator {
  const _Biometrics();

  @override
  Future<bool> authenticateBiometric() async => false;

  @override
  Future<bool> canUseBiometrics() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // The screen's own list; each text field scrolls too.
  final screenList = find.byType(Scrollable).first;

  // Whether the whole of [finder]'s widget is on screen.
  bool wholeOnScreen(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder.first);
    return visibleRect(tester, box).height == box.size.height;
  }

  testWidgets('a locked app shows the PIN field and both buttons without scrolling', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/lock',
      account: LayoutAccount.locked,
      body: (world) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(tester.takeException(), isNull, reason: 'nothing overflows a 360x640 screen');
        expect(find.byType(VeilHeroPanel), findsNothing);
        expect(find.byType(VeilMetricStrip), findsNothing);
        expect(findCopy(l10n.appLockHeroTitle), findsOneWidget);

        expect(wholeOnScreen(tester, find.byType(TextField)), isTrue);
        expect(wholeOnScreen(tester, find.text(l10n.appLockUnlock)), isTrue);
        expect(wholeOnScreen(tester, find.text(l10n.appLockUseBiometrics)), isTrue);

        // After the buttons: the notice and what the device offers. The
        // rules the words above already state are not repeated as pills.
        await tester.scrollUntilVisible(find.text(l10n.appLockPillBiometricsAvailable), 120, scrollable: screenList);
        expect(find.byType(VeilDestructiveNotice), findsOneWidget);
        expect(findCopy(l10n.appLockNoRecoveryBody), findsOneWidget);
        expect(find.text(l10n.appLockPillPinConfigured), findsOneWidget);
        expect(find.text(l10n.appLockPillBiometricsAvailable), findsOneWidget);
        for (final rule in [l10n.appLockPillLocalOnly, l10n.appLockPillNoRemoteReset]) {
          expect(find.text(rule, skipOffstage: false), findsNothing);
        }
        expect(find.byType(VeilStatusPill, skipOffstage: false), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('choosing a PIN shows that nothing can be recovered before the fields', (tester) async {
    usePhoneView(tester, phoneSmall);
    final storage = SecureStorageService(MemorySecureStore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockServiceProvider.overrideWithValue(AppLockService(const _Biometrics(), storage)),
        ],
        child: MaterialApp(
          theme: VeilTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppLockScreen(),
        ),
      ),
    );
    await pumpFrames(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.appLockFieldSetPin), findsOneWidget);
    final notice = tester.getTopLeft(find.byType(VeilDestructiveNotice)).dy;
    final firstField = tester.getTopLeft(find.byType(TextField).first).dy;
    expect(notice, lessThan(firstField));

    await tester.scrollUntilVisible(find.text(l10n.appLockSetAndUnlock), 120, scrollable: screenList);
    expect(find.text(l10n.appLockFieldConfirm), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
