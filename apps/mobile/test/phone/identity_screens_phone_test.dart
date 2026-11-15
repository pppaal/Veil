import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/auth/presentation/create_account_screen.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/step_row.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/brand_mark.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/onboarding_warning_screen.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_number_cards.dart';
import 'package:veil_mobile/src/features/security_status/presentation/security_signal_rows.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import '../support/copy_finder.dart';
import 'phone_app.dart';

// The screens around the account on a phone, content first: what each one
// is for is on its first screenful, losing the phone is said where the
// decision is made and once, and no screen opens on a slogan, a paragraph,
// a notice that only informs, or state words without a row.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  const signedOut = LayoutAccount.signedOut;

  // That the whole of [finder]'s first widget is on screen where a tap
  // reaches it, without anything having been scrolled.
  void expectInReach(WidgetTester tester, Finder finder) {
    expect(finder, findsWidgets);
    expect(whyNotWhollyTappable(tester, tester.renderObject<RenderBox>(finder.first)), isNull, reason: '$finder');
  }

  double top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder.first).dy;

  // The safety number is derived on a background isolate, which only real
  // time moves forward. (The page shows VeilLoadingBlock until it is.)
  Future<void> awaitSafetyNumber(WidgetTester tester) async {
    final loading = find.text(l10n.safetyNumbersLoadingTitle);
    for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(loading, findsNothing, reason: 'the safety number never loaded');
    await pumpFrames(tester, frames: 3);
  }

  group('splash', () {
    testWidgets('shows the mark and that the app is starting, and no words', (tester) async {
      usePhoneView(tester, phoneSmall);
      final world = await LayoutWorld.create(identities: identities, account: signedOut, locale: 'en', bootstrapping: true);
      try {
        await tester.pumpWidget(world.app(location: '/splash'));
        await pumpFrames(tester);
        expect(find.byType(BrandMark), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(Text), findsNothing, reason: 'the splash has no text');
        // A screen reader still hears what is going on.
        expect(find.bySemanticsLabel(l10n.splashPreparingTitle), findsOneWidget);
        // The mark sits where the native splash put it: in the middle.
        final mark = tester.getCenter(find.byType(BrandMark));
        expect(mark.dx, closeTo(phoneSmall.width / 2, 0.5));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        world.dispose();
      }
    });
  });

  group('privacy consent', () {
    testWidgets('the agree box and the button stay in reach while the notice scrolls', (tester) async {
      await withPhoneApp(tester, identities, location: '/privacy-consent', account: signedOut, body: (world) async {
        final button = find.widgetWithText(FilledButton, l10n.privacyConsentAccept);
        final lastSection = findCopy(l10n.privacyConsentThirdPartyBody);

        // On the first screenful of a 360x640 phone, before any scroll.
        expectInReach(tester, find.byType(Checkbox));
        expectInReach(tester, button);
        expect(lastSection, findsNothing, reason: 'the notice is longer than the screen');
        // The notice opens on its first group, not on words about itself.
        expect(top(tester, findCopy(l10n.privacyConsentCollectTitle)), lessThan(120));

        // The notice scrolls to its end under them.
        await tester.dragUntilVisible(lastSection, find.byType(ListView), const Offset(0, -300));
        await pumpFrames(tester, frames: 2);
        expect(lastSection, findsOneWidget);
        final notice = tester.getRect(find.byType(ListView));
        expect(tester.getRect(lastSection).bottom, lessThanOrEqualTo(notice.bottom));
        expect(notice.bottom, lessThanOrEqualTo(top(tester, find.byType(Checkbox))));
        expectInReach(tester, find.byType(Checkbox));
        expectInReach(tester, button);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('consent is not given without the box: the button does nothing until it is ticked', (tester) async {
      await withPhoneApp(tester, identities, location: '/privacy-consent', account: signedOut, body: (world) async {
        final button = find.widgetWithText(FilledButton, l10n.privacyConsentAccept);
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        await tester.tap(button);
        await pumpFrames(tester, frames: 3);
        expect(find.byType(OnboardingWarningScreen), findsNothing);
        expect(await world.storage.readPrivacyConsent(), isFalse);

        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        await tester.tap(button);
        await pumpFrames(tester, frames: 4);
        expect(find.byType(OnboardingWarningScreen), findsOneWidget);
        expect(await world.storage.readPrivacyConsent(), isTrue);
      });
    });
  });

  group('before you start', () {
    testWidgets('the three lines, the box and "Continue" on the first screenful; the loss said once', (tester) async {
      await withPhoneApp(tester, identities, location: '/onboarding', account: signedOut, body: (world) async {
        expect(findCopy(l10n.onboardingWarnTitle), findsOneWidget);
        for (final line in [l10n.onboardingWarnLine1, l10n.onboardingWarnLine2, l10n.onboardingWarnLine3]) {
          expectInReach(tester, findCopy(line));
        }
        expect(find.textContaining('no way to recover', skipOffstage: false), findsNWidgets(2),
            reason: 'the loss sentence and the box that says it was understood');
        expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);

        final box = find.widgetWithText(CheckboxListTile, l10n.onboardingWarnAgreeCheckbox);
        final proceed = find.widgetWithText(FilledButton, l10n.commonContinue);
        expectInReach(tester, box);
        expectInReach(tester, proceed);
        expect(tester.widget<FilledButton>(proceed).onPressed, isNull, reason: 'not before the box is ticked');
        await tester.tap(proceed);
        await pumpFrames(tester, frames: 3);
        expect(find.byType(CreateAccountScreen), findsNothing);

        await tester.tap(box);
        await tester.pump();
        expect(tester.widget<FilledButton>(proceed).onPressed, isNotNull);
        await tester.tap(proceed);
        await pumpFrames(tester, frames: 4);
        expect(find.byType(CreateAccountScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('create account', () {
    testWidgets('is the name field, "Continue" and one text button, and nothing else', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/create-account', account: signedOut,
          body: (world) async {
        final field = find.byType(TextField);
        final proceed = find.widgetWithText(FilledButton, l10n.commonContinue);
        final transfer = find.widgetWithText(TextButton, l10n.authCreateTransferLabel);
        expectInReach(tester, field);
        expectInReach(tester, proceed);
        expectInReach(tester, transfer);
        expect(field, findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(top(tester, field), lessThan(top(tester, proceed)));
        expect(top(tester, proceed), lessThan(top(tester, transfer)));
        // Before you start already said what losing the phone means.
        expect(find.byType(VeilNotice), findsNothing);
        expect(find.textContaining('recover'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('choose a handle', () {
    testWidgets('opens on the handle field and the button, with the one helper line', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/choose-handle', account: signedOut,
          body: (world) async {
        final create = find.widgetWithText(FilledButton, l10n.authHandleBindCta);
        expectInReach(tester, find.byType(TextField));
        expectInReach(tester, create);
        expect(findCopy(l10n.authHandleFindCaption), findsOneWidget);
        expect(top(tester, find.byType(TextField)), lessThan(top(tester, create)));
        expect(find.byType(VeilNotice), findsNothing);
        expect(find.byType(StepRow), findsNothing, reason: 'the stages are one line under the button, while it works');
      });
    });
  });

  group('device transfer on the new device', () {
    testWidgets('three numbered steps, then the code field, then the name and "Register"', (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', account: signedOut, body: (world) async {
        // Numbered 1 to 3, top to bottom, the first one in hand.
        final steps = tester.widgetList<StepRow>(find.byType(StepRow, skipOffstage: false)).toList();
        expect([for (final step in steps) step.number], [1, 2, 3]);
        expect([for (final step in steps) step.state],
            [StepRowState.current, StepRowState.upcoming, StepRowState.upcoming]);
        expect(find.byType(TextField), findsOneWidget, reason: 'only the step in hand shows its control');
        expectInReach(tester, find.byType(TextField));
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload));
        expect(top(tester, find.byType(TextField)), greaterThan(tester.getRect(find.byType(StepRow).last).bottom));
        expect(find.text(l10n.deviceTransferRegisterNewDevice, skipOffstage: false), findsNothing);

        // A code is read: the first step is done, the second is in hand
        // with the device's name.
        await tester.enterText(find.byType(TextField), 'VEIL_TRANSFER::session-1::token-1');
        await tester.tap(find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload));
        await pumpFrames(tester, frames: 3);
        final after = tester.widgetList<StepRow>(find.byType(StepRow, skipOffstage: false)).toList();
        expect([for (final step in after) step.state], [StepRowState.done, StepRowState.current, StepRowState.upcoming]);
        // That the code was read is the first step's check mark: nothing
        // else says so.
        expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);
        final name = tester.widget<TextField>(find.byType(TextField));
        expect(name.controller!.text, l10n.authDefaultDeviceName);
        expect(name.controller!.text, isNot('VEIL New Device'));
        expectInReach(tester, find.byType(TextField));
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.deviceTransferRegisterNewDevice));

        // That the old phone is needed is said once, under the steps.
        expect(findCopy(l10n.deviceTransferOldPhoneNeeded, skipOffstage: false), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a code that is not one is refused under the button that took it', (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', account: signedOut, body: (world) async {
        await tester.enterText(find.byType(TextField), 'not a code');
        final use = find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload);
        await tester.tap(use);
        await pumpFrames(tester, frames: 3);
        final refusal = find.text(l10n.deviceTransferPayloadInvalid);
        expect(refusal, findsOneWidget);
        expect(top(tester, refusal), greaterThanOrEqualTo(tester.getRect(use).bottom));
        expectInReach(tester, use);
        expect(find.text(l10n.deviceTransferRegisterNewDevice, skipOffstage: false), findsNothing);
      });
    });
  });

  group('device transfer on the old device', () {
    testWidgets('before a code is issued: "Get code" under the steps, and nothing asks for input', (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', body: (world) async {
        final steps = tester.widgetList<StepRow>(find.byType(StepRow, skipOffstage: false)).toList();
        expect([for (final step in steps) step.number], [1, 2, 3]);
        expect([for (final step in steps) step.state],
            [StepRowState.current, StepRowState.upcoming, StepRowState.upcoming]);
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.deviceTransferIssueToken));
        expect(find.byType(TextField, skipOffstage: false), findsNothing);
        expect(find.byType(FilledButton, skipOffstage: false), findsOneWidget);
        expect(findCopy(l10n.deviceTransferOldPhoneNeeded, skipOffstage: false), findsOneWidget);
        expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('with a code issued: the code with its copy button, then the approval', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await withPhoneApp(tester, identities, location: '/device-transfer', transferStarted: true, body: (world) async {
        final steps = tester.widgetList<StepRow>(find.byType(StepRow, skipOffstage: false)).toList();
        expect([for (final step in steps) step.number], [1, 2, 3]);
        expect(steps.first.state, StepRowState.done);

        final copy = find.byTooltip(l10n.deviceTransferCopyPayload);
        expectInReach(tester, copy);
        expect(tester.getSize(copy).width, greaterThanOrEqualTo(44));
        await tester.tap(copy);
        await pumpFrames(tester, frames: 2);
        expect(copied, hasLength(1));
        expect(copied.single, startsWith('VEIL_TRANSFER::'));

        // The claim field starts on the first screenful, and what approving
        // leads to is said between it and the button.
        final claim = find.byType(TextField, skipOffstage: false);
        expect(claim, findsOneWidget);
        expect(top(tester, claim), lessThan(screenHeight(tester)));
        final approve = find.text(l10n.deviceTransferApproveClaim, skipOffstage: false);
        final consequence = findCopyContaining(l10n.deviceTransferCompleteOnNewNote, skipOffstage: false);
        await tester.dragUntilVisible(approve, find.byType(ListView), const Offset(0, -200));
        await pumpFrames(tester, frames: 2);
        expect(consequence, findsOneWidget);
        expect(top(tester, claim), lessThan(top(tester, consequence)));
        expect(top(tester, consequence), lessThan(top(tester, approve)));
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('safety number', () {
    testWidgets('of a contact not yet verified: who, the number, "Mark as verified", then the code to scan',
        (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/safety-numbers/conv-priya',
          prepare: (world) async {
        // This device has talked to Priya, so her identity is pinned; nobody
        // compared numbers with her yet.
        final priya = world.relay.partiesByHandle['priya']!;
        await tester.runAsync(
          () => world.trust.resolver.evaluate(priya.userId, priya.deviceId, priya.identity.identityPublicKey),
        );
        return null;
      }, body: (world) async {
        await awaitSafetyNumber(tester);
        final mark = find.widgetWithText(FilledButton, l10n.safetyNumbersMarkVerified);
        final header = find.byType(SafetyPeerHeader);
        expect(find.descendant(of: header, matching: find.text(l10n.safetyNumbersUnverified)), findsOneWidget);
        // The number is read, not tapped: wholly on the first screenful.
        expect(tester.getRect(find.byType(SafetyNumberCard)).bottom, lessThan(screenHeight(tester)));
        expectInReach(tester, mark);
        final code = find.byType(SafetyQrCard, skipOffstage: false);
        expect(top(tester, header), lessThan(top(tester, find.byType(SafetyNumberCard))));
        expect(top(tester, find.byType(SafetyNumberCard)), lessThan(top(tester, mark)));
        expect(top(tester, mark), lessThan(top(tester, code)));

        // The digits on the page, with no label over them.
        expect(
          find.descendant(of: find.byType(SafetyNumberCard), matching: find.textContaining(RegExp('[A-Za-z]'))),
          findsNothing,
        );
        // How to compare is said once, under the number it is about and
        // above the button that records the comparison.
        final howTo = findCopy(l10n.safetyNumbersDetailBody);
        expect(howTo, findsOneWidget);
        expect(tester.getRect(find.byType(SafetyNumberCard)).bottom, lessThanOrEqualTo(top(tester, howTo)));
        expect(tester.getRect(howTo).bottom, lessThanOrEqualTo(top(tester, mark)));
      });
    });

    testWidgets('of a contact whose key changed in another conversation: the way to the review comes first',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/$chatConversationId', withGroup: true,
          attention: const ChatAttention(identityChangedInGroup: true), body: (world) async {
        await awaitSafetyNumber(tester);
        final review = find.widgetWithText(TextButton, l10n.safetyNumbersReviewChange);
        // On the first screenful of a 360x640 phone, in the notice, above
        // the number the change puts in question.
        expectInReach(tester, review);
        final notice = findCopy(l10n.safetyNumbersChangedElsewhereTitle);
        final current = find.byType(SafetyNumberCard, skipOffstage: false);
        expect(current, findsOneWidget);
        expect(top(tester, notice), lessThan(top(tester, review)));
        expect(tester.getRect(review).bottom, lessThanOrEqualTo(top(tester, current)));
        expect(findCopy(l10n.safetyNumbersCurrentNumberHeader, skipOffstage: false), findsOneWidget);
        // Nothing here compares or confirms the old key.
        expect(findCopy(l10n.safetyNumbersDetailBody, skipOffstage: false), findsNothing);
        expect(find.byType(SafetyQrCard, skipOffstage: false), findsNothing);
      });
    });

    testWidgets('with a change to review: the notice first, then the new number and the decision', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/safety-numbers/$chatConversationId',
          attention: const ChatAttention(identityChanged: true), body: (world) async {
        await awaitSafetyNumber(tester);
        final notice = findCopy(l10n.safetyNumbersKeyChangedTitle);
        final decide = find.widgetWithText(FilledButton, l10n.safetyNumbersReVerify);
        final newHeader = find.text(l10n.safetyNumbersNewNumberHeader);
        expectInReach(tester, notice);
        expectInReach(tester, newHeader);
        expectInReach(tester, decide);
        expect(top(tester, notice), lessThan(top(tester, find.byType(SafetyPeerHeader))));
        expect(find.text(l10n.safetyNumbersVerified, skipOffstage: false), findsNothing);
        expect(find.text(l10n.safetyNumbersUnverified), findsOneWidget);

        // How to compare is still said, for the new number: between it and
        // the decision.
        final newNumber = find.ancestor(of: newHeader, matching: find.byType(SafetyNumberCard));
        final howTo = findCopy(l10n.safetyNumbersDetailBody);
        expect(howTo, findsOneWidget);
        expect(tester.getRect(newNumber).bottom, lessThanOrEqualTo(top(tester, howTo)));
        expect(tester.getRect(howTo).bottom, lessThanOrEqualTo(top(tester, decide)));
      });
    });

    testWidgets('that cannot be worked out says so in the app\'s words, not in the error\'s', (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/conv-nobody', body: (world) async {
        await awaitSafetyNumber(tester);
        expect(findCopy(l10n.safetyNumbersErrorTitle), findsOneWidget);
        expect(findCopy(l10n.safetyNumbersErrorBody), findsOneWidget);

        // Trying again fails the same way: the page says so again, and the
        // error goes nowhere else.
        await tester.tap(find.text(l10n.safetyNumbersRetry));
        await pumpFrames(tester, frames: 3);
        await awaitSafetyNumber(tester);
        expect(tester.takeException(), isNull);
        expect(findCopy(l10n.safetyNumbersErrorTitle), findsOneWidget);
      });
    });

    testWidgets('of a group: a row per member with their state, how to compare under them', (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/$groupConversationId', withGroup: true,
          body: (world) async {
        await awaitSafetyNumber(tester);
        final rows = find.byType(VeilRow);
        expect(rows, findsNWidgets(groupMemberHandles.length));
        expectInReach(tester, rows);
        expect(top(tester, rows), lessThan(120), reason: 'the list opens under the bar');
        final howTo = findCopy(l10n.safetyNumbersGroupBody);
        expect(howTo, findsOneWidget);
        expect(top(tester, howTo), greaterThan(tester.getRect(rows.last).bottom));
      });
    });
  });

  group('security status', () {
    testWidgets('four groups of rows, each with its state as a word, under the bar', (tester) async {
      await withPhoneApp(tester, identities, location: '/security-status', body: (world) async {
        // No notice, no headline and no paragraph before the rows.
        expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);
        final firstGroup = find.byType(SecuritySignalGroup);
        expect(top(tester, firstGroup), lessThan(120), reason: 'rows start under the bar');

        final groups = <SecuritySignalGroup>{};
        void collect() => groups.addAll(tester.widgetList(find.byType(SecuritySignalGroup, skipOffstage: false)));
        collect();
        await scrollToEnd(tester, onPage: (_) async => collect());
        expect([for (final group in groups) group.title],
            [l10n.securityGroupThisPhone, l10n.securityGroupConnection, l10n.securityGroupEncryption, l10n.securityGroupRules]);
        for (final group in groups) {
          for (final signal in group.signals) {
            expect(signal.value, isNotEmpty, reason: signal.label);
            expect(signal.value.endsWith('.'), isFalse, reason: 'a word, not a sentence: ${signal.value}');
          }
        }
        final warning = [
          for (final group in groups)
            for (final signal in group.signals)
              if (signal.tone == SecuritySignalTone.warn) signal.label,
        ];
        expect(warning, contains(l10n.securityStatusTlsPins), reason: 'this build pins no TLS key');
        expect(tester.takeException(), isNull);
      });
    });

    // The longest state the screen has ("libsignal bridge (unaudited)"),
    // on a small phone with text enlarged past the system's usual step.
    testWidgets('a row whose state does not fit beside its label puts it under the label, whole', (tester) async {
      usePhoneView(tester, phoneSmall, textScale: 1.6);
      await tester.pumpWidget(MaterialApp(
        theme: VeilTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SecuritySignalGroup(
              title: l10n.securityGroupEncryption,
              signals: [
                SecuritySignal(
                  label: l10n.securityStatusCryptoImplementation,
                  value: l10n.securityStatusCryptoLibsignal,
                  detail: l10n.securityStatusCryptoLibsignalDetail('libsignal'),
                  tone: SecuritySignalTone.neutral,
                ),
                SecuritySignal(
                  label: l10n.securityStatusLocalWipe,
                  value: l10n.securityStatusLocalWipeValue,
                  tone: SecuritySignalTone.neutral,
                ),
              ],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'nothing overflows');

      RenderParagraph paragraphOf(String text) =>
          tester.renderObject<RenderParagraph>(find.descendant(of: find.text(text), matching: find.byType(RichText)));
      double lineCount(String text) {
        final paragraph = paragraphOf(text);
        return paragraph.size.height / paragraph.getFullHeightForCaret(const TextPosition(offset: 0));
      }

      // The label keeps one line and the state is not cut short; it stands
      // under the label, from the same left edge.
      final label = tester.getRect(find.text(l10n.securityStatusCryptoImplementation));
      final state = tester.getRect(find.text(l10n.securityStatusCryptoLibsignal));
      expect(lineCount(l10n.securityStatusCryptoImplementation), closeTo(1, 0.2));
      expect(paragraphOf(l10n.securityStatusCryptoLibsignal).didExceedMaxLines, isFalse);
      expect(state.top, greaterThanOrEqualTo(label.bottom));
      expect(state.left, closeTo(label.left, 1));

      // A short state stays at the end of its label's line.
      final shortLabel = tester.getRect(find.text(l10n.securityStatusLocalWipe));
      final shortState = tester.getRect(find.text(l10n.securityStatusLocalWipeValue));
      expect(shortState.left, greaterThan(shortLabel.right));
      expect(shortState.center.dy, closeTo(shortLabel.center.dy, 4));
      final row = tester.getRect(find.byType(SecuritySignalRow).last);
      expect(row.right - shortState.right, closeTo(VeilSpace.md, 1), reason: 'at the end of the row');
    });

    test('counts in words that agree with the number', () {
      expect(l10n.appLockStatusPinMismatchAttempts(1), 'Wrong PIN. 1 attempt left.');
      expect(l10n.appLockStatusPinMismatchAttempts(2), 'Wrong PIN. 2 attempts left.');
    });
  });
}
