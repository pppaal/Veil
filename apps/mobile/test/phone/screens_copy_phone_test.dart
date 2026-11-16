import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_adapter_registry.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_labels.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_number_cards.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// What the screens around the chat say on a phone, and in which order: the
// settings' account actions say what they erase, a pending identity change
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

    testWidgets('names the account, and the security group ends in one plain line, with no paragraph', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        final said = await read(tester);
        expect(said, containsAll([selfDisplayName, '@$selfHandle']), reason: 'the account was on screen');
        final testBuild =
            cryptoAdapterKindOf(world.container.read(cryptoAdapterProvider).adapterId) == CryptoAdapterKind.development;
        for (final text in [
          l10n.settingsSectionSecurity,
          l10n.settingsSectionAccount,
          testBuild ? l10n.securityFooterTestBuild : l10n.securityFooterUnaudited,
          l10n.settingsDeviceTransferTitle,
          l10n.settingsLogout,
          l10n.settingsDeleteAccountAction,
        ]) {
          expect(said, contains(text));
        }
        // What losing the account means is said in the dialogs that lose
        // it, and in Before you start; Settings has no paragraph on it.
        expect([for (final text in said) if (text.toLowerCase().contains('backup')) text], isEmpty);
        expect([for (final text in said) if (text.toLowerCase().contains('recover')) text], isEmpty);
      });
    });

    // "Erases Veil from it" read as uninstalling the app. Sign out deletes
    // what Veil keeps on this phone, the chats among it, and leaves no
    // device that can open the account (one phone at a time); the app
    // itself stays.
    // The account itself stays on the server, its handle taken; what is lost
    // is the way back in, which no backup or reset gives (the web's sign
    // out says the same). Changed on purpose: the body no longer opens with
    // "This signs this phone out", which said the title again.
    test('Sign out says what it deletes and what is lost, not that the app goes', () {
      final body = l10n.settingsLogoutConfirmBody('alex');
      expect(body, isNot(contains('Veil')), reason: 'the app is not what goes');
      expect(body, isNot(contains('uninstall')));
      expect(body, isNot(contains('signs this phone out')), reason: 'the title says it');
      expect(body, contains('chats on this phone are deleted'));
      expect(body, contains("you can't sign in as @alex again."));
      expect(body, isNot(contains('account is gone')), reason: 'the account stays on the server');
      expect(body.split(RegExp(r'(?<=[.!?])\s+')), hasLength(1), reason: 'one short sentence');
    });

    testWidgets('each account action says in its dialog what it erases, before the typed handle', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', size: phoneLarge, body: (world) async {
        for (final (key, title, body) in [
          ('settings-logout', l10n.settingsLogoutConfirmTitle, l10n.settingsLogoutConfirmBody(selfHandle)),
          ('settings-delete-account', l10n.settingsDeleteAccountConfirmHeadline, l10n.settingsDeleteAccountBody),
        ]) {
          await scrollToRow(tester, key);
          await tester.tap(find.byKey(ValueKey(key)));
          await pumpFrames(tester, frames: 3);
          final dialog = find.byType(AlertDialog);
          expect(find.descendant(of: dialog, matching: find.text(title)), findsOneWidget, reason: key);
          final said = find.descendant(of: dialog, matching: find.text(body));
          expect(said, findsOneWidget, reason: '$key says what it does');
          // What it erases, and that nothing brings it back.
          expect(body, anyOf(contains('erases'), contains('deletes'), contains('are deleted')), reason: key);
          expect(body, anyOf(contains("can't sign in"), contains("can't be undone")), reason: key);
          final prompt =
              find.descendant(of: dialog, matching: find.text(l10n.settingsTypePhraseToContinue('@$selfHandle')));
          expect(tester.getRect(said).bottom, lessThan(tester.getRect(prompt).top), reason: 'read before typing');
          await tester.tap(find.text(l10n.commonCancel));
          await pumpFrames(tester, frames: 3);
        }
        expect(world.container.read(appSessionProvider).isAuthenticated, isTrue);
      });
    });
  });

  group('device transfer', () {
    test('every outcome of the old device that needs saying has words of its own', () {
      const outcomes = <TransferStatus>[
        TransferNeedsApi(),
        TransferNotStarted(),
        TransferClaimCodeMissing(),
        TransferClaimNotWaiting('claim-7'),
        TransferClaimApproved('claim-7', 'AB12 CD34'),
      ];
      final labels = [for (final outcome in outcomes) transferStatusLabel(l10n, outcome)!];
      expect(labels.toSet(), hasLength(outcomes.length));
      expect(labels[3], contains('claim-7'));
      expect(labels[4], l10n.deviceTransferStatusClaimApproved);
      // The code on screen says it is ready, and the approve dialog shows
      // a claim that waits: no line repeats them.
      expect(transferStatusLabel(l10n, null), isNull);
      expect(transferStatusLabel(l10n, const TransferTokenReady()), isNull);
      expect(transferStatusLabel(l10n, const TransferClaimWaiting('c', 'f')), isNull);
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

    // The number to compare is the new one: it is the one number on the
    // page, labelled as such, with the decision under it (as Signal shows
    // only the number in question).
    testWidgets('shows the new number alone, labelled, with the decision under it', (tester) async {
      await withPhoneApp(tester, identities, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final next = find.text(l10n.safetyNumbersNewNumberHeader, skipOffstage: false);
        final decide = find.text(l10n.safetyNumbersReVerify, skipOffstage: false);
        expect(next, findsOneWidget);
        expect(find.byType(SafetyNumberCard, skipOffstage: false), findsOneWidget);
        expect(find.text(l10n.safetyNumbersCurrentNumberHeader, skipOffstage: false), findsNothing);
        expect(tester.getTopLeft(next).dy, lessThan(tester.getTopLeft(decide).dy));
        expect(plainLabel, findsNothing);
      });
    });

    testWidgets('a wide window opens on the warning too, with the new number under it', (tester) async {
      const wide = PhoneSize(900, 1400, topInset: 0, bottomInset: 0);
      await withPhoneApp(tester, identities, size: wide, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final warning = find.text('Safety number changed', skipOffstage: false);
        final next = find.text(l10n.safetyNumbersNewNumberHeader, skipOffstage: false);
        expect(tester.getTopLeft(warning).dy, lessThan(tester.getTopLeft(next).dy));
        expect(find.byType(SafetyNumberCard, skipOffstage: false), findsOneWidget);
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

    // One muted line, as Telegram's "No messages here yet": no line on
    // encryption, no button and no icon, with the keyboard up or not.
    for (final keyboard in [0.0, 300.0]) {
      testWidgets('shows "No messages yet" alone and whole (keyboard ${keyboard > 0 ? 'up' : 'down'})', (tester) async {
        await withPhoneApp(tester, identities, location: location, keyboardHeight: keyboard, body: (world) async {
          final area = onScreen(tester, find.byType(ChatMessageList));
          final box = tester.renderObject<RenderBox>(find.text('No messages yet'));
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(rect.top, greaterThanOrEqualTo(area.top));
          expect(rect.bottom, lessThanOrEqualTo(area.bottom));
          expect(find.textContaining('end-to-end encrypted'), findsNothing);
          expect(find.text('Compare safety numbers'), findsNothing);
          // No padlock, in the state or in the composer (design system 11.2).
          expect(find.byIcon(Icons.lock_outline), findsNothing);
          expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });
    }
  });
}
