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

// The lock screen on a phone: unlocking needs no scrolling and the page
// holds nothing else. Choosing a PIN is a grouped page: the two fields, the
// one footer that says what the PIN is, then the button.

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
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // Whether the whole of [finder]'s widget is on screen.
  bool wholeOnScreen(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder.first);
    return visibleRect(tester, box).height == box.size.height;
  }

  testWidgets('a locked app shows the PIN field and both buttons without scrolling, and nothing else', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/lock',
      account: LayoutAccount.locked,
      body: (world) async {
        expect(tester.takeException(), isNull, reason: 'nothing overflows a 360x640 screen');
        expect(findCopy(l10n.appLockLockedTitle), findsOneWidget);

        expect(wholeOnScreen(tester, find.byType(TextField)), isTrue);
        expect(wholeOnScreen(tester, find.widgetWithText(FilledButton, l10n.appLockUnlock)), isTrue);
        expect(wholeOnScreen(tester, find.widgetWithText(TextButton, l10n.appLockUseBiometrics)), isTrue);

        // A white page with no bar title: no notice, no state words, and
        // the PIN rule is not said here (it is the set-up page's footer).
        expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);
        for (final gone in [l10n.appLockSetupFooter, l10n.appLockTitle]) {
          expect(findCopy(gone, skipOffstage: false), findsNothing, reason: gone);
        }
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('biometrics that fail are said under the PIN field, and the app stays locked', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/lock',
      account: LayoutAccount.locked,
      body: (world) async {
        // The layout world's biometrics always refuse.
        await tester.tap(find.widgetWithText(TextButton, l10n.appLockUseBiometrics));
        await pumpFrames(tester, frames: 3);

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.decoration?.errorText, l10n.appLockStatusBiometricFailed);
        expect(find.byType(VeilNotice, skipOffstage: false), findsNothing, reason: 'the field says it, not a box');
        expect(findCopy(l10n.appLockLockedTitle), findsOneWidget, reason: 'still locked');
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('choosing a PIN: the two fields in a group, the footer once, then "Turn on"', (tester) async {
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

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.appLockTitle), findsOneWidget, reason: 'the bar');
    expect(findCopy(l10n.appLockLockedTitle), findsNothing, reason: 'nothing is locked yet: a PIN is chosen');
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    expect(find.descendant(of: find.byType(VeilGroup), matching: fields), findsNWidgets(2));
    final footer = findCopy(l10n.appLockSetupFooter);
    expect(footer, findsOneWidget);
    expect(tester.getRect(fields.last).bottom, lessThan(tester.getTopLeft(footer).dy));
    final turnOn = find.widgetWithText(FilledButton, l10n.appLockTurnOn);
    expect(wholeOnScreen(tester, turnOn), isTrue);
    expect(tester.getRect(footer).bottom, lessThan(tester.getTopLeft(turnOn).dy));
    expect(tester.widget<FilledButton>(turnOn).onPressed, isNull, reason: 'no PIN yet');
    // Unlocking with biometrics stays offered while no PIN is set.
    expect(find.widgetWithText(TextButton, l10n.appLockUseBiometrics), findsOneWidget);

    // A PIN of the wrong shape and a confirmation that differs are said
    // under their fields; the button waits for both to be right.
    await tester.enterText(fields.first, '12');
    await tester.enterText(fields.last, '13');
    await tester.pump();
    expect(find.text(l10n.appLockFieldPinError), findsOneWidget);
    expect(find.text(l10n.appLockConfirmMismatch), findsOneWidget);
    // Each error keeps the row's padding under it: off the hairline under
    // the first row and off the group's bottom edge under the second.
    final rows = find.byType(VeilRow);
    expect(rows, findsNWidgets(2));
    expect(tester.getRect(rows.first).bottom - tester.getRect(find.text(l10n.appLockFieldPinError)).bottom,
        greaterThanOrEqualTo(8));
    expect(tester.getRect(rows.last).bottom - tester.getRect(find.text(l10n.appLockConfirmMismatch)).bottom,
        greaterThanOrEqualTo(8));
    expect(tester.widget<FilledButton>(turnOn).onPressed, isNull);
    await tester.enterText(fields.first, '123456');
    await tester.enterText(fields.last, '123456');
    await tester.pump();
    expect(tester.widget<FilledButton>(turnOn).onPressed, isNotNull);
    expect(find.byType(VeilNotice), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
