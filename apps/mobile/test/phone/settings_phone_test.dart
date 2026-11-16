import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/app/theme_mode_provider.dart';
import 'package:veil_mobile/src/core/crypto/crypto_adapter_registry.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/auth/presentation/choose_handle_screen.dart';
import 'package:veil_mobile/src/features/contacts/presentation/contacts_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/device_rows.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_danger_zone.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/trusted_devices_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// The settings tab on a phone, as Signal and WhatsApp lay theirs out: a
// grouped page of rows with their values, one line under a row only where
// it needs one, a footer of one line under Security, one Devices row, and
// the two account actions last, each behind the user's handle typed.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // The sections of the screen, top to bottom, as its list holds them.
  List<Widget> sections(WidgetTester tester) =>
      (tester.widget<ListView>(find.byType(ListView)).childrenDelegate as SliverChildListDelegate).children;

  // The headers of the groups, top to bottom, read while scrolling down.
  Future<List<String?>> groupHeaders(WidgetTester tester) async {
    final headers = <String?>[];
    final seen = <VeilGroup>{};
    void collect() {
      for (final group in tester.widgetList<VeilGroup>(find.byType(VeilGroup, skipOffstage: false))) {
        if (seen.add(group)) headers.add(group.header);
      }
    }

    collect();
    await scrollToEnd(tester, onPage: (_) async => collect());
    return headers;
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    await pumpFrames(tester, frames: 2);
  }

  // The one Devices row, which opens the list of devices.
  const devicesRow = ValueKey('settings-devices');
  const laptopRow = ValueKey('device-dev-laptop');

  VeilRow row(WidgetTester tester, String key) => tester.widget<VeilRow>(find.byKey(ValueKey(key), skipOffstage: false));

  testWidgets('leads with the account, appearance, privacy and security; devices follow; the account actions are last',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      // The profile row is the person, with no word beside it.
      expect(row(tester, 'settings-profile').value, isNull);
      expect(sections(tester).last, isA<SettingsDangerZone>());
      expect(find.byType(VeilShell), findsOneWidget);
      expect(tester.widget<VeilShell>(find.byType(VeilShell)).grouped, isTrue, reason: 'a grouped page');
      expect(await groupHeaders(tester), [
        null, // the account row
        en.settingsSectionAppearance,
        en.settingsSectionPrivacy,
        en.settingsSectionSecurity,
        en.settingsSectionDevices,
        en.settingsSectionAccount,
      ]);
    });
  });

  testWidgets('group headers are in sentence case, and no row repeats its group\'s header', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final headers = [for (final header in await groupHeaders(tester)) if (header != null) header];
      expect(headers, hasLength(5));
      for (final header in headers) {
        expect(header, isNot(header.toUpperCase()), reason: '"$header" is in capitals');
        expect(header[0], header[0].toUpperCase(), reason: '"$header" does not start with a capital');
        expect(header.substring(1), header.substring(1).toLowerCase(), reason: '"$header" is in title case');
      }
      expect(en.settingsDeviceTransferTitle, isNot(contains(en.settingsSectionDevices)));
    });
  });

  testWidgets('at 360x640 the theme and the first privacy switch are on the first screenful', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final theme = tester.getRect(find.byKey(const ValueKey('settings-theme')));
      final firstSwitch = tester.getRect(find.byType(Switch).first);
      final bar = tester.getRect(find.text(en.navSettings).last);
      expect(theme.bottom, lessThan(firstSwitch.top));
      expect(firstSwitch.bottom, lessThan(bar.top), reason: 'above the tab bar');
      expect(find.byType(SegmentedButton<ThemeMode>), findsNothing, reason: 'a row with its value, not a selector');

      // One line under read receipts, whole; none under typing indicators.
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(en.settingsReadReceiptsCaption), matching: find.byType(RichText)).first,
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final typing = tester.widget<VeilRow>(find.widgetWithText(VeilRow, en.settingsTypingIndicatorsTitle));
      expect(typing.subtitle, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the theme row opens the three themes with a check on the one in use; a privacy row switches from anywhere on it',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      String label(ThemeMode mode) =>
          {ThemeMode.light: en.themeModeLight, ThemeMode.dark: en.themeModeDark, ThemeMode.system: en.themeModeSystem}[mode]!;
      final before = world.container.read(themeModeProvider);
      expect(row(tester, 'settings-theme').value, label(before));

      await tester.tap(find.byKey(const ValueKey('settings-theme')));
      await pumpFrames(tester, frames: 4);
      for (final mode in ThemeMode.values) {
        final option = find.byKey(ValueKey('theme-mode-${mode.name}'));
        expect(option, findsOneWidget);
        expect(find.descendant(of: option, matching: find.byIcon(Icons.check)), mode == before ? findsOneWidget : findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
      await pumpFrames(tester, frames: 4);
      expect(world.container.read(themeModeProvider), ThemeMode.light);
      expect(row(tester, 'settings-theme').value, en.themeModeLight);

      final privacy = world.container.read(privacyPreferencesProvider);
      expect(privacy.sendReadReceipts, isTrue);
      // The row's title, not its switch.
      await tester.tap(find.text(en.settingsReadReceiptsTitle));
      await pumpFrames(tester, frames: 2);
      expect(privacy.sendReadReceipts, isFalse);
      await tester.tap(find.byType(Switch).first);
      await pumpFrames(tester, frames: 2);
      expect(privacy.sendReadReceipts, isTrue);
    });
  });

  testWidgets('the security group: the lock, what this phone does about screenshots, previews and notifications, one footer line',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final lock = find.byKey(const ValueKey('settings-app-lock'));
      await scrollTo(tester, lock);
      // The seeded phone has a PIN.
      expect(find.descendant(of: lock, matching: find.text(en.commonOn)), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-lock-now'), skipOffstage: false), findsOneWidget);
      // The seeded phone blocks screenshots and hides its preview; this
      // build has no push service.
      expect(row(tester, 'settings-screenshots').value, en.securityStatusBlocked);
      expect(row(tester, 'settings-app-preview').value, en.securityStatusAppPreviewProtected);
      expect(row(tester, 'settings-notifications').value, en.securityNotificationsWhileOpen);
      for (final key in ['settings-screenshots', 'settings-app-preview', 'settings-notifications']) {
        expect(row(tester, key).onTap, isNull, reason: '$key is a value, not a setting');
      }
      expect(find.byKey(const ValueKey('settings-security-details'), skipOffstage: false), findsNothing,
          reason: 'its screen is gone');

      final testBuild =
          cryptoAdapterKindOf(world.container.read(cryptoAdapterProvider).adapterId) == CryptoAdapterKind.development;
      final security = tester.widgetList<VeilGroup>(find.byType(VeilGroup, skipOffstage: false))
          .singleWhere((group) => group.header == en.settingsSectionSecurity);
      expect(security.footer, testBuild ? en.securityFooterTestBuild : en.securityFooterUnaudited);
    });
  });

  testWidgets('one Devices row with how many are listed opens the devices over the tab bar, in two sections',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final devices = find.byKey(devicesRow);
      await scrollTo(tester, devices);
      // This phone and the quiet laptop; the revoked iPhone is not counted.
      expect(row(tester, 'settings-devices').value, '2');
      expect(find.text('MacBook Air', skipOffstage: false), findsNothing, reason: 'no device listed inline');
      expect(find.byType(VeilNotice, skipOffstage: false), findsNothing, reason: 'no stale-device notice');

      await tester.tap(devices);
      await pumpFrames(tester, frames: 6);
      expect(find.byType(TrustedDevicesScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text(en.navChats), findsNothing, reason: 'the list covers the tab bar');
      expect(find.byIcon(Icons.refresh), findsNothing, reason: 'no refresh button: it refreshes on open and on a pull');

      final headers = [for (final group in tester.widgetList<VeilGroup>(find.byType(VeilGroup))) group.header];
      expect(headers, [en.settingsDeviceStateCurrent, en.settingsDevicesOtherHeader]);
      expect(find.byType(DeviceRow), findsNWidgets(2));
      final laptop = find.byKey(laptopRow);
      expect(find.descendant(of: laptop, matching: find.text('MacBook Air')), findsOneWidget);
      expect(find.descendant(of: laptop, matching: find.text(en.settingsDeviceInactiveSince('Apr 2'))), findsOneWidget);
      expect(find.text('Old iPhone'), findsNothing, reason: 'a removed device is not listed');
      for (final word in ['Stale', 'Revoked', 'Preferred']) {
        expect(find.text(word), findsNothing, reason: 'no state words');
      }

      await tester.tap(find.byType(VeilBackButton));
      await pumpFrames(tester, frames: 6);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(TrustedDevicesScreen), findsNothing);
    });
  });

  // The list was pushed past the router, which could then neither take it
  // down nor put it back: a location opened from elsewhere stayed hidden
  // under it, and an unlock returned to the settings tab instead.
  testWidgets('the devices list is a route: another location replaces it, and an unlock brings it back',
      (tester) async {
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
    try {
      // The app's own router: its guard, and the stack it keeps over a lock.
      final router = world.container.read(appRouterProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: world.container,
        child: MaterialApp.router(
          theme: VeilTheme.dark(),
          locale: const Locale('en'),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ));
      await pumpFrames(tester);
      router.go('/settings');
      await pumpFrames(tester);

      Future<void> openDevices() async {
        final row = find.byKey(devicesRow);
        await scrollTo(tester, row);
        await tester.tap(row);
        await pumpFrames(tester, frames: 6);
        expect(find.byType(TrustedDevicesScreen), findsOneWidget);
        expect(router.state.uri.path, '/trusted-devices');
      }

      await openDevices();
      final session = world.container.read(appSessionProvider.notifier);
      session.lock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(TrustedDevicesScreen), findsNothing, reason: 'nothing of the account shows behind the lock');

      session.unlock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(AppLockScreen), findsNothing);
      expect(find.byType(TrustedDevicesScreen), findsOneWidget, reason: 'back where the lock interrupted');
      await tester.tap(find.byType(VeilBackButton));
      await pumpFrames(tester, frames: 6);
      expect(find.byType(SettingsScreen), findsOneWidget, reason: 'with the settings tab under it');

      // A location opened from elsewhere (a link, the router's fallback).
      await openDevices();
      router.go('/contacts');
      await pumpFrames(tester, frames: 6);
      expect(find.byType(TrustedDevicesScreen), findsNothing, reason: 'the list does not stay on top of it');
      expect(find.byType(ContactsScreen), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });

  testWidgets('removing another device asks first, then it is no longer listed', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      await scrollTo(tester, find.byKey(devicesRow));
      await tester.tap(find.byKey(devicesRow));
      await pumpFrames(tester, frames: 6);

      // This phone is not tappable; the laptop asks to be removed.
      final current = tester.widget<DeviceRow>(find.byType(DeviceRow).first);
      expect(current.onTap, isNull);
      await tester.tap(find.byKey(laptopRow));
      await pumpFrames(tester, frames: 3);
      expect(findCopy(en.settingsRevokeListedTitle('MacBook Air')), findsOneWidget);
      expect(findCopy(en.settingsRevokeListedBody), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing, reason: 'no red fill: the confirming button is red text');
      expect(world.api.revokedDevices, isEmpty, reason: 'nothing is removed before the answer');

      await tester.tap(find.widgetWithText(TextButton, en.settingsDeviceRevokeAction));
      await pumpFrames(tester, frames: 6);
      expect(world.api.revokedDevices, ['dev-laptop']);
      expect(find.byKey(laptopRow), findsNothing);
      expect(find.text(en.settingsDevicesOtherHeader), findsNothing);
      expect(findCopy(en.settingsRevokeListedDone('MacBook Air')), findsOneWidget);
    });
  });

  group('the account actions', () {
    testWidgets('are the last group, two red rows that each open their own dialog', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        await scrollTo(tester, find.byKey(const ValueKey('settings-delete-account')));
        for (final key in ['settings-logout', 'settings-delete-account']) {
          final widget = row(tester, key);
          expect(widget.destructive, isTrue, reason: key);
          expect(widget.subtitle, isNull, reason: 'the dialog says what $key does, once');
        }
        for (final key in ['settings-wipe', 'settings-revoke']) {
          expect(find.byKey(ValueKey(key), skipOffstage: false), findsNothing, reason: 'folded into Sign out');
        }
        expect(findCopy(en.settingsDeleteAccountBody, skipOffstage: false), findsNothing);
      });
    });

    // Signing out erases this device's keys: there is no signing back in.
    testWidgets('signing out asks for the handle, and cancelling leaves the session as it was', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        final handle = '@${world.container.read(appSessionProvider).handle}';
        final logout = find.byKey(const ValueKey('settings-logout'));
        await scrollTo(tester, logout);
        await tester.tap(logout);
        await pumpFrames(tester, frames: 3);

        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue, reason: 'a tap alone signs nobody out');
        expect(findCopy(en.settingsLogoutConfirmTitle), findsOneWidget);
        expect(findCopy(en.settingsLogoutConfirmBody), findsOneWidget);
        expect(findCopy(en.settingsTypePhraseToContinue(handle)), findsOneWidget);
        TextButton confirm() => tester.widget(find.widgetWithText(TextButton, en.settingsLogout));
        expect(confirm().onPressed, isNull);

        await tester.tap(find.text(en.commonCancel));
        await pumpFrames(tester, frames: 3);
        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue);
        expect(world.api.revokedDevices, isEmpty);
        expect(find.byType(SettingsScreen), findsOneWidget);
      });
    });

    // Sign out is the server-confirmed revoke of this phone, then the erase
    // (AppSessionController.revokeCurrentDevice; the confirmed path is in
    // test/app/account_step_up_test.dart). This fake relay issues no
    // step-up challenge, as an unreachable server would not: nothing may be
    // erased, and a toast says so.
    testWidgets('signing out with the handle typed asks the server first; unconfirmed, nothing is erased and a toast says so',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        final session = world.container.read(appSessionProvider);
        final handle = session.handle!;
        final logout = find.byKey(const ValueKey('settings-logout'));
        await scrollTo(tester, logout);
        await tester.tap(logout);
        await pumpFrames(tester, frames: 3);

        TextButton confirm() => tester.widget(find.widgetWithText(TextButton, en.settingsLogout));
        await tester.enterText(find.byType(TextField), handle.substring(0, handle.length - 1));
        await tester.pump();
        expect(confirm().onPressed, isNull, reason: 'half the handle is not the handle');
        // Letter case and the "@" are not the point.
        await tester.enterText(find.byType(TextField), handle.toUpperCase());
        await tester.pump();
        expect(confirm().onPressed, isNotNull);

        await tester.tap(find.widgetWithText(TextButton, en.settingsLogout));
        await pumpFrames(tester, frames: 6);
        expect(world.api.revokedDevices, isEmpty);
        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue, reason: 'nothing was erased');
        expect(find.byType(ChooseHandleScreen), findsNothing);
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(findCopy(en.settingsLogoutFailed), findsOneWidget);
      });
    });

    testWidgets('deleting the account asks for the handle, and the dialog fits above the keyboard at 360x640',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', keyboardHeight: 300, body: (world) async {
        final handle = '@${world.container.read(appSessionProvider).handle}';
        final row = find.byKey(const ValueKey('settings-delete-account'));
        await scrollTo(tester, row);
        await tester.tap(row);
        await pumpFrames(tester, frames: 3);

        expect(findCopy(en.settingsDeleteAccountBody), findsOneWidget);
        expect(findCopy(en.settingsTypePhraseToContinue(handle)), findsOneWidget);
        final confirm = find.widgetWithText(TextButton, en.settingsDeleteAccountAction);
        expect(tester.widget<TextButton>(confirm).onPressed, isNull);
        expect(find.byType(FilledButton), findsNothing, reason: 'no red fill');
        await tester.enterText(find.byType(TextField), handle);
        await tester.pump();
        expect(tester.widget<TextButton>(confirm).onPressed, isNotNull);
        // The field and the button that confirms are above the keyboard.
        expect(tester.getRect(find.byType(TextField)).top, greaterThanOrEqualTo(24), reason: 'under the status bar');
        expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(640 - 300));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text(en.commonCancel));
        await pumpFrames(tester, frames: 3);
        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue);
      });
    });
  });
}
