import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/step_row.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/phone_layout_probe.dart';
import '../support/claimed_transfer.dart';
import '../support/copy_finder.dart';

// The new device after its claim ran out, on the smallest phone. The claim
// and the transfer session share one window, so the code this device holds
// is spent: registering again on it is refused, by this device (it claims a
// session once) and by the relay (the session is over). What the user does
// next is paste a new code, so that is the step in hand, on the first
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
  testWidgets('a claim past its window opens on the step that takes a new code, its words at full width',
      (tester) async {
    final (transfer, session) = await openOnExpiredClaim(tester, locale);
    final l10n = lookupAppLocalizations(Locale(locale));
    final claimId = session.pendingTransfer!.claimId;

    final steps = tester.widgetList<StepRow>(find.byType(StepRow, skipOffstage: false)).toList();
    expect([for (final step in steps) step.number], [1, 2, 3]);
    expect([for (final step in steps) step.state],
        [StepRowState.current, StepRowState.upcoming, StepRowState.upcoming]);

    // Said once, in the first step, where the new code goes: no notice
    // above the steps.
    final expired = find.text(l10n.deviceTransferStatusExpired);
    final words = findCopy(l10n.deviceTransferNewCodeExpiredBody);
    expect(expired, findsOneWidget);
    expect(words, findsOneWidget);
    expect(find.byType(VeilNotice, skipOffstage: false), findsNothing);
    expect(tester.widget<StepRow>(find.ancestor(of: expired, matching: find.byType(StepRow))).number, 1);

    // The state stands on the title's line or under the title, above the
    // words; it takes no width from them. The paragraph gets the step's
    // width less its disc; the steps whose turn has not come are titles.
    final row = tester.getRect(find.byType(StepRow).first);
    final column = row.width - 2 * VeilSpace.md - StepRow.disc - VeilSpace.sm;
    expect(tester.getRect(expired).bottom, lessThanOrEqualTo(tester.getRect(words).top));
    expect(tester.getRect(expired).right, lessThanOrEqualTo(row.right - VeilSpace.md + 0.5));
    expect(widthGiven(tester, l10n.deviceTransferNewCodeExpiredBody), closeTo(column, 2.5));
    expect([for (final step in steps.skip(1)) step.body], [null, null]);

    // The control to use next, on the first screenful of a 360x640 phone.
    final field = find.byType(TextField);
    final use = find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload);
    expectInReach(tester, field);
    expectInReach(tester, use);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.getRect(words).bottom, lessThanOrEqualTo(tester.getRect(field).top));

    // Nothing tells the user to use the spent claim, and nothing offers to.
    for (final spent in [
      l10n.deviceTransferNewCompleteBody,
      l10n.deviceTransferNewCompleteNote,
      l10n.deviceTransferClaimCode(claimId),
      l10n.deviceTransferRegisterNewDevice,
      l10n.deviceTransferCompleteOnDevice,
    ]) {
      expect(findCopy(spent, skipOffstage: false), findsNothing, reason: spent);
    }
    // (The claim's code is selectable text, which the finder above skips.)
    expect(find.byType(SelectableText, skipOffstage: false), findsNothing);
    expect(find.byType(FilledButton, skipOffstage: false), findsOneWidget);

    expect(tester.takeException(), isNull);
    expect(transfer.relay.callsTo('POST /device-transfer/claim'), 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a new code after an expired claim: "Register" is in reach, and registering claims again',
      (tester) async {
    final (transfer, session) = await openOnExpiredClaim(tester, locale);
    final l10n = lookupAppLocalizations(Locale(locale));
    final spentClaim = session.pendingTransfer!.claimId;
    final spentCode = transfer.code;

    // The spent code is refused where it was typed, and changes nothing.
    await tester.enterText(find.byType(TextField), spentCode);
    await tester.tap(find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload));
    await pumpFrames(tester, frames: 3);
    final refusal = findCopy(l10n.deviceTransferCodeExpired);
    expect(refusal, findsOneWidget);
    // Under the button that was tapped; the field and the button stay put.
    final use = find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload);
    expect(tester.getRect(refusal).top, greaterThanOrEqualTo(tester.getRect(use).bottom));
    expectInReach(tester, use);
    expect(findCopy(l10n.deviceTransferRegisterNewDevice, skipOffstage: false), findsNothing);

    // The old device issues another code; this device reads it.
    await tester.runAsync(transfer.oldDevice.initTransfer);
    expect(transfer.code, isNot(spentCode));
    await tester.enterText(find.byType(TextField), transfer.code);
    await tester.tap(find.widgetWithText(FilledButton, l10n.deviceTransferImportPayload));
    await pumpFrames(tester, frames: 3);

    var steps = tester.widgetList<StepRow>(find.byType(StepRow, skipOffstage: false)).toList();
    expect([for (final step in steps) step.state],
        [StepRowState.done, StepRowState.current, StepRowState.upcoming]);
    expect(find.text(l10n.deviceTransferStatusExpired, skipOffstage: false), findsNothing,
        reason: 'nothing is expired any more');
    expect(findCopy(l10n.deviceTransferCodeExpired, skipOffstage: false), findsNothing);
    final register = find.widgetWithText(FilledButton, l10n.deviceTransferRegisterNewDevice);
    expectInReach(tester, find.byType(TextField));
    expectInReach(tester, register);

    // Registering goes to the relay this time, and the new claim replaces
    // the spent one.
    await tester.tap(register);
    await pumpUntil(tester, () => session.pendingTransfer?.claimId != spentClaim);
    await pumpFrames(tester, frames: 3);
    expect(transfer.relay.callsTo('POST /device-transfer/claim'), 2);
    steps = tester.widgetList<StepRow>(find.byType(StepRow, skipOffstage: false)).toList();
    expect([for (final step in steps) step.state],
        [StepRowState.done, StepRowState.done, StepRowState.current]);
    expect(find.text(l10n.deviceTransferClaimCode(session.pendingTransfer!.claimId)), findsOneWidget);
    expect(findCopy(l10n.deviceTransferNewCompleteBody), findsOneWidget);
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
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(transfer.app(session));
    await pumpFrames(tester, frames: 3);

    // Still live: the claim's code is shown, and the first step is closed.
    expect(find.text(l10n.deviceTransferClaimCode(session.pendingTransfer!.claimId)), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // The user reopens the first step and types the code in again; then the
    // window closes on real time, which the screen's clock follows.
    await tester.tap(find.text(l10n.deviceTransferNewCodeChange));
    await tester.pump();
    await tester.enterText(find.byType(TextField), transfer.code);
    final closesAt = session.pendingTransfer!.expiresAt;
    await tester.runAsync(
      () => Future<void>.delayed(closesAt.difference(DateTime.now()) + const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text(l10n.deviceTransferStatusExpired), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(find.text(l10n.commonCancel), findsNothing, reason: 'there is no code to go back to');
    expect(find.byType(SelectableText, skipOffstage: false), findsNothing, reason: 'the spent claim is not shown');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('"Change" on the first step can be taken back while the code still holds', (tester) async {
    usePhoneView(tester, phoneSmall);
    late ClaimedTransfer transfer;
    late AppSessionController session;
    await tester.runAsync(() async {
      transfer = await ClaimedTransfer.create();
      session = await transfer.restart();
    });
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(transfer.app(session));
    await pumpFrames(tester, frames: 3);

    await tester.tap(find.text(l10n.deviceTransferNewCodeChange));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    // A code that is not one, refused in the step.
    await tester.enterText(find.byType(TextField), 'not a code');
    await tester.tap(find.text(l10n.deviceTransferImportPayload));
    await tester.pump();
    expect(find.text(l10n.deviceTransferPayloadInvalid), findsOneWidget);

    final back = find.widgetWithText(TextButton, l10n.commonCancel);
    expect(back, findsOneWidget);
    expect(tester.getSize(back).height, greaterThanOrEqualTo(44));
    await tester.tap(back);
    await tester.pump();

    // The step is closed again over the code it had, and its refusal went
    // with it; the claim is as it was.
    expect(find.byType(TextField), findsNothing);
    expect(find.text(l10n.deviceTransferPayloadInvalid, skipOffstage: false), findsNothing);
    expect(find.text(l10n.deviceTransferNewCodeChange), findsOneWidget);
    expect(find.text(l10n.deviceTransferClaimCode(session.pendingTransfer!.claimId)), findsOneWidget);
    expect(transfer.relay.callsTo('POST /device-transfer/claim'), 1);

    // Reopened later, the step does not repeat a refusal that was dismissed.
    await tester.tap(find.text(l10n.deviceTransferNewCodeChange));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(l10n.deviceTransferPayloadInvalid, skipOffstage: false), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
