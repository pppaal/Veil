import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_step.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/onboarding_warning_screen.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_number_cards.dart';
import 'package:veil_mobile/src/features/security_status/presentation/security_signal_rows.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_screen_intro.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import '../support/copy_finder.dart';
import 'phone_app.dart';

// The screens around the account on a phone, content first: what each one
// is for is on its first screenful, a warning about recovery is said once
// where the decision is made, and no screen opens on a hero card, slogan
// pills or tiles.

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

  // No panel, pills or tiles stand between the bar and what the screen is
  // for.
  void expectNoDashboard() {
    expect(find.byType(VeilHeroPanel, skipOffstage: false), findsNothing);
    expect(find.byType(VeilMetricStrip, skipOffstage: false), findsNothing);
  }

  // The safety number is derived on a background isolate, which only real
  // time moves forward.
  Future<void> awaitSafetyNumber(WidgetTester tester) async {
    final loading = find.byType(VeilLoadingBlock);
    for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(loading, findsNothing, reason: 'the safety number never loaded');
    await pumpFrames(tester, frames: 3);
  }

  group('splash', () {
    testWidgets('shows the name, its one line and what the app is doing, and nothing else', (tester) async {
      usePhoneView(tester, phoneSmall);
      final world = await LayoutWorld.create(identities: identities, account: signedOut, locale: 'en', bootstrapping: true);
      try {
        await tester.pumpWidget(world.app(location: '/splash'));
        await pumpFrames(tester);
        expectNoDashboard();
        expect(find.byType(VeilStatusPill), findsNothing);
        expect(find.text('Veil'), findsOneWidget);
        expect(findCopy(l10n.splashPreparingTitle), findsOneWidget);
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
        expectNoDashboard();

        // On the first screenful of a 360x640 phone, before any scroll.
        expectInReach(tester, find.byType(Checkbox));
        expectInReach(tester, button);
        expect(lastSection, findsNothing, reason: 'the notice is longer than the screen');

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

  group('onboarding warning', () {
    testWidgets('"I understand" is in reach from the start, under the one no-recovery notice', (tester) async {
      await withPhoneApp(tester, identities, location: '/onboarding', account: signedOut, body: (world) async {
        expectNoDashboard();
        expect(find.byType(VeilStatusPill, skipOffstage: false), findsNothing);
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.commonIUnderstand));
        expect(findCopy(l10n.onboardingWarnTitle), findsOneWidget);
        expect(find.byType(VeilDestructiveNotice, skipOffstage: false), findsOneWidget);
        expect(findCopy(l10n.onboardingWarnDestructiveBody, skipOffstage: false), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    test('calls what stays on the device a key, as the consent screen does', () {
      // The consent lists what the server stores about a person; the keys
      // are not that.
      expect(l10n.onboardingWarnIdentityLine2, contains('private keys'));
    });
  });

  group('create account', () {
    testWidgets('opens on the name field, with the notice once between it and the two ways on', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/create-account', account: signedOut,
          body: (world) async {
        final proceed = find.widgetWithText(FilledButton, l10n.commonContinue);
        final transfer = find.widgetWithText(OutlinedButton, l10n.authCreateTransferLabel);
        expectNoDashboard();
        expect(find.byType(VeilStatusPill, skipOffstage: false), findsNothing);
        expectInReach(tester, find.byType(TextField));
        expectInReach(tester, proceed);
        expectInReach(tester, transfer);

        final notice = find.byType(VeilDestructiveNotice);
        expect(notice, findsOneWidget);
        expect(findCopy(l10n.authCreateRestoreBody), findsOneWidget);
        expect(top(tester, find.byType(TextField)), lessThan(top(tester, notice)));
        expect(top(tester, notice), lessThan(top(tester, proceed)));
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('choose handle', () {
    testWidgets('opens on the handle field and the button that binds it, the steps under them', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/choose-handle', account: signedOut,
          body: (world) async {
        final bind = find.widgetWithText(FilledButton, l10n.authHandleBindCta);
        expectNoDashboard();
        expect(find.byType(VeilStatusPill, skipOffstage: false), findsNothing);
        expectInReach(tester, find.byType(TextField));
        expectInReach(tester, bind);
        expect(top(tester, bind), lessThan(top(tester, find.byType(VeilStepRow))));
      });
    });
  });

  group('device transfer on the new device', () {
    testWidgets('three numbered steps, the code field first, then the name and "Register"', (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', account: signedOut, body: (world) async {
        expectNoDashboard();
        expect(find.byType(VeilStatusPill, skipOffstage: false), findsNothing);

        // Numbered 1 to 3, top to bottom, the first one in hand.
        final steps = tester.widgetList<TransferStep>(find.byType(TransferStep, skipOffstage: false)).toList();
        expect([for (final step in steps) step.number], [1, 2, 3]);
        expect([for (final step in steps) step.state],
            [TransferStepState.current, TransferStepState.upcoming, TransferStepState.upcoming]);
        expect(find.byType(TextField), findsOneWidget, reason: 'only the step in hand shows its control');
        expectInReach(tester, find.byType(TextField));
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload));
        expect(find.text(l10n.deviceTransferRegisterNewDevice, skipOffstage: false), findsNothing);

        // A code is read: the first step closes, the second takes its
        // place at the top with the device's name.
        await tester.enterText(find.byType(TextField), 'VEIL_TRANSFER::session-1::token-1');
        await tester.tap(find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload));
        await pumpFrames(tester, frames: 3);
        final after = tester.widgetList<TransferStep>(find.byType(TransferStep, skipOffstage: false)).toList();
        expect([for (final step in after) step.state],
            [TransferStepState.done, TransferStepState.current, TransferStepState.upcoming]);
        // That the code was read is the first step's check mark: no banner
        // stands between the step's words and its field.
        expect(find.byType(VeilInlineBanner, skipOffstage: false), findsNothing);
        final name = tester.widget<TextField>(find.byType(TextField));
        expect(name.controller!.text, l10n.authDefaultDeviceName);
        expect(name.controller!.text, isNot('VEIL New Device'));
        expectInReach(tester, find.byType(TextField));
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.deviceTransferRegisterNewDevice));

        // The no-fallback notice is still on the screen, once, after the steps.
        expect(find.byType(VeilDestructiveNotice, skipOffstage: false), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a code that is not one is refused in the step that took it', (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', account: signedOut, body: (world) async {
        await tester.enterText(find.byType(TextField), 'not a code');
        await tester.tap(find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload));
        await pumpFrames(tester, frames: 3);
        final refusal = find.text(l10n.deviceTransferPayloadInvalid);
        expect(refusal, findsOneWidget);
        expect(find.ancestor(of: refusal, matching: find.byType(TransferStep)), findsOneWidget);
        expect(tester.widget<TransferStep>(find.ancestor(of: refusal, matching: find.byType(TransferStep))).number, 1);
        expect(find.text(l10n.deviceTransferRegisterNewDevice, skipOffstage: false), findsNothing);
      });
    });
  });

  group('device transfer on the old device', () {
    testWidgets('before a code is issued: the first step is its button, and nothing else asks for input',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', body: (world) async {
        expectNoDashboard();
        final steps = tester.widgetList<TransferStep>(find.byType(TransferStep, skipOffstage: false)).toList();
        expect([for (final step in steps) step.number], [1, 2, 3]);
        expect([for (final step in steps) step.state],
            [TransferStepState.current, TransferStepState.upcoming, TransferStepState.upcoming]);
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.deviceTransferIssueToken));
        expect(find.byType(TextField, skipOffstage: false), findsNothing);
        expect(find.byType(FilledButton, skipOffstage: false), findsOneWidget);
        expect(find.byType(VeilDestructiveNotice, skipOffstage: false), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('with a code issued: the code, "Copy code" on one line, then the approval', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await withPhoneApp(tester, identities, location: '/device-transfer', transferStarted: true, body: (world) async {
        expectNoDashboard();
        final steps = tester.widgetList<TransferStep>(find.byType(TransferStep, skipOffstage: false)).toList();
        expect([for (final step in steps) step.number], [1, 2, 3]);
        expect(steps.first.state, TransferStepState.done);

        // The copy button's label is one line, beside the short "Clear".
        final copy = find.widgetWithText(OutlinedButton, l10n.deviceTransferCopyPayload);
        expectInReach(tester, copy);
        final label = tester.renderObject<RenderParagraph>(
          find.descendant(of: copy, matching: find.byType(RichText)).last,
        );
        expect(label.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.text.toPlainText().length))
            .map((box) => box.top)
            .toSet(), hasLength(1), reason: '"${l10n.deviceTransferCopyPayload}" wraps inside its button');
        expect(top(tester, copy), closeTo(top(tester, find.text(l10n.deviceTransferClear)), 20));

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
        final consequence = findCopy(l10n.deviceTransferCompleteOnNewNote, skipOffstage: false);
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
    testWidgets('of a contact not yet verified: the number and "Mark as verified" before the code to scan',
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
        expectNoDashboard();
        expect(find.byType(VeilScreenIntro), findsOneWidget);
        expect(find.text(l10n.safetyNumbersUnverified), findsOneWidget);
        expectInReach(tester, find.byType(SafetyNumberCard));
        expectInReach(tester, mark);
        final code = find.byType(SafetyQrCard, skipOffstage: false);
        expect(top(tester, find.byType(SafetyNumberCard)), lessThan(top(tester, mark)));
        expect(top(tester, mark), lessThan(top(tester, code)));

        // How to compare is said once, under the number it is about and
        // above the button that records the comparison: not above the number.
        final howTo = findCopy(l10n.safetyNumbersDetailBody);
        expect(howTo, findsOneWidget);
        expect(tester.widget<VeilScreenIntro>(find.byType(VeilScreenIntro)).body, isNull);
        expect(tester.getRect(find.byType(SafetyNumberCard)).bottom, lessThanOrEqualTo(top(tester, howTo)));
        expect(tester.getRect(howTo).bottom, lessThanOrEqualTo(top(tester, mark)));
      });
    });

    testWidgets('of a contact whose key changed in another conversation: the way to the review comes first',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/$chatConversationId', withGroup: true,
          attention: const ChatAttention(identityChangedInGroup: true), body: (world) async {
        await awaitSafetyNumber(tester);
        final review = find.widgetWithText(FilledButton, l10n.safetyNumbersReviewChange);
        // On the first screenful of a 360x640 phone, under the notice and
        // above the number the change puts in question.
        expectInReach(tester, review);
        final notice = findCopy(l10n.safetyNumbersChangedElsewhereTitle);
        final current = find.byType(SafetyNumberCard, skipOffstage: false);
        expect(current, findsOneWidget);
        expect(top(tester, notice), lessThan(top(tester, review)));
        expect(tester.getRect(review).bottom, lessThanOrEqualTo(top(tester, current)));
        // Nothing here compares or confirms the old key.
        expect(findCopy(l10n.safetyNumbersDetailBody, skipOffstage: false), findsNothing);
        expect(find.byType(SafetyQrCard, skipOffstage: false), findsNothing);
      });
    });

    testWidgets('with a change to review: the new number and the decision on the first screenful', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/safety-numbers/$chatConversationId',
          attention: const ChatAttention(identityChanged: true), body: (world) async {
        await awaitSafetyNumber(tester);
        final decide = find.widgetWithText(FilledButton, l10n.safetyNumbersReVerify);
        expectInReach(tester, find.text(l10n.safetyNumbersCardLabelNew));
        expectInReach(tester, decide);
        expect(find.text(l10n.safetyNumbersVerified, skipOffstage: false), findsNothing);
        expect(find.text(l10n.safetyNumbersUnverified), findsOneWidget);

        // How to compare is still said, for the new number: between it and
        // the decision.
        final newNumber = find.ancestor(
          of: find.text(l10n.safetyNumbersCardLabelNew),
          matching: find.byType(SafetyNumberCard),
        );
        final howTo = findCopy(l10n.safetyNumbersDetailBody);
        expect(howTo, findsOneWidget);
        expect(tester.getRect(newNumber).bottom, lessThanOrEqualTo(top(tester, howTo)));
        expect(tester.getRect(howTo).bottom, lessThanOrEqualTo(top(tester, decide)));
      });
    });

    testWidgets('that cannot be worked out says so in the app\'s words, not in the error\'s', (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/conv-nobody', body: (world) async {
        await awaitSafetyNumber(tester);
        expect(find.byType(VeilErrorState), findsOneWidget);
        expect(findCopy(l10n.safetyNumbersErrorBody), findsOneWidget);

        // Trying again fails the same way: the page says so again, and the
        // error goes nowhere else.
        await tester.tap(find.text(l10n.safetyNumbersRetry));
        await pumpFrames(tester, frames: 3);
        await awaitSafetyNumber(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(VeilErrorState), findsOneWidget);
      });
    });

    testWidgets('of a group: the members follow a few words, no panel', (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/$groupConversationId', withGroup: true,
          body: (world) async {
        await awaitSafetyNumber(tester);
        expectNoDashboard();
        expect(find.byType(VeilScreenIntro), findsOneWidget);
        expectInReach(tester, find.byType(VeilListTileCard));
      });
    });
  });

  group('security status', () {
    testWidgets('says first what needs a look, then shows the rows in groups', (tester) async {
      await withPhoneApp(tester, identities, location: '/security-status', body: (world) async {
        expectNoDashboard();
        // The words on top are words, not a card with pills.
        expect(find.byType(VeilScreenIntro), findsOneWidget);
        expect(find.text(l10n.securityStatusPillPrivateBeta, skipOffstage: false), findsNothing);

        // Every row that warns is named in the notice on top, and only those.
        final groups = <SecuritySignalGroup>{};
        void collect() => groups.addAll(tester.widgetList(find.byType(SecuritySignalGroup, skipOffstage: false)));
        final notice = find.byType(VeilInlineBanner);
        expect(notice, findsOneWidget);
        expectInReach(tester, notice);
        final said = tester.widget<VeilInlineBanner>(notice);
        final firstGroup = find.byType(SecuritySignalGroup);
        expect(top(tester, notice), lessThan(top(tester, firstGroup)));
        expect(top(tester, firstGroup), lessThan(screenHeight(tester)), reason: 'rows start on the first screenful');

        collect();
        await scrollToEnd(tester, onPage: (_) async => collect());
        expect(groups, hasLength(3));
        final warning = [
          for (final group in groups)
            for (final signal in group.signals)
              if (signal.needsAttention) signal.label,
        ];
        expect(warning, isNotEmpty, reason: 'this build pins no TLS key');
        expect(said.message.split(' · ').toSet(), warning.toSet());
        expect(said.title, l10n.securityStatusAttentionTitle(warning.length));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('its headline breaks between sentences, never inside one', (tester) async {
      await withPhoneApp(tester, identities, location: '/security-status', body: (world) async {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: findCopy(l10n.securityStatusHeroTitle), matching: find.byType(RichText)),
        );
        final shown = paragraph.text.toPlainText();
        final sentences = RegExp(r'[^.]+\.').allMatches(shown).toList();
        expect(sentences, hasLength(3));
        final lines = <double>{};
        for (final sentence in sentences) {
          final start = sentence.start + (sentence[0]!.length - sentence[0]!.trimLeft().length);
          final tops = {
            for (final box in paragraph.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: sentence.end)))
              box.top,
          };
          expect(tops, hasLength(1), reason: '"${sentence[0]}" is split over lines in "$shown"');
          lines.addAll(tops);
        }
        expect(lines.length, greaterThan(1), reason: 'the headline is meant to wrap here');
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
            padding: const EdgeInsets.all(VeilSpace.lg),
            child: SecuritySignalGroup(
              title: l10n.securityStatusSectionProductRules,
              signals: [
                SecuritySignal(
                  label: l10n.securityStatusCryptoAdapter,
                  value: l10n.securityStatusCryptoLibsignal,
                  detail: l10n.securityStatusCryptoLibsignalDetail('libsignal'),
                  tone: SecuritySignalTone.neutral,
                ),
                SecuritySignal(
                  label: l10n.securityStatusLocalWipe,
                  value: l10n.securityStatusAvailable,
                  detail: l10n.securityStatusLocalWipeDetail,
                  tone: SecuritySignalTone.good,
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
      final label = tester.getRect(find.text(l10n.securityStatusCryptoAdapter));
      final state = tester.getRect(find.widgetWithText(VeilStatusPill, l10n.securityStatusCryptoLibsignal));
      expect(lineCount(l10n.securityStatusCryptoAdapter), closeTo(1, 0.2));
      expect(paragraphOf(l10n.securityStatusCryptoLibsignal).didExceedMaxLines, isFalse);
      expect(state.top, greaterThanOrEqualTo(label.bottom));
      expect(state.left, closeTo(label.left, 1));

      // A short state stays at the end of its label's line.
      final shortLabel = tester.getRect(find.text(l10n.securityStatusLocalWipe));
      final shortState = tester.getRect(find.widgetWithText(VeilStatusPill, l10n.securityStatusAvailable));
      expect(shortState.left, greaterThan(shortLabel.right));
      expect(shortState.center.dy, closeTo(shortLabel.center.dy, 4));
      final card = tester.getRect(find.byType(VeilSurfaceCard));
      expect(card.right - shortState.right, closeTo(VeilSpace.md, 1), reason: 'at the end of the row');
    });

    test('counts what needs a look in words that agree with the number', () {
      expect(l10n.securityStatusAttentionTitle(1), '1 item needs a look');
      expect(l10n.securityStatusAttentionTitle(3), '3 items need a look');
      expect(l10n.appLockStatusPinMismatchAttempts(1), 'PIN mismatch. 1 attempt left before temporary lock.');
      expect(l10n.appLockStatusPinMismatchAttempts(2), 'PIN mismatch. 2 attempts left before temporary lock.');
    });
  });
}
