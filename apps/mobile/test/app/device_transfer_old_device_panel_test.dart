import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_old_device_panel.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_step.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

// The old device's three steps in the states a screenshot run does not
// reach: a session that ran out, and what an approval came to.

final _en = lookupAppLocalizations(const Locale('en'));
final _now = DateTime(2026, 4, 2, 12);
const _code = 'VEIL_TRANSFER::session-1::token-1';

Future<void> _pump(
  WidgetTester tester, {
  required TransferStatus? status,
  required DateTime expiresAt,
  String? errorMessage,
}) {
  tester.view
    ..physicalSize = const Size(400, 3000)
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
          transferSessionId: 'session-1',
          transferCode: _code,
          status: status,
          transferExpiresAt: expiresAt,
          transferExpired: !expiresAt.isAfter(_now),
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

  testWidgets('a failure of the relay is said above the steps', (tester) async {
    await _pump(
      tester,
      status: const TransferTokenReady(),
      expiresAt: _now.add(const Duration(minutes: 4)),
      errorMessage: 'The relay did not answer.',
    );

    final failure = find.text('The relay did not answer.');
    expect(failure, findsOneWidget);
    expect(find.ancestor(of: failure, matching: find.byType(TransferStep)), findsNothing);
    expect(tester.getRect(failure).bottom, lessThanOrEqualTo(tester.getRect(find.byType(TransferStep).first).top));
  });
}
