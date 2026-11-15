import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_labels.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_screen_intro.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

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
    final loading = find.byType(VeilLoadingBlock);
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

    // The devices of the account, from their row on the settings tab.
    Future<void> openDevices(WidgetTester tester) async {
      // From the top: the screen was read to its end.
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await tester.pump();
      final row = find.byKey(const ValueKey('settings-devices'), skipOffstage: false);
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await pumpFrames(tester, frames: 2);
      await tester.tap(row);
      await pumpFrames(tester, frames: 6);
    }

    testWidgets('names the account, and says what each destructive action does', (tester) async {
      await withPhoneApp(tester, identities, location: '/settings', body: (world) async {
        final said = await read(tester);
        expect(said, containsAll([selfDisplayName, '@$selfHandle']), reason: 'the account was on screen');
        for (final text in [
          l10n.settingsSectionSecurity,
          l10n.settingsSectionDevices,
          l10n.settingsSectionIrreversible,
          l10n.settingsDestructiveNoticeBody,
          l10n.settingsWipeLocalSubtitle,
          l10n.settingsRevokeSubtitle,
          l10n.settingsLogoutSubtitle,
        ]) {
          expect(said, contains(text));
        }

        await openDevices(tester);
        final devices = await read(tester);
        expect(devices, containsAll(['Pixel 9 Pro Fold', 'MacBook Air', 'Old iPhone', 'Android']),
            reason: 'the devices were on screen');
        for (final text in ['2 trusted devices (1 stale)  ·  ', '1 revoked', 'Seen Apr 2 (UTC)', l10n.settingsGraphStaleBody]) {
          expect(devices, contains(text));
        }
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
      expect(transferStatusLabel(l10n, const TransferClaimApproved('c', 'f')), 'Approved claim c on old device. Key fingerprint: f');
    });
  });

  group('safety number with a pending identity change', () {
    const change = ChatAttention(identityChanged: true);
    const location = '/safety-numbers/$chatConversationId';

    testWidgets('a phone opens on the warning, before anything else', (tester) async {
      await withPhoneApp(tester, identities, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final warning = tester.getRect(find.text("This contact's identity key changed"));
        final intro = tester.getRect(find.byType(VeilScreenIntro));
        expect(find.byType(VeilHeroPanel), findsNothing);
        expect(warning.bottom, lessThan(intro.top));
        expect(warning.top, lessThan(screenHeight(tester) / 2), reason: 'on the first screenful');
        expect(find.text("This contact's identity key changed"), findsOneWidget, reason: 'said once');
      });
    });

    // The number to compare is the new one, so it comes first with the
    // decision under it; the pinned number follows for reference.
    testWidgets('says which number is the new one and which the current, the new one first', (tester) async {
      await withPhoneApp(tester, identities, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final current = find.text('CURRENT SAFETY NUMBER', skipOffstage: false);
        final next = find.text('NEW SAFETY NUMBER', skipOffstage: false);
        final decide = find.text('Re-verify with new key', skipOffstage: false);
        expect(next, findsOneWidget);
        final newTop = tester.getTopLeft(next).dy;
        final decideTop = tester.getTopLeft(decide).dy;
        await tester.dragUntilVisible(current, find.byType(ListView), const Offset(0, -200));
        expect(current, findsOneWidget);
        expect(newTop, lessThan(decideTop));
        expect(find.text('SAFETY NUMBER', skipOffstage: false), findsNothing);
        // Scrolled by now: compared within one frame.
        expect(tester.getTopLeft(next).dy, lessThan(tester.getTopLeft(current).dy));
      });
    });

    testWidgets('a wide window opens on the warning too, with the new number before the current one', (tester) async {
      const wide = PhoneSize(900, 1400, topInset: 0, bottomInset: 0);
      await withPhoneApp(tester, identities, size: wide, location: location, attention: change, body: (world) async {
        await awaitSafetyNumber(tester);
        final warning = find.text("This contact's identity key changed", skipOffstage: false);
        final current = find.text('CURRENT SAFETY NUMBER', skipOffstage: false);
        final next = find.text('NEW SAFETY NUMBER', skipOffstage: false);
        expect(tester.getTopLeft(warning).dy, lessThan(tester.getTopLeft(next).dy));
        expect(tester.getTopLeft(next).dy, lessThan(tester.getTopLeft(current).dy));
      });
    });

    testWidgets('with no change there is one number, under its plain label', (tester) async {
      await withPhoneApp(tester, identities, location: location, body: (world) async {
        await awaitSafetyNumber(tester);
        expect(find.text('SAFETY NUMBER', skipOffstage: false), findsOneWidget);
        expect(find.text("This contact's identity key changed", skipOffstage: false), findsNothing);
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

    testWidgets('above the keyboard shows its words and its button whole, without the icon', (tester) async {
      await withPhoneApp(tester, identities, location: location, keyboardHeight: 300, body: (world) async {
        final area = onScreen(tester, find.byType(ChatMessageList));
        for (final finder in [
          find.text('No messages yet'),
          find.textContaining('encrypted on this device'),
          find.widgetWithText(OutlinedButton, 'Compare safety numbers'),
        ]) {
          final box = tester.renderObject<RenderBox>(finder);
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(rect.top, greaterThanOrEqualTo(area.top), reason: '$finder');
          expect(rect.bottom, lessThanOrEqualTo(area.bottom), reason: '$finder');
        }
        expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget, reason: 'the composer\'s, not the state\'s');
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('with the whole screen shows its icon too', (tester) async {
      await withPhoneApp(tester, identities, location: location, body: (world) async {
        expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2), reason: 'the state\'s and the composer\'s');
        expect(find.text('No messages yet'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Compare safety numbers'), findsOneWidget);
      });
    });
  });
}
