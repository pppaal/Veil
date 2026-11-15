import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_old_device_panel.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_step.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

// The old device's three steps in the states a screenshot run does not
// reach: a session that ran out, what an approval came to, and a failure.

final _en = lookupAppLocalizations(const Locale('en'));
final _now = DateTime(2026, 4, 2, 12);
const _code = 'VEIL_TRANSFER::session-1::token-1';

// [expiresAt] null is a device that has no session open.
Future<void> _pump(
  WidgetTester tester, {
  required TransferStatus? status,
  required DateTime? expiresAt,
  String? errorMessage,
  Size view = const Size(400, 3000),
}) {
  tester.view
    ..physicalSize = view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(MaterialApp(
    theme: VeilTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: TransferOldDevicePanel(
          isAuthenticated: true,
          isBusy: false,
          transferSessionId: expiresAt == null ? null : 'session-1',
          transferCode: expiresAt == null ? null : _code,
          status: status,
          transferExpiresAt: expiresAt,
          transferExpired: expiresAt != null && !expiresAt.isAfter(_now),
          errorMessage: errorMessage,
          claimIdController: TextEditingController(),
          onIssue: () {},
          onApprove: () {},
          onCopyCode: () {},
          onClear: () {},
          now: _now,
        ),
      ),
    ),
  ));
}

List<TransferStep> _steps(WidgetTester tester) => tester.widgetList<TransferStep>(find.byType(TransferStep)).toList();

// The step [finder]'s widget stands in.
int _stepOf(WidgetTester tester, Finder finder) =>
    tester.widget<TransferStep>(find.ancestor(of: finder, matching: find.byType(TransferStep))).number;

