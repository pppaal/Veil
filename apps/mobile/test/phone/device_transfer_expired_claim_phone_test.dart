import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/phone_layout_probe.dart';
import '../support/claimed_transfer.dart';
import '../support/copy_finder.dart';

// The new device after its claim ran out, on the smallest phone. The claim
// and the transfer session share one window, so the code this device holds
// is spent: registering again on it is refused, by this device (it claims a
// session once) and by the relay (the session is over). What the user does
// next is paste a new code, so the first screen is back, on the first
// screenful, and nothing the spent code could be used for is offered.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadBundledFonts);

  // That the whole of [finder]'s widget is on screen where a tap reaches
  // it, without anything having been scrolled.
  void expectInReach(WidgetTester tester, Finder finder) {
    expect(finder, findsOneWidget);
    expect(whyNotWhollyTappable(tester, tester.renderObject<RenderBox>(finder)), isNull, reason: '$finder');
  }

  // The width a paragraph of the app's copy was given to lay out in.
  double widthGiven(WidgetTester tester, String copy) => tester
      .renderObject<RenderParagraph>(find.descendant(of: findCopy(copy), matching: find.byType(RichText)))
      .constraints
      .maxWidth;

  // Real time for the fake relay, frames for the screen, until [condition].
  Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 400 && !condition(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(condition(), isTrue);
  }

  Future<(ClaimedTransfer, AppSessionController)> openOnExpiredClaim(WidgetTester tester, String locale) async {
    usePhoneView(tester, phoneSmall);
    late ClaimedTransfer transfer;
    late AppSessionController session;
    await tester.runAsync(() async {
      transfer = await ClaimedTransfer.create(window: const Duration(minutes: -6));
      session = await transfer.restart();
    });
    expect(session.pendingTransfer, isNotNull);
    expect(session.pendingTransfer!.expiredAt(DateTime.now()), isTrue);
    await tester.pumpWidget(transfer.app(session, locale: locale));
    await pumpFrames(tester, frames: 3);
    return (transfer, session);
  }

  const locale = 'en';
  final l10n = lookupAppLocalizations(const Locale(locale));
  final codeField = find.widgetWithText(TextField, l10n.deviceTransferPayloadInputLabel);
  final claimCode = find.byKey(const ValueKey('transfer-claim-code'));
  Finder continueButton() => find.widgetWithText(FilledButton, l10n.commonContinue);

  testWidgets('a claim past its window opens on the first screen, which says so in one line at full width',
      (tester) async {
    final (transfer, session) = await openOnExpiredClaim(tester, locale);

    // Said once, by the button that takes the new code: no notice, no
    // stepper.
    final words = findCopy(l10n.deviceTransferNewCodeExpiredBody);
    expect(words, findsOneWidget);
    expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);
    expect(widthGiven(tester, l10n.deviceTransferNewCodeExpiredBody), closeTo(360 - 2 * VeilSpace.md, 2.5));

    // The controls to use next, on the first screenful of a 360x640 phone.
    expectInReach(tester, codeField);
    expectInReach(tester, continueButton());
    expect(tester.widget<TextField>(codeField).controller!.text, isEmpty);
    expect(tester.getRect(codeField).bottom, lessThanOrEqualTo(tester.getRect(words).top));
    expect(tester.getRect(words).bottom, lessThanOrEqualTo(tester.getRect(continueButton()).top));

    // Nothing tells the user to use the spent claim, and nothing offers to.
    for (final spent in [
      l10n.deviceTransferNewCompleteBody,
      l10n.deviceTransferNewCompleteTitle,
      l10n.deviceTransferCompleteOnDevice,
    ]) {
      expect(findCopy(spent, skipOffstage: false), findsNothing, reason: spent);
    }
    expect(claimCode, findsNothing);
    expect(find.byType(SelectableText, skipOffstage: false), findsNothing);
    expect(find.byType(FilledButton, skipOffstage: false), findsOneWidget);

    expect(tester.takeException(), isNull);
    expect(transfer.relay.callsTo('POST /device-transfer/claim'), 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a new code after an expired claim: "Continue" registers this phone again in one step', (tester) async {
    final (transfer, session) = await openOnExpiredClaim(tester, locale);
    final spentClaim = session.pendingTransfer!.claimId;
    final spentCode = transfer.code;

    // The spent code is refused where it was typed, and changes nothing.
    await tester.enterText(codeField, spentCode);
    await tester.tap(continueButton());
    await pumpFrames(tester, frames: 3);
    final refusal = findCopy(l10n.deviceTransferCodeExpired);
    expect(refusal, findsOneWidget);
    // Under the button that was tapped; the field and the button stay put.
    expect(tester.getRect(refusal).top, greaterThanOrEqualTo(tester.getRect(continueButton()).bottom));
    expectInReach(tester, continueButton());
    expect(transfer.relay.callsTo('POST /device-transfer/claim'), 1);

    // The old device issues another code; this device reads it and, in the
    // same step, registers: the relay gets a new claim.
    await tester.runAsync(transfer.oldDevice.initTransfer);
    expect(transfer.code, isNot(spentCode));
    await tester.enterText(codeField, transfer.code);
    await tester.tap(continueButton());
    await pumpUntil(tester, () => session.pendingTransfer?.claimId != spentClaim);
    await pumpFrames(tester, frames: 3);
    expect(transfer.relay.callsTo('POST /device-transfer/claim'), 2);

    // The second screen: the new claim's code, large, and one line.
    expect(find.descendant(of: claimCode, matching: find.text(session.pendingTransfer!.claimId)), findsOneWidget);
    expect(findCopy(l10n.deviceTransferNewCompleteBody), findsOneWidget);
    expect(findCopy(l10n.deviceTransferCodeExpired, skipOffstage: false), findsNothing);
    expect(codeField, findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a claim that runs out while the screen is open gives the field back empty', (tester) async {
    usePhoneView(tester, phoneSmall);
    late ClaimedTransfer transfer;
    late AppSessionController session;
    await tester.runAsync(() async {
      transfer = await ClaimedTransfer.create(window: const Duration(milliseconds: 1500));
      session = await transfer.restart();
    });
    await tester.pumpWidget(transfer.app(session));
    await pumpFrames(tester, frames: 3);

    // Still live: the claim's code is shown, and the first screen is behind.
    expect(find.text(session.pendingTransfer!.claimId), findsOneWidget);
    expect(codeField, findsNothing);

    // The user goes back to paste the code in again; then the window closes
    // on real time, which the screen's clock follows.
    await tester.tap(find.text(l10n.deviceTransferNewCodeChange));
    await tester.pump();
    await tester.enterText(codeField, transfer.code);
    final closesAt = session.pendingTransfer!.expiresAt;
    await tester.runAsync(
      () => Future<void>.delayed(closesAt.difference(DateTime.now()) + const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(findCopy(l10n.deviceTransferNewCodeExpiredBody), findsOneWidget);
    expect(tester.widget<TextField>(codeField).controller!.text, isEmpty);
    expect(find.text(l10n.commonCancel), findsNothing, reason: 'there is no claim to go back to');
    expect(find.byType(SelectableText, skipOffstage: false), findsNothing, reason: 'the spent claim is not shown');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('"Change" can be taken back while the claim still holds', (tester) async {
    usePhoneView(tester, phoneSmall);
    late ClaimedTransfer transfer;
    late AppSessionController session;
    await tester.runAsync(() async {
      transfer = await ClaimedTransfer.create();
      session = await transfer.restart();
    });
    await tester.pumpWidget(transfer.app(session));
    await pumpFrames(tester, frames: 3);

    await tester.tap(find.text(l10n.deviceTransferNewCodeChange));
    await tester.pump();
    expect(codeField, findsOneWidget);
    // A code that is not one, refused on the first screen.
    await tester.enterText(codeField, 'not a code');
    await tester.tap(continueButton());
    await tester.pump();
    expect(find.text(l10n.deviceTransferPayloadInvalid), findsOneWidget);

    final back = find.widgetWithText(TextButton, l10n.commonCancel);
    expect(back, findsOneWidget);
    expect(tester.getSize(back).height, greaterThanOrEqualTo(44));
    await tester.tap(back);
    await tester.pump();

    // Back on the claim it held, and the refusal went with the first
    // screen; the claim is as it was.
    expect(codeField, findsNothing);
    expect(find.text(l10n.deviceTransferPayloadInvalid, skipOffstage: false), findsNothing);
    expect(find.text(l10n.deviceTransferNewCodeChange), findsOneWidget);
    expect(find.text(session.pendingTransfer!.claimId), findsOneWidget);
    expect(transfer.relay.callsTo('POST /device-transfer/claim'), 1);

    // Opened again later, the first screen does not repeat a refusal that
    // was dismissed.
    await tester.tap(find.text(l10n.deviceTransferNewCodeChange));
    await tester.pump();
    expect(codeField, findsOneWidget);
    expect(find.text(l10n.deviceTransferPayloadInvalid, skipOffstage: false), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
