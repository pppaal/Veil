import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/app/theme_mode_provider.dart';
import 'package:veil_mobile/src/core/crypto/crypto_adapter_registry.dart';
import 'package:veil_mobile/src/core/network/veil_api_exception.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/auth/presentation/choose_handle_screen.dart';
import 'package:veil_mobile/src/features/contacts/presentation/contacts_screen.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_danger_zone.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// The settings tab on a phone, as Signal and WhatsApp lay theirs out: a
// grouped page of rows with their values, one line under a row only where
// it needs one, a footer of one line under Security, and the account last:
// moving to a new phone, then the two account actions, each behind the
// user's handle typed. The account runs on one phone at a time, so there
// is no list of devices.

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

  // The row that opens Move to a new phone.
  const moveRow = ValueKey('settings-device-transfer');

  VeilRow row(WidgetTester tester, String key) => tester.widget<VeilRow>(find.byKey(ValueKey(key), skipOffstage: false));

  testWidgets('leads with the account, appearance, privacy and security; the account group is last',
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
        en.settingsSectionAccount,
      ]);
      // Nothing lists devices: the account runs on this phone alone.
      expect(find.byKey(const ValueKey('settings-devices'), skipOffstage: false), findsNothing);
      expect(find.text('Devices', skipOffstage: false), findsNothing);
    });
  });

  testWidgets('group headers are in sentence case, and no row repeats its group\'s header', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final headers = [for (final header in await groupHeaders(tester)) if (header != null) header];
      expect(headers, hasLength(4));
      for (final header in headers) {
        expect(header, isNot(header.toUpperCase()), reason: '"$header" is in capitals');
        expect(header[0], header[0].toUpperCase(), reason: '"$header" does not start with a capital');
        expect(header.substring(1), header.substring(1).toLowerCase(), reason: '"$header" is in title case');
      }
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

  testWidgets('Move to a new phone opens over the tab bar, and back returns to Settings', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final move = find.byKey(moveRow);
      await scrollTo(tester, move);
      expect(row(tester, 'settings-device-transfer').destructive, isFalse);
      expect(row(tester, 'settings-device-transfer').value, isNull);

      await tester.tap(move);
      await pumpFrames(tester, frames: 6);
      expect(find.byType(DeviceTransferScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text(en.navChats), findsNothing, reason: 'the screen covers the tab bar');

      await tester.tap(find.byType(VeilBackButton));
      await pumpFrames(tester, frames: 6);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(DeviceTransferScreen), findsNothing);
    });
  });

  // A screen pushed past the router could be neither taken down nor put
  // back: a location opened from elsewhere stayed hidden under it, and an
  // unlock returned to the settings tab instead.
  testWidgets('a screen a settings row opens is a route: another location replaces it, and an unlock brings it back',
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

      Future<void> openMove() async {
        final row = find.byKey(moveRow);
        await scrollTo(tester, row);
        await tester.tap(row);
        await pumpFrames(tester, frames: 6);
        expect(find.byType(DeviceTransferScreen), findsOneWidget);
        expect(router.state.uri.path, '/device-transfer');
      }

      await openMove();
      final session = world.container.read(appSessionProvider.notifier);
      session.lock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(DeviceTransferScreen), findsNothing, reason: 'nothing of the account shows behind the lock');

      session.unlock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(AppLockScreen), findsNothing);
      expect(find.byType(DeviceTransferScreen), findsOneWidget, reason: 'back where the lock interrupted');
      await tester.tap(find.byType(VeilBackButton));
      await pumpFrames(tester, frames: 6);
      expect(find.byType(SettingsScreen), findsOneWidget, reason: 'with the settings tab under it');

      // A location opened from elsewhere (a link, the router's fallback).
      await openMove();
      router.go('/contacts');
      await pumpFrames(tester, frames: 6);
      expect(find.byType(DeviceTransferScreen), findsNothing, reason: 'the screen does not stay on top of it');
      expect(find.byType(ContactsScreen), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });

  group('the account actions', () {
    testWidgets('close the last group, two red rows under Move to a new phone that each open their own dialog',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        await scrollTo(tester, find.byKey(const ValueKey('settings-delete-account')));
        final account = tester.widgetList<VeilGroup>(find.byType(VeilGroup, skipOffstage: false))
            .singleWhere((group) => group.header == en.settingsSectionAccount);
        expect([for (final child in account.children) (child.key as ValueKey<String>).value],
            ['settings-device-transfer', 'settings-logout', 'settings-delete-account']);
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
        expect(findCopy(en.settingsLogoutConfirmBody(world.container.read(appSessionProvider).handle!)), findsOneWidget);
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

    // The server answers that this phone is no longer on the account: the
    // phone is erased all the same (handleSecurityException), so Sign out
    // did what it said, and no "Couldn't sign out" follows it.
    testWidgets('signing out of a phone the server already dropped erases it and says no failure', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        world.api.challengeError = VeilApiException('Device is not active', statusCode: 401, code: 'device_not_active');
        final handle = world.container.read(appSessionProvider).handle!;
        final logout = find.byKey(const ValueKey('settings-logout'));
        await scrollTo(tester, logout);
        await tester.tap(logout);
        await pumpFrames(tester, frames: 3);
        await tester.enterText(find.byType(TextField), handle);
        await tester.pump();
        await tester.tap(find.widgetWithText(TextButton, en.settingsLogout));
        await pumpFrames(tester, frames: 8);

        expect(world.container.read(appSessionProvider).isAuthenticated, isFalse, reason: 'the phone was erased');
        expect(findCopy(en.settingsLogoutFailed, skipOffstage: false), findsNothing);
        expect(find.byType(SettingsScreen), findsNothing);
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
