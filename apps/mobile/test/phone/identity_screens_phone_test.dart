import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/errors/user_facing_error.dart';
import 'package:veil_mobile/src/features/auth/presentation/choose_handle_screen.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/brand_mark.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/onboarding_warning_screen.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_number_cards.dart';
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
  // time moves forward. (The page shows a spinner and one line until it is.)
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
    testWidgets('shows the mark alone, a spinner only after a second, and no words', (tester) async {
      usePhoneView(tester, phoneSmall);
      final world = await LayoutWorld.create(identities: identities, account: signedOut, locale: 'en', bootstrapping: true);
      try {
        await tester.pumpWidget(world.app(location: '/splash'));
        await pumpFrames(tester, frames: 4);
        expect(find.byType(BrandMark), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'a quick start shows the mark alone');
        expect(find.byType(Text), findsNothing, reason: 'the splash has no text');
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'a slow start shows a spinner');
        expect(find.byType(Text), findsNothing, reason: 'the splash has no text');
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
        expect(find.textContaining('gone for good', skipOffstage: false), findsOneWidget, reason: 'the loss sentence');
        expect(find.textContaining("can't be recovered", skipOffstage: false), findsOneWidget,
            reason: 'the box that says it was understood');
        // Plain sentences: no glyph before each line.
        expect(find.byType(Icon, skipOffstage: false), findsNothing);
        expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);

        final box = find.widgetWithText(CheckboxListTile, l10n.onboardingWarnAgreeCheckbox);
        final proceed = find.widgetWithText(FilledButton, l10n.commonContinue);
        expectInReach(tester, box);
        expectInReach(tester, proceed);
        expect(tester.widget<FilledButton>(proceed).onPressed, isNull, reason: 'not before the box is ticked');
        await tester.tap(proceed);
        await pumpFrames(tester, frames: 3);
        expect(find.byType(ChooseHandleScreen), findsNothing);

        await tester.tap(box);
        await tester.pump();
        expect(tester.widget<FilledButton>(proceed).onPressed, isNotNull);
        await tester.tap(proceed);
        await pumpFrames(tester, frames: 4);
        expect(find.byType(ChooseHandleScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('choose a handle', () {
    testWidgets('is the handle field, "Create account" and one text button, and nothing else', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/choose-handle', account: signedOut,
          body: (world) async {
        final field = find.byType(TextField);
        final create = find.widgetWithText(FilledButton, l10n.authHandleBindCta);
        final transfer = find.widgetWithText(TextButton, l10n.authCreateTransferLabel);
        expectInReach(tester, field);
        expectInReach(tester, create);
        expectInReach(tester, transfer);
        expect(field, findsOneWidget);
        expect(findCopy(l10n.authHandleFindCaption), findsOneWidget);
        expect(top(tester, field), lessThan(top(tester, create)));
        expect(top(tester, create), lessThan(top(tester, transfer)));
        expect(find.byType(VeilNotice), findsNothing);
        // Before you start already said what losing the phone means.
        expect(find.textContaining('recover'), findsNothing);
        // Focused from the start, as Signal's username screen: the "@" and
        // the hint show before a tap.
        expect(tester.widget<TextField>(field).autofocus, isTrue);
        expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a handle with characters no account can have is the field error, and cannot be sent',
        (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/choose-handle', account: signedOut,
          body: (world) async {
        TextField field() => tester.widget<TextField>(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'Sam Rivera');
        await pumpFrames(tester, frames: 2);
        expect(field().decoration?.errorText, l10n.authHandleInvalid);
        expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10n.authHandleBindCta)).onPressed, isNull);
        await tester.enterText(find.byType(TextField), 'sam_rivera');
        await pumpFrames(tester, frames: 2);
        expect(field().decoration?.errorText, isNull);
      });
    });

    testWidgets('a failure is the field\'s error until the handle is changed, not a box', (tester) async {
      await withPhoneApp(tester, identities,
          size: phoneSmall,
          location: '/choose-handle',
          account: signedOut,
          sessionError: UserFacingErrorCode.handleTaken.sentence, body: (world) async {
        TextField field() => tester.widget<TextField>(find.byType(TextField));
        expect(field().decoration?.errorText, l10n.errorHandleTaken);
        expect(find.byType(VeilNotice), findsNothing);
        // In the helper line's place: the button stays where it was.
        expect(findCopy(l10n.authHandleFindCaption), findsNothing);
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.authHandleBindCta));

        await tester.enterText(find.byType(TextField), 'sam');
        await pumpFrames(tester, frames: 2);
        expect(field().decoration?.errorText, isNull);
        expect(findCopy(l10n.errorHandleTaken), findsNothing);
        expect(findCopy(l10n.authHandleFindCaption), findsOneWidget);
      });
    });
  });

  group('device transfer on the new device', () {
    testWidgets('one screen: the code, this phone\'s name and one "Continue"; no switch between phones, no steps',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', account: signedOut, body: (world) async {
        expect(find.text(l10n.deviceTransferNewTitle), findsOneWidget);
        expect(find.byType(SegmentedButton<Object>), findsNothing);
        final code = find.widgetWithText(TextField, l10n.deviceTransferPayloadInputLabel);
        final name = find.byType(TextField).last;
        final proceed = find.widgetWithText(FilledButton, l10n.commonContinue);
        expectInReach(tester, code);
        expectInReach(tester, name);
        expectInReach(tester, proceed);
        expect(tester.widget<TextField>(code).decoration!.hintText, l10n.deviceTransferPayloadHint);
        expect(tester.widget<TextField>(name).controller!.text, l10n.authDefaultDeviceName);
        expect(top(tester, code), lessThan(top(tester, name)));
        expect(top(tester, name), lessThan(top(tester, proceed)));
        expect(find.byType(FilledButton), findsOneWidget, reason: 'reading the code and registering are one step');
        expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);
        // Before you start already said what losing the old phone means.
        expect(find.textContaining('If it is gone'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a code that is not one is refused under the button that took it', (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', account: signedOut, body: (world) async {
        await tester.enterText(find.widgetWithText(TextField, l10n.deviceTransferPayloadInputLabel), 'not a code');
        final proceed = find.widgetWithText(FilledButton, l10n.commonContinue);
        await tester.tap(proceed);
        await pumpFrames(tester, frames: 3);
        final refusal = find.text(l10n.deviceTransferPayloadInvalid);
        expect(refusal, findsOneWidget);
        expect(top(tester, refusal), greaterThanOrEqualTo(tester.getRect(proceed).bottom));
        expectInReach(tester, proceed);
        expect(find.byKey(const ValueKey('transfer-claim-code')), findsNothing);
      });
    });
  });

  group('device transfer on the old device', () {
    testWidgets('before a code is issued: three numbered lines and "Get code", and nothing asks for input',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/device-transfer', body: (world) async {
        expect(find.text(l10n.deviceTransferTitle), findsOneWidget);
        expect(find.byType(SegmentedButton<Object>), findsNothing);
        for (final line in [l10n.deviceTransferOldStep1, l10n.deviceTransferOldStep2, l10n.deviceTransferOldStep3]) {
          expectInReach(tester, find.text(line));
        }
        expectInReach(tester, find.widgetWithText(FilledButton, l10n.deviceTransferIssueToken));
        expect(find.byType(TextField, skipOffstage: false), findsNothing);
        expect(find.byType(FilledButton, skipOffstage: false), findsOneWidget);
        expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('with a code issued: the code, "Copy code", how long it holds, then the new phone\'s code and Approve',
        (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await withPhoneApp(tester, identities, location: '/device-transfer', transferStarted: true, body: (world) async {
        expectInReach(tester, find.text(l10n.deviceTransferOldHandTitle));
        final copy = find.widgetWithText(OutlinedButton, l10n.deviceTransferCopyPayload);
        expectInReach(tester, copy);
        expect(tester.getSize(copy).height, greaterThanOrEqualTo(44));
        await tester.tap(copy);
        await pumpFrames(tester, frames: 2);
        expect(copied, hasLength(1));
        expect(copied.single, startsWith('VEIL_TRANSFER::'));
        expect(findCopy(l10n.deviceTransferPayloadCopied), findsOneWidget);

        // The field starts on the first screenful; Approve is under it.
        final claim = find.byType(TextField, skipOffstage: false);
        expect(claim, findsOneWidget);
        expect(top(tester, claim), lessThan(screenHeight(tester)));
        final approve = find.text(l10n.deviceTransferApproveClaim, skipOffstage: false);
        await tester.dragUntilVisible(approve, find.byType(ListView), const Offset(0, -200));
        await pumpFrames(tester, frames: 2);
        expect(top(tester, claim), lessThan(top(tester, approve)));
        // What approving leads to is said in the dialog Approve opens.
        expect(findCopy(l10n.deviceTransferApproveBody('x').split('x').last, skipOffstage: false), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('safety number', () {
    // "Check these numbers match {name}'s phone, …", whoever it is about.
    final howToParts = l10n.safetyNumbersDetailBody('\u0000').split('\u0000');
    Finder howTo({bool skipOffstage = true}) => find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data ?? '').startsWith(howToParts.first) &&
              (widget.data ?? '').endsWith(howToParts.last),
          skipOffstage: skipOffstage,
        );

    testWidgets('with no number yet: says so, and offers no keys to renew', (tester) async {
      await withPhoneApp(tester, identities, size: phoneMedium, location: '/safety-numbers/$emptyChatConversationId',
          body: (world) async {
        await awaitSafetyNumber(tester);
        expect(find.text(l10n.safetyNumbersNoPinTitle), findsOneWidget);
        expect(find.byType(SafetyNumberCard), findsNothing);
        expect(find.text(l10n.safetyNumbersRotateButton, skipOffstage: false), findsNothing,
            reason: 'there is no session to renew');
      });
    });

    testWidgets('of a contact not yet verified: who, the number, one sentence, "Mark as verified", then the codes',
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
        final copy = find.byKey(const ValueKey('safety-copy-code'));
        final paste = find.byKey(const ValueKey('safety-paste-code'));
        expectInReach(tester, copy);
        expectInReach(tester, paste);
        expect(tester.widget<TextButton>(copy).child, isA<Text>());
        expect(top(tester, header), lessThan(top(tester, find.byType(SafetyNumberCard))));
        expect(top(tester, find.byType(SafetyNumberCard)), lessThan(top(tester, mark)));
        expect(top(tester, mark), lessThan(top(tester, copy)));
        expect(top(tester, copy), closeTo(top(tester, paste), 1), reason: 'one row of two text buttons');
        // No QR code: no app here scans one.
        expect(find.byType(Image, skipOffstage: false), findsNothing);

        // The digits on the page, with no label over them.
        expect(
          find.descendant(of: find.byType(SafetyNumberCard), matching: find.textContaining(RegExp('[A-Za-z]'))),
          findsNothing,
        );
        // How to compare is said once, with their name, under the number it
        // is about and above the button that records the comparison.
        expect(howTo(), findsOneWidget);
        expect(tester.widget<Text>(howTo()).data, contains(peerNames['priya']!));
        expect(tester.getRect(find.byType(SafetyNumberCard)).bottom, lessThanOrEqualTo(top(tester, howTo())));
        expect(tester.getRect(howTo()).bottom, lessThanOrEqualTo(top(tester, mark)));
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
        expect(findCopy(l10n.safetyNumbersChangedElsewhereBody), findsOneWidget);
        expect(top(tester, notice), lessThan(top(tester, review)));
        expect(tester.getRect(review).bottom, lessThanOrEqualTo(top(tester, current)));
        expect(findCopy(l10n.safetyNumbersCurrentNumberHeader, skipOffstage: false), findsOneWidget);
        // Nothing here compares or confirms the old key.
        expect(howTo(skipOffstage: false), findsNothing);
        expect(find.byKey(const ValueKey('safety-copy-code'), skipOffstage: false), findsNothing);
        expect(find.byKey(const ValueKey('safety-paste-code'), skipOffstage: false), findsNothing);
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
        // the decision; the codes to copy and paste follow.
        final newNumber = find.ancestor(of: newHeader, matching: find.byType(SafetyNumberCard));
        expect(howTo(), findsOneWidget);
        expect(tester.getRect(newNumber).bottom, lessThanOrEqualTo(top(tester, howTo())));
        expect(tester.getRect(howTo()).bottom, lessThanOrEqualTo(top(tester, decide)));
        final copy = find.byKey(const ValueKey('safety-copy-code'), skipOffstage: false);
        expect(copy, findsOneWidget);
        expect(top(tester, decide), lessThan(top(tester, copy)));
      });
    });

    testWidgets('that cannot be worked out says so in the app\'s words, not in the error\'s', (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/conv-nobody', body: (world) async {
        await awaitSafetyNumber(tester);
        expect(findCopy(l10n.safetyNumbersErrorTitle), findsOneWidget);
        // The title and Retry say it: no line of the error under them.
        expect(find.byType(VeilEmptyState), findsOneWidget);
        expect(tester.widget<VeilEmptyState>(find.byType(VeilEmptyState)).body, isNull);

        // Trying again fails the same way: the page says so again, and the
        // error goes nowhere else.
        await tester.tap(find.text(l10n.safetyNumbersRetry));
        await pumpFrames(tester, frames: 3);
        await awaitSafetyNumber(tester);
        expect(tester.takeException(), isNull);
        expect(findCopy(l10n.safetyNumbersErrorTitle), findsOneWidget);
      });
    });

    testWidgets('of a group: a row per member, only the verified labelled, and no footer', (tester) async {
      await withPhoneApp(tester, identities, location: '/safety-numbers/$groupConversationId', withGroup: true,
          body: (world) async {
        await awaitSafetyNumber(tester);
        final rows = find.byType(VeilRow);
        expect(rows, findsNWidgets(groupMemberHandles.length));
        expectInReach(tester, rows);
        expect(top(tester, rows), lessThan(120), reason: 'the list opens under the bar');
        expect(find.text(l10n.safetyNumbersUnverified), findsNothing);
        expect(tester.widget<VeilGroup>(find.byType(VeilGroup)).footer, isNull);
      });
    });
  });

  // The Security details screen is gone (its rows are in Settings, see
  // test/security/security_status_screen_test.dart); the count stays.
  group('app lock words', () {
    test('counts in words that agree with the number', () {
      expect(l10n.appLockStatusPinMismatchAttempts(1), 'Wrong PIN. 1 try left.');
      expect(l10n.appLockStatusPinMismatchAttempts(2), 'Wrong PIN. 2 tries left.');
    });
  });
}
