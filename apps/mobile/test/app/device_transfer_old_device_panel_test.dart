import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_old_device_panel.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_step.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/step_row.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

// The old device's three steps, and the controls of the step in hand under
// them, in the states a screenshot run does not reach: a session that ran
// out, what an approval came to, and a failure.

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
  TextEditingController? claim,
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
          claimIdController: claim ?? TextEditingController(),
          onIssue: () {},
          onApprove: () {},
          onCopyCode: () {},
          onClear: () {},
          now: _now,
          stepsFooter: _en.deviceTransferOldPhoneNeeded,
        ),
      ),
    ),
  ));
}

List<StepRow> _steps(WidgetTester tester) => tester.widgetList<StepRow>(find.byType(StepRow)).toList();

// The step [finder]'s words stand in.
int _stepOf(WidgetTester tester, Finder finder) =>
    tester.widget<StepRow>(find.ancestor(of: finder, matching: find.byType(StepRow))).number;

// Whether [finder]'s widget is one of the controls under the steps.
bool _underTheSteps(WidgetTester tester, Finder finder) =>
    find.ancestor(of: finder, matching: find.byType(StepRow)).evaluate().isEmpty &&
    tester.getRect(finder).top >= tester.getRect(find.byType(StepRow).last).bottom;

void main() {
  testWidgets('a session that ran out hides its code and asks for a new one with the first step', (tester) async {
    await _pump(tester, status: const TransferTokenReady(), expiresAt: _now.subtract(const Duration(minutes: 1)));

    expect([for (final step in _steps(tester)) step.state],
        [StepRowState.current, StepRowState.upcoming, StepRowState.upcoming]);
    // Said in the first step, with the button for a new code under the steps.
    final issue = find.widgetWithText(FilledButton, _en.deviceTransferIssueToken);
    expect(_stepOf(tester, find.text(_en.deviceTransferOldIssueExpiredBody)), 1);
    expect(_stepOf(tester, find.text(_en.deviceTransferStatusExpired)), 1);
    expect(_underTheSteps(tester, issue), isTrue);
    expect(tester.widget<FilledButton>(issue).onPressed, isNotNull);
    // A code nobody can use is not offered for copying, and nothing is
    // approved against it.
    expect(find.text(_code), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byTooltip(_en.deviceTransferCopyPayload), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(_en.deviceTransferApproveClaim), findsNothing);
    expect(find.text(_en.deviceTransferStatusTokenReady), findsNothing, reason: 'it is not ready any more');
    // That the old phone is needed is said once, under the steps.
    expect(find.text(_en.deviceTransferOldPhoneNeeded), findsOneWidget);
  });

  testWidgets('a live session says in the first step that its code is ready, and shows it under the steps',
      (tester) async {
    await _pump(tester, status: const TransferTokenReady(), expiresAt: _now.add(const Duration(minutes: 4)));

    // One step is in hand: handing the code over, until the new phone's
    // code is typed in.
    expect([for (final step in _steps(tester)) step.state],
        [StepRowState.done, StepRowState.current, StepRowState.upcoming]);
    expect(_stepOf(tester, find.text(_en.deviceTransferStatusTokenReady)), 1);
    final code = find.text(_code);
    expect(_underTheSteps(tester, code), isTrue);
    final copy = find.byTooltip(_en.deviceTransferCopyPayload);
    expect(copy, findsOneWidget);
    expect(tester.getSize(copy).height, greaterThanOrEqualTo(44));
    expect(find.widgetWithText(FilledButton, _en.deviceTransferIssueToken), findsNothing);
    expect(find.text(_en.deviceTransferStatusExpired), findsNothing);
    // The claim field, then what approving leads to, then the button.
    final field = find.byType(TextField);
    final consequence = find.text(_en.deviceTransferApproveFooter);
    final approve = find.widgetWithText(FilledButton, _en.deviceTransferApproveClaim);
    expect(tester.getRect(code).bottom, lessThanOrEqualTo(tester.getRect(field).top));
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(tester.getRect(consequence).top));
    expect(tester.getRect(consequence).bottom, lessThanOrEqualTo(tester.getRect(approve).top));
  });

  testWidgets('once the new phone\'s code is typed in, approving is the step in hand', (tester) async {
    final claim = TextEditingController();
    await _pump(tester, status: const TransferTokenReady(), expiresAt: _now.add(const Duration(minutes: 4)), claim: claim);

    await tester.enterText(find.byType(TextField), 'claim-7');
    await tester.pump();
    expect([for (final step in _steps(tester)) step.state],
        [StepRowState.done, StepRowState.done, StepRowState.current]);

    // Cleared, it is the code's turn again.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect([for (final step in _steps(tester)) step.state],
        [StepRowState.done, StepRowState.current, StepRowState.upcoming]);
  });

  testWidgets('what an approval came to is said under the button that approves, in green', (tester) async {
    await _pump(
      tester,
      status: const TransferClaimApproved('claim-7', 'AB12 CD34'),
      expiresAt: _now.add(const Duration(minutes: 4)),
    );

    final approved = find.text(_en.deviceTransferStatusClaimApproved('claim-7', 'AB12 CD34'));
    expect(approved, findsOneWidget);
    final approve = find.widgetWithText(FilledButton, _en.deviceTransferApproveClaim);
    expect(tester.getRect(approve).bottom, lessThanOrEqualTo(tester.getRect(approved).top));
    final context = tester.element(approved);
    expect(tester.widget<Text>(approved).style?.color, context.veilPalette.success);
    expect(find.byType(VeilNotice), findsNothing, reason: 'good news is a line, not a notice');
    // This phone's part is done.
    expect([for (final step in _steps(tester)) step.state],
        [StepRowState.done, StepRowState.done, StepRowState.done]);
  });

  // A failure used to stand above the first step, a screenful away from
  // the button that was tapped.
  testWidgets('a failed approval is said under the button that approves', (tester) async {
    await _pump(
      tester,
      // An earlier answer of the relay, which the failure replaces.
      status: const TransferClaimNotWaiting('claim-7'),
      expiresAt: _now.add(const Duration(minutes: 4)),
      errorMessage: 'The relay did not answer.',
    );

    final failure = find.text('The relay did not answer.');
    expect(failure, findsOneWidget);
    // One line in the danger colour, not a box: there is nothing to decide.
    expect(find.byType(VeilNotice), findsNothing);
    expect(tester.widget<Text>(failure).style?.color, tester.element(failure).veilPalette.danger);
    expect(find.text(_en.deviceTransferFailedTitle), findsNothing);
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
    expect(tester.getRect(find.byType(StepRow).first).top, 0);
    expect(tester.getRect(find.byType(TransferStepResult)).top, greaterThan(640), reason: 'below the fold, unmoved');
  });

  testWidgets('a failure to issue is said above the button that issues', (tester) async {
    await _pump(tester, status: null, expiresAt: null, errorMessage: 'The relay did not answer.');

    final failure = find.text('The relay did not answer.');
    expect(failure, findsOneWidget);
    expect(find.byType(VeilNotice), findsNothing, reason: 'a line, not a box');
    expect(_underTheSteps(tester, failure), isTrue);
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
          body: StepRow(
            number: 2,
            title: title,
            state: StepRowState.current,
            body: 'This device creates its own keys and sends a claim that only the old device can approve.',
            status: status,
            statusTone: VeilTone.danger,
          ),
        ),
      ));
    }

    // The width the step's words were given, and the widest they could be:
    // the row less its padding, the disc and the gap after it.
    double given(WidgetTester tester) => tester
        .renderObject<RenderBox>(
          find.descendant(of: find.textContaining('This device creates'), matching: find.byType(RichText)),
        )
        .constraints
        .maxWidth;
    double whole(WidgetTester tester) =>
        tester.getSize(find.byType(StepRow)).width - 2 * VeilSpace.md - StepRow.disc - VeilSpace.sm;

    testWidgets('puts a state that does not fit beside the title under it, and its words keep the whole width',
        (tester) async {
      await pumpStep(tester, width: 320, title: 'Register this device', status: 'Claim expired');
      expect(tester.takeException(), isNull);

      final title = tester.getRect(find.text('Register this device'));
      final state = tester.getRect(find.text('Claim expired'));
      final words = tester.getRect(find.textContaining('This device creates'));
      expect(state.top, greaterThanOrEqualTo(title.bottom), reason: 'under the title');
      expect(state.left, closeTo(title.left, 1));
      expect(state.bottom, lessThanOrEqualTo(words.top), reason: 'above the words, not beside them');
      expect(given(tester), closeTo(whole(tester), 2.5));
    });

    testWidgets('keeps a state that fits on the title\'s line, at its end', (tester) async {
      await pumpStep(tester, width: 400, title: 'Issue', status: 'Expired');
      expect(tester.takeException(), isNull);

      final title = tester.getRect(find.text('Issue'));
      final state = tester.getRect(find.text('Expired'));
      final row = tester.getRect(find.byType(StepRow));
      final words = tester.getRect(find.textContaining('This device creates'));
      expect(state.center.dy, closeTo(title.center.dy, 2));
      expect(state.left, greaterThan(title.right));
      expect(row.right - state.right, closeTo(VeilSpace.md, 2), reason: 'at the end of the line');
      expect(state.bottom, lessThanOrEqualTo(words.top));
      expect(given(tester), closeTo(whole(tester), 2.5));
    });
  });
}
