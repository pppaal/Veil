import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final world = await LayoutWorld.create(identities: identities, account: signedOut, locale: 'ko', bootstrapping: true);
      try {
        await tester.pumpWidget(world.app(location: '/splash'));
        await pumpFrames(tester);
        final l10n = lookupAppLocalizations(const Locale('ko'));
        expectNoDashboard();
        expect(find.byType(VeilStatusPill), findsNothing);
        expect(find.text('VEIL'), findsOneWidget);
        expect(findCopy(l10n.splashBody), findsOneWidget);
        expect(findCopy(l10n.splashPreparingTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        world.dispose();
      }
    });
  });

  group('privacy consent', () {
    for (final locale in ['en', 'ko']) {
      testWidgets('the agree box and the button stay in reach while the notice scrolls ($locale)', (tester) async {
        await withPhoneApp(tester, identities, location: '/privacy-consent', account: signedOut, locale: locale,
            body: (world) async {
          final l10n = lookupAppLocalizations(Locale(locale));
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
    }

    testWidgets('consent is not given without the box: the button does nothing until it is ticked', (tester) async {
      await withPhoneApp(tester, identities, location: '/privacy-consent', account: signedOut, body: (world) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
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
    for (final locale in ['en', 'ko']) {
      testWidgets('"I understand" is in reach from the start, under the one no-recovery notice ($locale)',
          (tester) async {
        await withPhoneApp(tester, identities, location: '/onboarding', account: signedOut, locale: locale,
            body: (world) async {
          final l10n = lookupAppLocalizations(Locale(locale));
          expectNoDashboard();
          expect(find.byType(VeilStatusPill, skipOffstage: false), findsNothing);
          expectInReach(tester, find.widgetWithText(FilledButton, l10n.commonIUnderstand));
          expect(findCopy(l10n.onboardingWarnTitle), findsOneWidget);
          expect(find.byType(VeilDestructiveNotice, skipOffstage: false), findsOneWidget);
          expect(findCopy(l10n.onboardingWarnDestructiveBody, skipOffstage: false), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }

    test('Korean calls what stays on the device a key, as the consent screen does', () {
      final ko = lookupAppLocalizations(const Locale('ko'));
      // The consent lists what the server stores about a person; the keys
      // are not that, and "개인 정보" would say they were.
      expect(ko.onboardingWarnIdentityLine2, contains('개인 키'));
      expect(ko.onboardingWarnIdentityLine2, isNot(contains('개인 정보')));
      expect(ko.onboardingWarnDestructiveTitle, isNot(contains('복구 불가한 설계')));
      expect(ko.onboardingWarnDestructiveTitle, contains('복구'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.onboardingWarnIdentityLine2, contains('private keys'));
    });
  });

  group('create account', () {
    for (final locale in ['en', 'ko']) {
      testWidgets('opens on the name field, with the notice once between it and the two ways on ($locale)',
          (tester) async {
        await withPhoneApp(tester, identities, size: phoneMedium, location: '/create-account', account: signedOut,
            locale: locale, body: (world) async {
          final l10n = lookupAppLocalizations(Locale(locale));
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
    }
  });

  group('choose handle', () {
    testWidgets('opens on the handle field and the button that binds it, the steps under them', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/choose-handle', account: signedOut,
          locale: 'ko', body: (world) async {
        final l10n = lookupAppLocalizations(const Locale('ko'));
        final bind = find.widgetWithText(FilledButton, l10n.authHandleBindCta);
        expectNoDashboard();
        expect(find.byType(VeilStatusPill, skipOffstage: false), findsNothing);
        expectInReach(tester, find.byType(TextField));
        expectInReach(tester, bind);
        expect(top(tester, bind), lessThan(top(tester, find.byType(VeilStepRow))));
        // No transliterated "challenge" in the steps.
        for (final text in [l10n.authHandleStep3Title, l10n.authHandleStep3Body, l10n.authStageRequestingChallenge]) {
          expect(text, isNot(contains('챌린지')));
        }
      });
    });
  });

  group('device transfer on the new device', () {
    for (final locale in ['en', 'ko']) {
      testWidgets('three numbered steps, the code field first, then the name and "Register" ($locale)',
          (tester) async {
        await withPhoneApp(tester, identities, location: '/device-transfer', account: signedOut, locale: locale,
            body: (world) async {
          final l10n = lookupAppLocalizations(Locale(locale));
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
          // place at the top with the device's name in the user's language.
          await tester.enterText(find.byType(TextField), 'VEIL_TRANSFER::session-1::token-1');
          await tester.tap(find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload));
          await pumpFrames(tester, frames: 3);
          final after = tester.widgetList<TransferStep>(find.byType(TransferStep, skipOffstage: false)).toList();
          expect([for (final step in after) step.state],
              [TransferStepState.done, TransferStepState.current, TransferStepState.upcoming]);
          final name = tester.widget<TextField>(find.byType(TextField));
          expect(name.controller!.text, l10n.authDefaultDeviceName);
          expect(name.controller!.text, isNot('VEIL New Device'));
          expectInReach(tester, find.byType(TextField));
          expectInReach(tester, find.widgetWithText(FilledButton, l10n.deviceTransferRegisterNewDevice));
          expect(isOtherLanguage(name.controller!.text, locale), isFalse);

          // The no-fallback notice is still on the screen, once, after the steps.
          expect(find.byType(VeilDestructiveNotice, skipOffstage: false), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('a code that is not one is refused in the step that took it', (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', account: signedOut, body: (world) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
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
    for (final locale in ['en', 'ko']) {
      testWidgets('with a code issued: the code, "Copy code" on one line, then the approval ($locale)',
          (tester) async {
        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

        await withPhoneApp(tester, identities, location: '/device-transfer', locale: locale, transferStarted: true,
            body: (world) async {
          final l10n = lookupAppLocalizations(Locale(locale));
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
    }
  });

  group('safety number', () {
    testWidgets('of a contact not yet verified: the number and "Mark as verified" before the code to scan',
        (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/safety-numbers/conv-jiwoo',
          prepare: (world) async {
        // This device has talked to Jiwoo, so her identity is pinned; nobody
        // compared numbers with her yet.
        final jiwoo = world.relay.partiesByHandle['jiwoo']!;
        await tester.runAsync(
          () => world.trust.resolver.evaluate(jiwoo.userId, jiwoo.deviceId, jiwoo.identity.identityPublicKey),
        );
        return null;
      }, body: (world) async {
        await awaitSafetyNumber(tester);
        final l10n = lookupAppLocalizations(const Locale('en'));
        final mark = find.widgetWithText(FilledButton, l10n.safetyNumbersMarkVerified);
        expectNoDashboard();
        expect(find.byType(VeilScreenIntro), findsOneWidget);
        expect(find.text(l10n.safetyNumbersUnverified), findsOneWidget);
        expectInReach(tester, find.byType(SafetyNumberCard));
        expectInReach(tester, mark);
        final code = find.byType(SafetyQrCard, skipOffstage: false);
        expect(top(tester, find.byType(SafetyNumberCard)), lessThan(top(tester, mark)));
        expect(top(tester, mark), lessThan(top(tester, code)));
      });
    });

    testWidgets('with a change to review: the new number and the decision on the first screenful', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/safety-numbers/$chatConversationId',
          attention: const ChatAttention(identityChanged: true), locale: 'ko', body: (world) async {
        await awaitSafetyNumber(tester);
        final l10n = lookupAppLocalizations(const Locale('ko'));
        expectInReach(tester, find.text(l10n.safetyNumbersCardLabelNew));
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.safetyNumbersReVerify));
        expect(find.text(l10n.safetyNumbersVerified, skipOffstage: false), findsNothing);
        expect(find.text(l10n.safetyNumbersUnverified), findsOneWidget);
      });
    });

    testWidgets('that cannot be worked out says so in the language of the app, not in the error\'s', (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/conv-nobody', locale: 'ko', body: (world) async {
        await awaitSafetyNumber(tester);
        final l10n = lookupAppLocalizations(const Locale('ko'));
        expect(find.byType(VeilErrorState), findsOneWidget);
        expect(findCopy(l10n.safetyNumbersErrorBody), findsOneWidget);
        expect(otherLanguageTextsOnScreen(tester, 'ko'), isEmpty);
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
    for (final locale in ['en', 'ko']) {
      testWidgets('says first what needs a look, then shows the rows in groups ($locale)', (tester) async {
        await withPhoneApp(tester, identities, location: '/security-status', locale: locale, body: (world) async {
          final l10n = lookupAppLocalizations(Locale(locale));
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
    }

    test('counts what needs a look in words that agree with the number', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.securityStatusAttentionTitle(1), '1 item needs a look');
      expect(en.securityStatusAttentionTitle(3), '3 items need a look');
      expect(en.appLockStatusPinMismatchAttempts(1), 'PIN mismatch. 1 attempt left before temporary lock.');
      expect(en.appLockStatusPinMismatchAttempts(2), 'PIN mismatch. 2 attempts left before temporary lock.');
    });
  });

  group('the words that open a screen', () {
    testWidgets('are drawn with Korean words kept whole and read out as plain text', (tester) async {
      usePhoneView(tester, phoneSmall);
      const title = '이 기기가 당신의 신원이 됩니다.';
      const body = '사람들이 나를 찾을 때 쓸 핸들을 정하세요.';
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: VeilScreenIntro(eyebrow: '기기 귀속', title: title, body: body, trailing: SizedBox(key: Key('trailing'), width: 80, height: 20)),
        ),
      ));
      expect(findCopy(title), findsOneWidget);
      expect(findCopy(body), findsOneWidget);
      expect(tester.widget<Text>(findCopy(title)).semanticsLabel, title);
      expect(tester.widget<Text>(findCopy(title)).data, veilKeepWordsWhole(title));
      expect(tester.getSize(find.byKey(const Key('trailing'))).width, 80, reason: 'what trails the title keeps its width');
      expect(tester.takeException(), isNull);
    });
  });
}
