import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../layout/support/phone_layout_probe.dart';
import '../support/claimed_transfer.dart';

// The old phone approving a move, through its screen: Approve reads the
// claim first and asks, with the key fingerprint the new phone shows; the
// approval is signed only once the user chose "Move account". Cancel moves
// nothing.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadBundledFonts);
  final en = lookupAppLocalizations(const Locale('en'));

  // Real time for the fake relay, frames for the screen, until [condition].
  Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 400 && !condition(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(condition(), isTrue);
  }

  testWidgets('Approve shows the new phone\'s fingerprint and signs nothing until "Move account"', (tester) async {
    usePhoneView(tester, phoneMedium);
    late ClaimedTransfer transfer;
    await tester.runAsync(() async {
      transfer = await ClaimedTransfer.create();
    });
    final claim = transfer.relay.transfers[transfer.oldDevice.transferSessionId!]!.claim!;
    await tester.pumpWidget(transfer.oldApp());
    await pumpFrames(tester, frames: 3);

    await tester.enterText(find.byType(TextField), claim.claimId);
    final approve = find.widgetWithText(FilledButton, en.deviceTransferApproveClaim);
    final dialog = find.byType(AlertDialog);

    // Cancel: the claim was read, and nothing was approved.
    await tester.tap(approve);
    await pumpUntil(tester, () => dialog.evaluate().isNotEmpty);
    expect(find.text(en.deviceTransferApproveTitle), findsOneWidget);
    expect(find.text(en.deviceTransferApproveBody(claim.claimantFingerprint)), findsOneWidget);
    await tester.tap(find.text(en.commonCancel));
    await pumpFrames(tester, frames: 3);
    expect(dialog, findsNothing);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(claim.approved, isFalse, reason: 'Cancel approves nothing');
    expect(find.text(en.deviceTransferStatusClaimApproved), findsNothing);

    // Move account: the approval is signed and the relay takes it.
    await tester.tap(approve);
    await pumpUntil(tester, () => dialog.evaluate().isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('transfer-approve-confirm')));
    await pumpUntil(tester, () => claim.approved);
    await pumpUntil(tester, () => find.text(en.deviceTransferStatusClaimApproved).evaluate().isNotEmpty);
    expect(transfer.oldDevice.errorMessage, isNull);
  });
}
