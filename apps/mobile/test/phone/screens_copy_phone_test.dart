import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_labels.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_number_cards.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// What the screens around the chat say on a phone, and in which order: the
// settings say what each destructive action does, a pending identity change
// comes first on the screen that reviews it, and the consent row is one tap
// target.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // The safety number is derived on a background isolate, which only real
  // time moves forward.
  Future<void> awaitSafetyNumber(WidgetTester tester) async {
    final loading = find.byKey(SafetyNumbersScreen.loadingKey);
    for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await pumpFrames(tester, frames: 3);
  }

  group('settings', () {
    Set<String> textsShown(WidgetTester tester) => {
          for (final element in find.byType(Text).evaluate())
            if ((element.widget as Text).data case final text?) text,
        };

    // Everything the screen says from top to bottom.
    Future<Set<String>> read(WidgetTester tester) async {
      final said = textsShown(tester);
      await scrollToEnd(tester, onPage: (_) async => said.addAll(textsShown(tester)));
      return said;
    }

    // Brings the row with [key] on screen, from the top: the screen may
    // have been read to its end.
    Future<void> scrollToRow(WidgetTester tester, String key) async {
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await tester.pump();
      final row = find.byKey(ValueKey(key), skipOffstage: false);
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await pumpFrames(tester, frames: 2);
    }

    testWidgets('names the account, and says the loss of an account once, in the security footer', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        final said = await read(tester);
        expect(said, containsAll([selfDisplayName, '@$selfHandle']), reason: 'the account was on screen');
        for (final text in [
          l10n.settingsSectionSecurity,
          l10n.settingsSectionDevices,
          l10n.settingsSectionAccount,
          '${l10n.securityFooterEncryption} ${l10n.securityFooterNoRecovery}',
          l10n.settingsLogout,
          l10n.settingsWipeLocal,
          l10n.settingsRevokeTitle,
          l10n.settingsDeleteAccountAction,
        ]) {
          expect(said, contains(text));
        }
        // The security footer is the only text of the screen that names
        // the backup there is not.
        expect([for (final text in said) if (text.toLowerCase().contains('backup')) text],
            ['${l10n.securityFooterEncryption} ${l10n.securityFooterNoRecovery}']);
      });
    });

    testWidgets('each destructive action says in its dialog what it erases, before the typed phrase',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', size: phoneLarge, body: (world) async {
        for (final (key, title, body, phrase) in [
          ('settings-logout', l10n.settingsLogoutConfirmTitle, l10n.settingsLogoutConfirmBody, l10n.settingsLogoutConfirmPhrase),
          ('settings-wipe', l10n.settingsWipeConfirmTitle, l10n.settingsWipeConfirmBody, l10n.settingsWipeConfirmPhrase),
          ('settings-revoke', l10n.settingsRevokeConfirmTitle, l10n.settingsRevokeConfirmBody, l10n.settingsRevokeConfirmPhrase),
          (
            'settings-delete-account',
            l10n.settingsDeleteAccountConfirmHeadline,
            l10n.settingsDeleteAccountBody,
            l10n.settingsDeleteAccountConfirmPhrase
          ),
        ]) {
          await scrollToRow(tester, key);
          await tester.tap(find.byKey(ValueKey(key)));
          await pumpFrames(tester, frames: 3);
          final dialog = find.byType(AlertDialog);
          expect(find.descendant(of: dialog, matching: find.text(title)), findsOneWidget, reason: key);
          final said = find.descendant(of: dialog, matching: find.text(body));
          expect(said, findsOneWidget, reason: '$key says what it does');
          // What it erases, and that nothing brings it back.
          expect(body, anyOf(contains('erases'), contains('deletes'), contains('wipes')), reason: key);
          expect(body.toLowerCase(), contains('backup'), reason: key);
          final prompt = find.descendant(of: dialog, matching: find.text(l10n.settingsTypePhraseToContinue(phrase)));
          expect(tester.getRect(said).bottom, lessThan(tester.getRect(prompt).top), reason: 'read before typing');
          await tester.tap(find.text(l10n.commonCancel));
          await pumpFrames(tester, frames: 3);
        }
        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue);
      });
    });

    testWidgets('the devices list says what the server knows of each device', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        await scrollToRow(tester, 'settings-device-dev-laptop');
        await tester.tap(find.byKey(const ValueKey('settings-device-dev-laptop')));
        await pumpFrames(tester, frames: 6);
        final devices = await read(tester);
        expect(devices, containsAll(['Pixel 9 Pro Fold', 'MacBook Air', 'Old iPhone', 'Android']),
            reason: 'the devices were on screen');
        for (final text in ['Last seen Apr 2 (UTC)', 'Approved by Pixel 9 Pro Fold', l10n.settingsDeviceNoteStale]) {
          expect(devices, contains(text));
        }
        // No count of what the list already shows.
        expect(devices.where((text) => text.contains('·')), isEmpty);
      });
    });
  });

  group('device transfer', () {
    test('every outcome of the old device has words of its own', () {
      const outcomes = <TransferStatus>[
        TransferNeedsApi(),
        TransferTokenReady(),
        TransferNotStarted(),
        TransferClaimCodeMissing(),
        TransferClaimNotWaiting('claim-7'),
        TransferClaimApproved('claim-7', 'AB12 CD34'),
      ];
      final labels = [for (final outcome in outcomes) transferStatusLabel(l10n, outcome)!];
      expect(labels.toSet(), hasLength(outcomes.length));
      expect(labels[4], contains('claim-7'));
      expect(labels[5], allOf(contains('claim-7'), contains('AB12 CD34')));
      expect(transferStatusLabel(l10n, null), isNull);
      expect(transferStatusLabel(l10n, const TransferClaimApproved('c', 'f')), 'Approved code c. Key fingerprint: f');
    });
  });

  group('safety number with a pending identity change', () {
    const change = ChatAttention(identityChanged: true);
    const location = '/safety-numbers/$chatConversationId';
    // The screen's bar says "Safety number" too, so the label over the one
    // number is found inside its card.
    final plainLabel = find.descendant(
      of: find.byType(SafetyNumberCard, skipOffstage: false),
      matching: find.text('Safety number', skipOffstage: false),
    );

    testWidgets('a phone opens on the warning, before anything else', (tester) async {
      await withPhoneApp(tester, identities, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final warning = tester.getRect(find.text('Safety number changed'));
        final intro = tester.getRect(find.byType(SafetyPeerHeader));
        expect(warning.bottom, lessThan(intro.top));
        expect(warning.top, lessThan(screenHeight(tester) / 2), reason: 'on the first screenful');
        expect(find.text('Safety number changed'), findsOneWidget, reason: 'said once');
      });
    });

    // The number to compare is the new one, so it comes first with the
    // decision under it; the pinned number follows for reference.
    testWidgets('says which number is the new one and which the current, the new one first', (tester) async {
      await withPhoneApp(tester, identities, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final current = find.text('Current safety number', skipOffstage: false);
        final next = find.text('New safety number', skipOffstage: false);
        final decide = find.text('Verify the new number', skipOffstage: false);
        expect(next, findsOneWidget);
        final newTop = tester.getTopLeft(next).dy;
        final decideTop = tester.getTopLeft(decide).dy;
        await tester.dragUntilVisible(current, find.byType(ListView), const Offset(0, -200));
        expect(current, findsOneWidget);
        expect(newTop, lessThan(decideTop));
        expect(plainLabel, findsNothing);
        // Scrolled by now: compared within one frame.
        expect(tester.getTopLeft(next).dy, lessThan(tester.getTopLeft(current).dy));
      });
    });

    testWidgets('a wide window opens on the warning too, with the new number before the current one', (tester) async {
      const wide = PhoneSize(900, 1400, topInset: 0, bottomInset: 0);
      await withPhoneApp(tester, identities, size: wide, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final warning = find.text('Safety number changed', skipOffstage: false);
        final current = find.text('Current safety number', skipOffstage: false);
        final next = find.text('New safety number', skipOffstage: false);
        expect(tester.getTopLeft(warning).dy, lessThan(tester.getTopLeft(next).dy));
        expect(tester.getTopLeft(next).dy, lessThan(tester.getTopLeft(current).dy));
      });
    });

    testWidgets('with no change there is one number, with no label over it', (tester) async {
      await withPhoneApp(tester, identities, location: location, body: (world) async {
        await awaitSafetyNumber(tester);
        expect(find.byType(SafetyNumberCard), findsOneWidget);
        expect(plainLabel, findsNothing);
        expect(find.text('Safety number changed', skipOffstage: false), findsNothing);
      });
    });
  });

  group('privacy consent', () {
    // The framework's tap target check never measured this row: it starts
    // at the left edge of its column. It was 24 px tall once.
    testWidgets('the consent sentence and its box are one target, 44 px tall, and either toggles it',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/privacy-consent', account: LayoutAccount.signedOut,
          body: (world) async {
        // Under the notice from the start: nothing is scrolled to reach it.
        final sentence = findCopy(l10n.privacyConsentAgree);
        expect(sentence, findsOneWidget);

        final row = find.ancestor(of: sentence, matching: find.byType(MergeSemantics)).first;
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
        expect(await smallTapTargetsOnScreen(tester, minimum: minimumTapTarget), isEmpty);

        bool checked() => tester.widget<Checkbox>(find.byType(Checkbox)).value!;
        FilledButton proceed() => tester.widget(find.widgetWithText(FilledButton, l10n.privacyConsentAccept));
        expect(checked(), isFalse);
        expect(proceed().onPressed, isNull);

        await tester.tap(sentence);
        await tester.pump();
        expect(checked(), isTrue);
        expect(proceed().onPressed, isNotNull);

        // Just under the sentence, inside the row's own padding.
        await tester.tapAt(tester.getRect(row).bottomCenter.translate(0, -3));
        await tester.pump();
        expect(checked(), isFalse);

        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        expect(checked(), isTrue);
      });
    });
  });

  group('an empty chat', () {
    const location = '/chat/$emptyChatConversationId';

    // A compact empty state is its title and its button (design system
    // 7.8): the line under the title and the icon wait for the whole screen.
    testWidgets('above the keyboard shows its title and its button whole, without the icon', (tester) async {
      await withPhoneApp(tester, identities, location: location, keyboardHeight: 300, body: (world) async {
        final area = onScreen(tester, find.byType(ChatMessageList));
        for (final finder in [
          find.text('No messages yet'),
          find.widgetWithText(OutlinedButton, 'Compare safety numbers'),
        ]) {
          final box = tester.renderObject<RenderBox>(finder);
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(rect.top, greaterThanOrEqualTo(area.top), reason: '$finder');
          expect(rect.bottom, lessThanOrEqualTo(area.bottom), reason: '$finder');
        }
        expect(find.textContaining('end-to-end encrypted'), findsNothing);
        // Neither the state's icon nor a padlock in the composer, which has none.
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('with the whole screen shows the line that messages are end-to-end encrypted too', (tester) async {
      await withPhoneApp(tester, identities, location: location, body: (world) async {
        expect(find.text('Messages are end-to-end encrypted.'), findsOneWidget);
        // No padlock, in the state or in the composer (design system 11.2).
        expect(find.byIcon(Icons.lock_outline), findsNothing);
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
        expect(find.text('No messages yet'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Compare safety numbers'), findsOneWidget);
      });
    });
  });
}
