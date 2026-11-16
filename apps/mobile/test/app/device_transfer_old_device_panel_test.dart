import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_old_device_panel.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_step.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

// The old phone's half of a move, as Signal's: a start screen of three
// plain numbered lines and "Get code"; then the code with "Copy code", how
// long it holds, the new phone's code and "Approve". These are the states a
// screenshot run does not reach: a session that ran out, what an approval
// came to, and a failure.

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
          now: _now,
        ),
      ),
    ),
  ));
}

final _steps = [_en.deviceTransferOldStep1, _en.deviceTransferOldStep2, _en.deviceTransferOldStep3];

void main() {
  testWidgets('before a code: three plain numbered lines, then "Get code"', (tester) async {
    await _pump(tester, status: null, expiresAt: null);

    final issue = find.widgetWithText(FilledButton, _en.deviceTransferIssueToken);
    for (final (index, line) in _steps.indexed) {
      expect(find.text(line), findsOneWidget);
      expect(line, startsWith('${index + 1}. '));
      expect(tester.getRect(find.text(line)).bottom, lessThanOrEqualTo(tester.getRect(issue).top));
    }
    // Text, not a stepper: no check marks, no circles.
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.widget<FilledButton>(issue).onPressed, isNotNull);
    expect(find.text(_en.deviceTransferOldIssueExpiredBody), findsNothing);
  });

  testWidgets('a session that ran out hides its code and asks for a new one on the start screen', (tester) async {
    await _pump(tester, status: const TransferTokenReady(), expiresAt: _now.subtract(const Duration(minutes: 1)));

    final issue = find.widgetWithText(FilledButton, _en.deviceTransferIssueToken);
    final expired = find.text(_en.deviceTransferOldIssueExpiredBody);
    expect(expired, findsOneWidget);
    expect(tester.getRect(expired).bottom, lessThanOrEqualTo(tester.getRect(issue).top));
    expect(tester.widget<FilledButton>(issue).onPressed, isNotNull);
    // A code nobody can use is not offered for copying, and nothing is
    // approved against it.
    expect(find.text(_code), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text(_en.deviceTransferCopyPayload), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(_en.deviceTransferApproveClaim), findsNothing);
  });

  testWidgets('a live session: the code, "Copy code" under it, how long it holds, then the new phone\'s code and Approve',
      (tester) async {
    await _pump(tester, status: const TransferTokenReady(), expiresAt: _now.add(const Duration(minutes: 4)));

    final heading = find.text(_en.deviceTransferOldHandTitle);
    final code = find.text(_code);
    final copy = find.widgetWithText(OutlinedButton, _en.deviceTransferCopyPayload);
    final expiry = find.text(_en.deviceTransferExpires(_en.deviceTransferExpiryInMinutes(4)));
    final field = find.byType(TextField);
    final approve = find.widgetWithText(FilledButton, _en.deviceTransferApproveClaim);
    for (final finder in [heading, code, copy, expiry, field, approve]) {
      expect(finder, findsOneWidget);
    }
    expect(tester.getSize(copy).height, greaterThanOrEqualTo(44));
    // Top to bottom, in that order.
    final order = [heading, code, copy, expiry, field, approve];
    for (var i = 1; i < order.length; i++) {
      expect(tester.getRect(order[i - 1]).bottom, lessThanOrEqualTo(tester.getRect(order[i]).top));
    }
    expect(tester.widget<TextField>(field).decoration!.labelText, _en.deviceTransferClaimInputLabel);
    expect(find.widgetWithText(FilledButton, _en.deviceTransferIssueToken), findsNothing);
    expect(find.text(_en.deviceTransferOldStep1), findsNothing, reason: 'the instructions were the start screen');
  });

  testWidgets('what an approval came to is said under the button that approves, in green', (tester) async {
    await _pump(
      tester,
      status: const TransferClaimApproved('claim-7', 'AB12 CD34'),
      expiresAt: _now.add(const Duration(minutes: 4)),
    );

    final approved = find.text(_en.deviceTransferStatusClaimApproved);
    expect(approved, findsOneWidget);
    final approve = find.widgetWithText(FilledButton, _en.deviceTransferApproveClaim);
    expect(tester.getRect(approve).bottom, lessThanOrEqualTo(tester.getRect(approved).top));
    final context = tester.element(approved);
    expect(tester.widget<Text>(approved).style?.color, context.veilPalette.success);
    expect(find.byType(VeilNotice), findsNothing, reason: 'good news is a line, not a notice');
    // This phone's part is done.
    expect(tester.widget<FilledButton>(approve).onPressed, isNull);
  });

  // A failure used to stand above the steps, a screenful away from the
  // button that was tapped.
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
    final approve = find.widgetWithText(FilledButton, _en.deviceTransferApproveClaim);
    expect(tester.getRect(approve).bottom, lessThanOrEqualTo(tester.getRect(failure).top));
    expect(find.text(_en.deviceTransferStatusClaimNotWaiting('claim-7')), findsNothing,
        reason: 'the last thing that happened is the failure');
  });

  testWidgets('a claim waiting for approval puts no line under the button: the dialog shows it', (tester) async {
    await _pump(
      tester,
      status: const TransferClaimWaiting('claim-7', 'AB12 CD34'),
      expiresAt: _now.add(const Duration(minutes: 4)),
    );
    expect(find.byType(TransferStepResult), findsNothing);
    expect(find.textContaining('AB12'), findsNothing);
  });

  testWidgets('a failed approval comes into view on a phone, where the button is at the foot of the screen',
      (tester) async {
    // A phone with the keyboard up: less room than the screen holds.
    const phone = Size(360, 300);
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

  testWidgets('a failure to issue is said above the button that issues', (tester) async {
    await _pump(tester, status: null, expiresAt: null, errorMessage: 'The relay did not answer.');

    final failure = find.text('The relay did not answer.');
    expect(failure, findsOneWidget);
    expect(find.byType(VeilNotice), findsNothing, reason: 'a line, not a box');
    final issue = find.widgetWithText(FilledButton, _en.deviceTransferIssueToken);
    expect(tester.getRect(find.text(_en.deviceTransferOldStep3)).bottom, lessThanOrEqualTo(tester.getRect(failure).top));
    expect(tester.getRect(failure).bottom, lessThanOrEqualTo(tester.getRect(issue).top));
    expect(tester.widget<FilledButton>(issue).onPressed, isNotNull, reason: 'issuing can be tried again');
  });

  testWidgets('a build with no relay says so above the button, and does not offer to issue', (tester) async {
    await _pump(tester, status: const TransferNeedsApi(), expiresAt: null);

    final issue = find.widgetWithText(FilledButton, _en.deviceTransferIssueToken);
    final needsApi = find.text(_en.deviceTransferStatusNeedsApi);
    expect(needsApi, findsOneWidget);
    expect(tester.getRect(needsApi).bottom, lessThanOrEqualTo(tester.getRect(issue).top));
    expect(tester.widget<FilledButton>(issue).onPressed, isNull);
  });

  group('the approve dialog', () {
    Future<Future<bool>> open(WidgetTester tester) async {
      late Future<bool> result;
      await tester.pumpWidget(MaterialApp(
        theme: VeilTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => result = confirmTransferApproval(context, fingerprint: 'AB12 CD34'),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('names the key fingerprint the new phone shows and what moving does, before anything is signed',
        (tester) async {
      final result = await open(tester);
      expect(find.text(_en.deviceTransferApproveTitle), findsOneWidget);
      expect(find.text(_en.deviceTransferApproveBody('AB12 CD34')), findsOneWidget);
      await tester.tap(find.text(_en.commonCancel));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('"Move account" is the only way to approve', (tester) async {
      final result = await open(tester);
      await tester.tap(find.text(_en.deviceTransferApproveAction));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });
  });
}
