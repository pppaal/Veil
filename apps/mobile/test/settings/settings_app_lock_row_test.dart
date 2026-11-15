import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../phone/phone_app.dart';

// The App lock row of Settings says whether the lock is on: whether this
// phone has a PIN, as the keystore answers, and again after the lock
// screen it opens was left (a PIN may have been set there).

LocalSecuritySnapshot _snapshot({required bool hasPin}) => LocalSecuritySnapshot(
      hasDeviceSecretRefs: true,
      hasPin: hasPin,
      biometricsAvailable: false,
      integrityCompromised: false,
      integrityReasons: const [],
      screenCaptureProtectionSupported: true,
      screenCaptureProtectionEnabled: true,
      appPreviewProtectionEnabled: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  testWidgets('says Off without a PIN and On once the keystore has one, with nothing before it answers',
      (tester) async {
    usePhoneView(tester, phoneLarge);
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
    var hasPin = false;
    var asked = 0;
    final container = ProviderContainer(
      parent: world.container,
      overrides: [
        localSecuritySnapshotProvider.overrideWith((ref) async {
          asked++;
          return _snapshot(hasPin: hasPin);
        }),
      ],
    );
    final router = GoRouter(initialLocation: '/settings', routes: container.read(appRoutesProvider));
    try {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: VeilTheme.dark(fontFamily: layoutFontFamily),
          locale: const Locale('en'),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ));
      final row = find.byKey(const ValueKey('settings-app-lock'));
      // Before the keystore answers the row says neither.
      expect(find.descendant(of: row, matching: find.text(en.commonOn)), findsNothing);
      expect(find.descendant(of: row, matching: find.text(en.commonOff)), findsNothing);

      // The fake server answers the device list after a moment as well.
      await pumpFrames(tester);
      expect(find.descendant(of: row, matching: find.text(en.commonOff)), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(en.commonOn)), findsNothing);

      // A PIN is set on the lock screen the row opens; back on Settings the
      // row asks the keystore again.
      final before = asked;
      await tester.tap(row);
      await pumpFrames(tester, frames: 6);
      hasPin = true;
      router.pop();
      await pumpFrames(tester);
      expect(asked, greaterThan(before), reason: 'asked again after the lock screen');
      expect(find.descendant(of: row, matching: find.text(en.commonOn)), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(en.commonOff)), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      // Riverpod schedules the disposal of what the screen watched.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      router.dispose();
      container.dispose();
      world.dispose();
    }
  });
}