void main() {
  testWidgets('a session that ran out hides its code and asks for a new one in the first step', (tester) async {
    await _pump(tester, status: const TransferTokenReady(), expiresAt: _now.subtract(const Duration(minutes: 1)));

    expect([for (final step in _steps(tester)) step.state],
        [TransferStepState.current, TransferStepState.upcoming, TransferStepState.upcoming]);
    // Said where the new code is issued, with the button for it.
    final expired = find.text(_en.deviceTransferOldIssueExpiredBody);
    final issue = find.widgetWithText(FilledButton, _en.deviceTransferIssueToken);
    expect(_stepOf(tester, expired), 1);
    expect(_stepOf(tester, find.text(_en.deviceTransferStatusExpired)), 1);
    expect(_stepOf(tester, issue), 1);
    expect(tester.widget<FilledButton>(issue).onPressed, isNotNull);
    // A code nobody can use is not offered for copying, and nothing is
    // approved against it.
    expect(find.text(_code), findsNothing);
    expect(find.byType(TransferCodeBox), findsNothing);
    expect(find.text(_en.deviceTransferCopyPayload), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(_en.deviceTransferApproveClaim), findsNothing);
    expect(find.text(_en.deviceTransferStatusTokenReady), findsNothing, reason: 'it is not ready any more');
  });

  testWidgets('a live session says in the first step that its code is ready, and shows it in the second',
      (tester) async {
    await _pump(tester, status: const TransferTokenReady(), expiresAt: _now.add(const Duration(minutes: 4)));

    expect([for (final step in _steps(tester)) step.state],
        [TransferStepState.done, TransferStepState.current, TransferStepState.current]);
    expect(_stepOf(tester, find.text(_en.deviceTransferStatusTokenReady)), 1);
    expect(_stepOf(tester, find.text(_code)), 2);
    expect(find.widgetWithText(FilledButton, _en.deviceTransferIssueToken), findsNothing);
    expect(find.byType(VeilStatusPill), findsNothing);
  });

  testWidgets('what an approval came to is said in the step that approves', (tester) async {
    await _pump(
      tester,
      status: const TransferClaimApproved('claim-7', 'AB12 CD34'),
      expiresAt: _now.add(const Duration(minutes: 4)),
    );

    final approved = find.text(_en.deviceTransferStatusClaimApproved('claim-7', 'AB12 CD34'));
    expect(approved, findsOneWidget);
    expect(_stepOf(tester, approved), 3);
    final approve = find.widgetWithText(FilledButton, _en.deviceTransferApproveClaim);
    expect(tester.getRect(approve).bottom, lessThanOrEqualTo(tester.getRect(approved).top));
  });

  // A failure used to stand above the first step, a screenful away from
  // the button that was tapped.
  testWidgets('a failed approval is said in the step that approves, under its button', (tester) async {
    await _pump(
      tester,
      // An earlier answer of the relay, which the failure replaces.
      status: const TransferClaimNotWaiting('claim-7'),
      expiresAt: _now.add(const Duration(minutes: 4)),
      errorMessage: 'The relay did not answer.',
    );

    final failure = find.text('The relay did not answer.');
    expect(failure, findsOneWidget);
    expect(_stepOf(tester, failure), 3);
    expect(_stepOf(tester, find.text(_en.deviceTransferFailedTitle)), 3);
    final approve = find.widgetWithText(FilledButton, _en.deviceTransferApproveClaim);
    expect(tester.getRect(approve).bottom, lessThanOrEqualTo(tester.getRect(failure).top));
    expect(find.text(_en.deviceTransferStatusClaimNotWaiting('claim-7')), findsNothing,
        reason: 'the last thing that happened is the failure');
  });

  testWidgets('a failed approval comes into view on a phone, where the button is at the foot of the screen',
      (tester) async {
    const phone = Size(360, 640);
    final open = _now.add(const Duration(minutes: 4));
    await _pump(tester, status: const TransferTokenReady(), expiresAt: open, view: phone);
    final approve = find.widgetWithText(FilledButton, _en.deviceTransferApproveClaim);
    // The user scrolled until the button was just on screen, and tapped it.
    await Scrollable.ensureVisible(tester.element(approve), alignment: 1);
    await tester.pump();
    expect(tester.getRect(approve).bottom, closeTo(phone.height, 1));

    await _pump(tester, status: const TransferTokenReady(), expiresAt: open, view: phone, errorMessage: 'No answer.');
    await tester.pump();
    await tester.pump();

    final failure = tester.getRect(find.byType(TransferStepResult));
    expect(failure.top, greaterThanOrEqualTo(0));
    expect(failure.bottom, lessThanOrEqualTo(phone.height));
    expect(find.text('No answer.'), findsOneWidget);
    // The button it is about is still on screen above it.
    expect(tester.getRect(approve).top, greaterThanOrEqualTo(0));
  });

  testWidgets('a screen that opens with a result on it opens at its top', (tester) async {
    await _pump(
      tester,
      status: const TransferClaimApproved('claim-7', 'AB12 CD34'),
      expiresAt: _now.add(const Duration(minutes: 4)),
      view: const Size(360, 640),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, 0);
    expect(tester.getRect(find.byType(TransferStep).first).top, 0);
    expect(tester.getRect(find.byType(TransferStepResult)).top, greaterThan(640), reason: 'below the fold, unmoved');
  });

  testWidgets('a failure to issue is said in the first step, above its button', (tester) async {
    await _pump(tester, status: null, expiresAt: null, errorMessage: 'The relay did not answer.');

    final failure = find.text('The relay did not answer.');
    expect(failure, findsOneWidget);
    expect(_stepOf(tester, failure), 1);
    final issue = find.widgetWithText(FilledButton, _en.deviceTransferIssueToken);
    expect(tester.getRect(failure).bottom, lessThanOrEqualTo(tester.getRect(issue).top));
    expect(tester.widget<FilledButton>(issue).onPressed, isNotNull, reason: 'issuing can be tried again');
  });

  testWidgets('a build with no relay says so in the first step and does not offer to issue', (tester) async {
    await _pump(tester, status: const TransferNeedsApi(), expiresAt: null);

    expect(_stepOf(tester, find.text(_en.deviceTransferStatusNeedsApi)), 1);
    final issue = find.widgetWithText(FilledButton, _en.deviceTransferIssueToken);
    expect(tester.widget<FilledButton>(issue).onPressed, isNull);
  });

  group('a step', () {
    // (The test font draws every letter as a square, so a title is far
    // wider here than on a device; what is measured holds for any font.)
    Future<void> pumpStep(
      WidgetTester tester, {
      required double width,
      required String title,
      required String status,
    }) {
      tester.view
        ..physicalSize = Size(width, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(MaterialApp(
        theme: VeilTheme.dark(),
        home: Scaffold(
          body: TransferStep(
            number: 2,
            title: title,
            state: TransferStepState.current,
            body: 'This device creates its own keys and sends a claim that only the old device can approve.',
            status: status,
            statusTone: VeilBannerTone.danger,
          ),
        ),
      ));
    }

    // The width the step's words were given, and the widest they could be:
    // the card less its padding, the number and the gap after it.
    double given(WidgetTester tester) => tester
        .renderObject<RenderBox>(
          find.descendant(of: find.textContaining('This device creates'), matching: find.byType(RichText)),
        )
        .constraints
        .maxWidth;
    double whole(WidgetTester tester) =>
        tester.getSize(find.byType(VeilSurfaceCard)).width - 2 * VeilSpace.md - 28 - VeilSpace.sm;

    testWidgets('puts a state that does not fit beside the title under it, and its words keep the whole width',
        (tester) async {
      await pumpStep(tester, width: 320, title: 'Register this device', status: 'Claim expired');
      expect(tester.takeException(), isNull);

      final title = tester.getRect(find.text('Register this device'));
      final pill = tester.getRect(find.byType(VeilStatusPill));
      final words = tester.getRect(find.textContaining('This device creates'));
      expect(pill.top, greaterThanOrEqualTo(title.bottom), reason: 'under the title');
      expect(pill.left, closeTo(title.left, 1));
      expect(pill.bottom, lessThanOrEqualTo(words.top), reason: 'above the words, not beside them');
      expect(given(tester), closeTo(whole(tester), 2.5));
    });

    testWidgets('keeps a state that fits on the title\'s line, at its end', (tester) async {
      await pumpStep(tester, width: 400, title: 'Issue', status: 'Expired');
      expect(tester.takeException(), isNull);

      final title = tester.getRect(find.text('Issue'));
      final pill = tester.getRect(find.byType(VeilStatusPill));
      final card = tester.getRect(find.byType(VeilSurfaceCard));
      final words = tester.getRect(find.textContaining('This device creates'));
      expect(pill.center.dy, closeTo(title.center.dy, 2));
      expect(pill.left, greaterThan(title.right));
      expect(card.right - pill.right, closeTo(VeilSpace.md, 2), reason: 'at the end of the line');
      expect(pill.bottom, lessThanOrEqualTo(words.top));
      expect(given(tester), closeTo(whole(tester), 2.5));
    });
  });
}
