import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/app/theme_mode_provider.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/auth/presentation/create_account_screen.dart';
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

// The settings tab on a phone: a grouped page with what is changed day to
// day first, the security of the account with its one footer, a row for
// each device of the account, and what cannot be undone last, each behind a
// typed phrase.

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

  // The quiet laptop's row: any device row opens the list of devices.
  const laptopRow = ValueKey('settings-device-dev-laptop');

  testWidgets('leads with the account, appearance, privacy and security; devices follow; what cannot be undone is last',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
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
      expect(en.settingsSecurityDetailsTitle, isNot(en.settingsSectionSecurity));
      expect(en.settingsDeviceTransferTitle, isNot(contains(en.settingsSectionDevices)));
    });
  });

  testWidgets('at 360x640 the theme and the first privacy switch are on the first screenful', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final theme = tester.getRect(find.byType(SegmentedButton<ThemeMode>));
      final firstSwitch = tester.getRect(find.byType(Switch).first);
      final bar = tester.getRect(find.text(en.navSettings).last);
      expect(theme.bottom, lessThan(firstSwitch.top));
      expect(firstSwitch.bottom, lessThan(bar.top), reason: 'above the tab bar');

      // Three words on one line each, inside the selector.
      for (final label in [en.themeModeLight, en.themeModeDark, en.themeModeSystem]) {
        final text = find.descendant(of: find.byType(SegmentedButton<ThemeMode>), matching: find.text(label));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        expect(paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.length)).map((box) => box.top).toSet(),
            hasLength(1), reason: '"$label" wraps');
        expect(paragraph.didExceedMaxLines, isFalse, reason: '"$label" is cut');
        expect(tester.getRect(text).right, lessThanOrEqualTo(theme.right));
      }
      // The privacy captions are whole: neither is cut with an ellipsis.
      for (final caption in [en.settingsReadReceiptsCaption, en.settingsTypingIndicatorsCaption]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(caption), matching: find.byType(RichText)).first,
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: '"$caption" is cut');
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the theme selector sets the theme, and a privacy row switches from anywhere on it', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      await tester.tap(find.text(en.themeModeLight));
      await pumpFrames(tester, frames: 2);
      expect(world.container.read(themeModeProvider), ThemeMode.light);

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

  testWidgets('the security group: the lock with its state, and the one footer on encryption and recovery',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final lock = find.byKey(const ValueKey('settings-app-lock'));
      await scrollTo(tester, lock);
      // The seeded phone has a PIN.
      expect(find.descendant(of: lock, matching: find.text(en.commonOn)), findsOneWidget);
      for (final key in ['settings-lock-now', 'settings-security-details', 'settings-one-time-link']) {
        expect(find.byKey(ValueKey(key), skipOffstage: false), findsOneWidget, reason: key);
      }
      final footer = '${en.securityFooterEncryption} ${en.securityFooterNoRecovery}';
      expect(find.text(footer, skipOffstage: false), findsOneWidget);
      final security = tester.widgetList<VeilGroup>(find.byType(VeilGroup, skipOffstage: false))
          .singleWhere((group) => group.header == en.settingsSectionSecurity);
      expect(security.footer, footer);
    });
  });

  testWidgets('a row for each device with its state, the one notice on the quiet one, the list over the tab bar',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final laptop = find.byKey(laptopRow);
      await scrollTo(tester, laptop);
      expect(find.byType(DeviceRow, skipOffstage: false), findsNWidgets(3));
      expect(find.descendant(of: laptop, matching: find.text('MacBook Air')), findsOneWidget);
      expect(find.descendant(of: laptop, matching: find.text(en.settingsDeviceStateStale)), findsOneWidget);
      expect(find.descendant(of: laptop, matching: find.text('Last seen Apr 2 (UTC)')), findsOneWidget);
      expect(find.text(en.settingsDeviceStateCurrent, skipOffstage: false), findsOneWidget);
      expect(find.text(en.settingsDeviceStateRevoked, skipOffstage: false), findsOneWidget);
      final stale = find.byKey(const ValueKey('settings-devices-stale'), skipOffstage: false);
      expect(find.descendant(of: stale, matching: find.text(en.settingsDevicesStaleNotice(1))), findsOneWidget);
      expect(find.descendant(of: stale, matching: find.text(en.settingsDevicesReview)), findsOneWidget);

      await tester.tap(laptop);
      await pumpFrames(tester, frames: 6);
      expect(find.byType(TrustedDevicesScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text(en.navChats), findsNothing, reason: 'the list covers the tab bar');
      expect(find.byType(DeviceDetailsGroup, skipOffstage: false), findsWidgets);
      expect(findCopy(en.settingsDeviceNoteStale, skipOffstage: false), findsOneWidget,
          reason: 'what the quiet one\'s state means is said under it');

      await tester.tap(find.byType(VeilBackButton));
      await pumpFrames(tester, frames: 6);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(TrustedDevicesScreen), findsNothing);

      // The notice's action opens the same list.
      await scrollTo(tester, find.text(en.settingsDevicesReview));
      await tester.tap(find.text(en.settingsDevicesReview));
      await pumpFrames(tester, frames: 6);
      expect(find.byType(TrustedDevicesScreen), findsOneWidget);
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
        final row = find.byKey(laptopRow);
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

  testWidgets('revoking a listed device asks first, then lists it as revoked', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      await scrollTo(tester, find.byKey(laptopRow));
      await tester.tap(find.byKey(laptopRow));
      await pumpFrames(tester, frames: 6);

      // Only the quiet laptop can be revoked from here: not this device,
      // and not the one already revoked.
      final revoke = find.widgetWithText(VeilRow, en.settingsDeviceRevokeAction, skipOffstage: false);
      expect(revoke, findsOneWidget);
      expect(tester.widget<VeilRow>(revoke).destructive, isTrue);
      await scrollTo(tester, revoke);
      await tester.tap(revoke);
      await pumpFrames(tester, frames: 3);
      expect(findCopy(en.settingsRevokeListedTitle('MacBook Air')), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing, reason: 'no red fill: the confirming button is red text');
      expect(world.api.revokedDevices, isEmpty, reason: 'nothing is revoked before the answer');

      await tester.tap(find.widgetWithText(TextButton, en.settingsRevokeConfirmAction));
      await pumpFrames(tester, frames: 6);
      expect(world.api.revokedDevices, ['dev-laptop']);
      expect(find.widgetWithText(VeilRow, en.settingsDeviceRevokeAction, skipOffstage: false), findsNothing);
      expect(findCopy(en.settingsDeviceNoteStale, skipOffstage: false), findsNothing);
      expect(
        find.descendant(
          of: find.byType(TrustedDevicesScreen),
          matching: find.text(en.settingsDeviceStateRevoked, skipOffstage: false),
        ),
        findsNWidgets(2),
      );
    });
  });

  group('what cannot be undone', () {
    testWidgets('is the last group, four red rows that each open their own dialog', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        await scrollTo(tester, find.byKey(const ValueKey('settings-delete-account')));
        final footer = '${en.securityFooterEncryption} ${en.securityFooterNoRecovery}';
        for (final key in ['settings-logout', 'settings-wipe', 'settings-revoke', 'settings-delete-account']) {
          final row = find.byKey(ValueKey(key), skipOffstage: false);
          expect(row, findsOneWidget);
          final widget = tester.widget<VeilRow>(row);
          expect(widget.destructive, isTrue, reason: key);
          expect(widget.subtitle, isNull, reason: 'the dialog says what $key does, once');
        }
        // The loss is said once on the screen, in the security footer.
        expect(findCopy(en.settingsDeleteAccountBody, skipOffstage: false), findsNothing);
        expect(find.text(footer, skipOffstage: false), findsOneWidget);
      });
    });

    // Logging out erases this device's keys: there is no logging back in.
    // It used to happen on one tap.
    testWidgets('logging out asks for its phrase, and cancelling leaves the session as it was', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        final logout = find.byKey(const ValueKey('settings-logout'));
        await scrollTo(tester, logout);
        await tester.tap(logout);
        await pumpFrames(tester, frames: 3);

        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue, reason: 'a tap alone logs nobody out');
        expect(findCopy(en.settingsLogoutConfirmTitle), findsOneWidget);
        expect(findCopy(en.settingsLogoutConfirmBody), findsOneWidget);
        expect(findCopy(en.settingsTypePhraseToContinue(en.settingsLogoutConfirmPhrase)), findsOneWidget);
        TextButton confirm() => tester.widget(find.widgetWithText(TextButton, en.settingsLogout));
        expect(confirm().onPressed, isNull);

        await tester.tap(find.text(en.commonCancel));
        await pumpFrames(tester, frames: 3);
        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue);
        expect(find.byType(SettingsScreen), findsOneWidget);
      });
    });

    testWidgets('logging out with the phrase typed signs this device out', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        final logout = find.byKey(const ValueKey('settings-logout'));
        await scrollTo(tester, logout);
        await tester.tap(logout);
        await pumpFrames(tester, frames: 3);

        TextButton confirm() => tester.widget(find.widgetWithText(TextButton, en.settingsLogout));
        await tester.enterText(find.byType(TextField), 'sign');
        await tester.pump();
        expect(confirm().onPressed, isNull, reason: 'half the phrase is not the phrase');
        // Letter case is not the point.
        await tester.enterText(find.byType(TextField), 'SIGN OUT');
        await tester.pump();
        expect(confirm().onPressed, isNotNull);

        await tester.tap(find.widgetWithText(TextButton, en.settingsLogout));
        await pumpFrames(tester, frames: 6);
        expect(world.container.read(appSessionProvider).isAuthenticated, isFalse);
        expect(find.byType(CreateAccountScreen), findsOneWidget);
      });
    });

    testWidgets('each action asks for its phrase, and the dialog fits above the keyboard at 360x640',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', keyboardHeight: 300, body: (world) async {
        for (final (key, phrase, action) in [
          ('settings-wipe', en.settingsWipeConfirmPhrase, en.settingsWipeConfirmAction),
          ('settings-revoke', en.settingsRevokeConfirmPhrase, en.settingsRevokeConfirmAction),
          ('settings-delete-account', en.settingsDeleteAccountConfirmPhrase, en.settingsDeleteAccountAction),
        ]) {
          final row = find.byKey(ValueKey(key));
          await scrollTo(tester, row);
          await tester.tap(row);
          await pumpFrames(tester, frames: 3);

          expect(findCopy(en.settingsTypePhraseToContinue(phrase)), findsOneWidget);
          final confirm = find.widgetWithText(TextButton, action);
          expect(tester.widget<TextButton>(confirm).onPressed, isNull);
          expect(find.byType(FilledButton), findsNothing, reason: 'no red fill');
          await tester.enterText(find.byType(TextField), phrase);
          await tester.pump();
          expect(tester.widget<TextButton>(confirm).onPressed, isNotNull);
          // The field and the button that confirms are above the keyboard.
          expect(tester.getRect(find.byType(TextField)).top, greaterThanOrEqualTo(24), reason: 'under the status bar');
          expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(640 - 300));
          expect(tester.takeException(), isNull);

          await tester.tap(find.text(en.commonCancel));
          await pumpFrames(tester, frames: 3);
        }
        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue);
      });
    });
  });
}
