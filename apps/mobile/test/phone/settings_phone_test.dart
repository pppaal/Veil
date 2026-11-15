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
import 'package:veil_mobile/src/features/settings/presentation/settings_danger_zone.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/trusted_device_card.dart';
import 'package:veil_mobile/src/features/settings/presentation/trusted_devices_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_grouped.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// The settings tab on a phone: grouped rows with what is changed day to day
// first, the devices of the account behind a row of their own, and what
// cannot be undone last, each behind a typed phrase.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));
  final ko = lookupAppLocalizations(const Locale('ko'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // The sections of the screen, top to bottom, as its list holds them.
  List<Widget> sections(WidgetTester tester) =>
      (tester.widget<ListView>(find.byType(ListView)).childrenDelegate as SliverChildListDelegate).children;

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    await pumpFrames(tester, frames: 2);
  }

  testWidgets('leads with appearance, privacy and the lock; devices follow; what cannot be undone is last',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final groups = sections(tester);
      expect([for (final group in groups.whereType<VeilGroup>()) group.label], [
        null, // the account row
        en.settingsSectionAppearance,
        en.settingsSectionPrivacy,
        en.settingsSectionSecurity,
        en.settingsSectionDevices,
        en.settingsSectionTools,
      ]);
      // Once, and after everything else.
      expect(groups.whereType<SettingsDangerZone>(), hasLength(1));
      expect(groups.last, isA<SettingsDangerZone>());

      // No hero, no pills and no device card ahead of the settings.
      expect(find.byType(VeilHeroPanel), findsNothing);
      expect(find.byType(TrustedDeviceCard), findsNothing);
      expect(find.text('Pixel 9 Pro Fold'), findsNothing);
    });
  });

  testWidgets('section labels are in one casing', (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final labels = [
        for (final group in sections(tester).whereType<VeilGroup>())
          if (group.label case final label?) label,
        en.settingsSectionIrreversible,
      ];
      expect(labels, hasLength(6));
      for (final label in labels) {
        expect(label, label.toUpperCase(), reason: '"$label" is not in capitals like the others');
      }
    });
  });

  // The label style is tracked for capitals. The same tracking pulled the
  // syllables of a Korean label apart ("화 면", "보 안").
  testWidgets('a Korean section label is set without the tracking of an English one', (tester) async {
    double? tracking(String label) => tester.widget<Text>(find.text(label)).style!.letterSpacing;

    await withPhoneApp(tester, identities, location: '/settings', locale: 'ko', body: (world) async {
      for (final label in [ko.settingsSectionAppearance, ko.settingsSectionPrivacy]) {
        expect(tracking(label), 0, reason: '"$label" is pulled apart');
      }
    });
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final label = Theme.of(tester.element(find.byType(SettingsScreen))).textTheme.labelLarge!;
      expect(label.letterSpacing, greaterThan(1));
      expect(tracking(en.settingsSectionAppearance), label.letterSpacing);
    });
  });

  for (final (locale, l10n) in [('en', en), ('ko', ko)]) {
    testWidgets('at 360x640 the theme and the first privacy switch are on the first screenful ($locale)',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', locale: locale, body: (world) async {
        final theme = tester.getRect(find.byType(SegmentedButton<ThemeMode>));
        final firstSwitch = tester.getRect(find.byType(Switch).first);
        final bar = tester.getRect(find.text(l10n.navSettings).last);
        expect(theme.bottom, lessThan(firstSwitch.top));
        expect(firstSwitch.bottom, lessThan(bar.top), reason: 'above the tab bar');

        // Three words on one line each, inside the selector.
        for (final label in [l10n.themeModeLight, l10n.themeModeDark, l10n.themeModeSystem]) {
          final text = find.descendant(of: find.byType(SegmentedButton<ThemeMode>), matching: find.text(label));
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: text, matching: find.byType(RichText)),
          );
          expect(paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.length)).map((box) => box.top).toSet(),
              hasLength(1), reason: '"$label" wraps');
          expect(paragraph.didExceedMaxLines, isFalse, reason: '"$label" is cut');
          expect(tester.getRect(text).right, lessThanOrEqualTo(theme.right));
        }
        expect(tester.takeException(), isNull);
      });
    });
  }

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

  testWidgets('the devices row counts the devices, flags the quiet one and opens their list over the tab bar',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
      final row = find.byKey(const ValueKey('settings-devices'));
      await scrollTo(tester, row);
      expect(find.descendant(of: row, matching: find.text(en.settingsDevicesRowCount(2))), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(en.settingsGraphStaleCount(1))), findsOneWidget);

      await tester.tap(row);
      await pumpFrames(tester, frames: 6);
      expect(find.byType(TrustedDevicesScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text(en.navChats), findsNothing, reason: 'the list covers the tab bar');
      expect(find.byType(TrustedDeviceCard), findsWidgets);
      expect(findCopy(en.settingsGraphStaleTitle), findsOneWidget, reason: 'the warning is whole on the list');
      // Three devices: the quiet one is one of the two trusted, not a third
      // beside them and the revoked one.
      expect(find.text('2 trusted devices (1 stale)  ·  '), findsOneWidget);
      expect(find.text('1 revoked'), findsOneWidget);
      expect(find.textContaining('·'), findsOneWidget, reason: 'two parts, which add up to the list');

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
        final row = find.byKey(const ValueKey('settings-devices'));
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
      await scrollTo(tester, find.byKey(const ValueKey('settings-devices')));
      await tester.tap(find.byKey(const ValueKey('settings-devices')));
      await pumpFrames(tester, frames: 6);

      // Only the quiet laptop can be revoked from here: not this device,
      // and not the one already revoked.
      final revoke = find.widgetWithText(OutlinedButton, en.settingsDeviceRevokeAction);
      await scrollTo(tester, revoke);
      expect(revoke, findsOneWidget);
      await tester.tap(revoke);
      await pumpFrames(tester, frames: 3);
      expect(findCopy(en.settingsRevokeListedTitle('MacBook Air')), findsOneWidget);
      expect(world.api.revokedDevices, isEmpty, reason: 'nothing is revoked before the answer');

      await tester.tap(find.widgetWithText(FilledButton, en.settingsRevokeConfirmAction));
      await pumpFrames(tester, frames: 6);
      expect(world.api.revokedDevices, ['dev-laptop']);
      expect(find.widgetWithText(OutlinedButton, en.settingsDeviceRevokeAction), findsNothing);
      expect(findCopy(en.settingsGraphStaleTitle, skipOffstage: false), findsNothing);
      // Nothing quiet is left to count among the trusted.
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await pumpFrames(tester, frames: 2);
      expect(find.text('1 trusted device  ·  '), findsOneWidget);
      expect(find.text('2 revoked'), findsOneWidget);
    });
  });

  group('what cannot be undone', () {
    testWidgets('is one group under the no-recovery notice, with what each action erases', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', locale: 'ko', body: (world) async {
        await scrollTo(tester, find.byKey(const ValueKey('settings-delete-account')));
        final notice = tester.getRect(find.byType(VeilDestructiveNotice));
        final rows = [
          for (final key in ['settings-logout', 'settings-wipe', 'settings-revoke', 'settings-delete-account'])
            find.byKey(ValueKey(key), skipOffstage: false),
        ];
        for (final row in rows) {
          expect(row, findsOneWidget);
          expect(tester.widget<VeilGroupRow>(row).destructive, isTrue);
        }
        expect(notice.top, lessThan(tester.getRect(rows.last).top));
        expect(findCopy(ko.settingsDestructiveNoticeBody, skipOffstage: false), findsOneWidget);
        for (final said in [
          ko.settingsLogoutSubtitle,
          ko.settingsWipeLocalSubtitle,
          ko.settingsRevokeSubtitle,
          ko.settingsDeleteAccountBody,
        ]) {
          expect(findCopy(said, skipOffstage: false), findsOneWidget);
        }
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
        FilledButton confirm() => tester.widget(find.widgetWithText(FilledButton, en.settingsLogout));
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

        FilledButton confirm() => tester.widget(find.widgetWithText(FilledButton, en.settingsLogout));
        await tester.enterText(find.byType(TextField), 'log');
        await tester.pump();
        expect(confirm().onPressed, isNull, reason: 'half the phrase is not the phrase');
        // Letter case is not the point.
        await tester.enterText(find.byType(TextField), 'log out');
        await tester.pump();
        expect(confirm().onPressed, isNotNull);

        await tester.tap(find.widgetWithText(FilledButton, en.settingsLogout));
        await pumpFrames(tester, frames: 6);
        expect(world.container.read(appSessionProvider).isAuthenticated, isFalse);
        expect(find.byType(CreateAccountScreen), findsOneWidget);
      });
    });

    testWidgets('each phrase is in the app\'s language, and the dialog fits above the keyboard at 360x640',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', locale: 'ko', keyboardHeight: 300,
          body: (world) async {
        for (final (key, phrase, action) in [
          ('settings-wipe', ko.settingsWipeConfirmPhrase, ko.settingsWipeConfirmAction),
          ('settings-revoke', ko.settingsRevokeConfirmPhrase, ko.settingsRevokeConfirmAction),
          ('settings-delete-account', ko.settingsDeleteAccountConfirmPhrase, ko.settingsDeleteAccountAction),
        ]) {
          final row = find.byKey(ValueKey(key));
          await scrollTo(tester, row);
          await tester.tap(row);
          await pumpFrames(tester, frames: 3);

          expect(isOtherLanguage(phrase, 'ko'), isFalse, reason: '"$phrase" is not Korean');
          expect(findCopy(ko.settingsTypePhraseToContinue(phrase)), findsOneWidget);
          final confirm = find.widgetWithText(FilledButton, action);
          expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
          await tester.enterText(find.byType(TextField), phrase);
          await tester.pump();
          expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
          // The field and the button that confirms are above the keyboard.
          expect(tester.getRect(find.byType(TextField)).top, greaterThanOrEqualTo(24), reason: 'under the status bar');
          expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(640 - 300));
          expect(tester.takeException(), isNull);

          await tester.tap(find.text(ko.commonCancel));
          await pumpFrames(tester, frames: 3);
        }
        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue);
      });
    });
  });
}
