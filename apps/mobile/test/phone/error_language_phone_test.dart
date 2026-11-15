import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/errors/user_facing_error.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/auth/presentation/choose_handle_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_attachment_views.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_old_device_panel.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_screen.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/step_row.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/splash_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// A failure the app has words of its own for reaches a screen as the
// sentence formatUserFacingError returned for it: the words of a log line,
// not of the ARB. The chat and the list show the ARB's sentence for it
// instead (veilErrorText); so does every other screen that shows a
// controller's error: the splash, the handle form, both sides of a device
// transfer, and an attachment in a chat. What has no code (a relay's own
// message, or a failure the data layer words itself and
// formatUserFacingError does not know) is shown as it came.

final _en = lookupAppLocalizations(const Locale('en'));

// What a relay says in its own words: no code, no sentence of the ARB.
const _relaysOwn = 'handle_taken';

Widget _alone(Widget child) => MaterialApp(
      theme: VeilTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  test('the ARB and the sentence a controller reports are not the same words', () {
    // Which is why a screen that shows the controller's sentence as it came
    // can be told from one that looked the ARB's up.
    for (final (code, arb) in [
      (UserFacingErrorCode.relayFailed, _en.errorRelayFailed),
      (UserFacingErrorCode.uploadFailed, _en.errorUploadFailed),
      (UserFacingErrorCode.notFound, _en.errorNotFound),
      (UserFacingErrorCode.conflict, _en.errorConflict),
    ]) {
      expect(arb, isNot(code.sentence), reason: code.name);
    }
  });

  testWidgets('the splash says why the app cannot start in the ARB\'s words', (tester) async {
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedOut,
      locale: 'en',
      bootstrapping: true,
      sessionError: UserFacingErrorCode.apiNeedsTls.sentence,
    );
    try {
      await tester.pumpWidget(world.app(location: '/splash'));
      await pumpFrames(tester);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(findCopy(_en.splashErrorTitle), findsOneWidget);
      expect(findCopy(_en.errorApiNeedsTls), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      world.dispose();
    }
  });

  testWidgets('the handle form says a refused handle in the ARB\'s words, and a relay\'s own words as they came',
      (tester) async {
    await withPhoneApp(tester, identities,
        location: '/choose-handle',
        account: LayoutAccount.signedOut,
        sessionError: UserFacingErrorCode.conflict.sentence, body: (world) async {
      expect(find.byType(ChooseHandleScreen), findsOneWidget);
      expect(findCopy(_en.authHandleFailedTitle), findsOneWidget);
      expect(findCopy(_en.errorConflict), findsOneWidget);
      expect(findCopy(UserFacingErrorCode.conflict.sentence), findsNothing);
    });

    await withPhoneApp(tester, identities,
        location: '/choose-handle',
        account: LayoutAccount.signedOut,
        sessionError: _relaysOwn, body: (world) async {
      expect(findCopy(_en.authHandleFailedTitle), findsOneWidget);
      expect(findCopy(_relaysOwn), findsOneWidget);
    });
  });

  testWidgets('a new device says a failed login in the ARB\'s words, in the step in hand', (tester) async {
    await withPhoneApp(tester, identities,
        location: '/device-transfer',
        account: LayoutAccount.signedOut,
        sessionError: UserFacingErrorCode.relayFailed.sentence, body: (world) async {
      expect(find.byType(DeviceTransferScreen), findsOneWidget);
      final failure = findCopy(_en.errorRelayFailed);
      expect(failure, findsOneWidget);
      // With the first step's controls, under the steps.
      expect(tester.getRect(failure).top, greaterThanOrEqualTo(tester.getRect(find.byType(StepRow).last).bottom));
      expect(tester.getRect(failure).top,
          greaterThanOrEqualTo(tester.getRect(find.widgetWithText(FilledButton, _en.deviceTransferImportPayload)).bottom));
      expect(findCopy(_en.deviceTransferFailedTitle), findsOneWidget);
      expect(findCopy(UserFacingErrorCode.relayFailed.sentence), findsNothing);
    });
  });

  testWidgets('an old device says a failed approval in the ARB\'s words', (tester) async {
    final now = DateTime(2026, 4, 2, 12);
    Widget panel(String error) => _alone(TransferOldDevicePanel(
          isAuthenticated: true,
          isBusy: false,
          transferSessionId: 'session-1',
          transferCode: 'VEIL_TRANSFER::session-1::token-1',
          status: const TransferTokenReady(),
          transferExpiresAt: now.add(const Duration(minutes: 4)),
          transferExpired: false,
          errorMessage: error,
          claimIdController: TextEditingController(),
          onIssue: () {},
          onApprove: () {},
          onCopyCode: () {},
          onClear: () {},
          now: now,
          stepsFooter: _en.deviceTransferOldPhoneNeeded,
        ));
    tester.view
      ..physicalSize = const Size(400, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(panel(UserFacingErrorCode.conflict.sentence));
    await tester.pump();
    final failure = findCopy(_en.errorConflict);
    expect(failure, findsOneWidget);
    // Under the button that approves.
    expect(tester.getRect(failure).top,
        greaterThanOrEqualTo(tester.getRect(find.widgetWithText(FilledButton, _en.deviceTransferApproveClaim)).bottom));
    expect(findCopy(UserFacingErrorCode.conflict.sentence), findsNothing);

    await tester.pumpWidget(panel(_relaysOwn));
    await tester.pump();
    expect(findCopy(_relaysOwn), findsOneWidget);
  });

  group('an attachment in a chat', () {
    AttachmentTransferSnapshot transfer(AttachmentTransferPhase phase, String error) => AttachmentTransferSnapshot(
          clientMessageId: 'client-1',
          phase: phase,
          progress: 0.5,
          filename: 'scan.pdf',
          contentType: 'application/pdf',
          errorMessage: error,
          canRetry: true,
          canCancel: false,
        );

    testWidgets('says a failed upload in the ARB\'s words', (tester) async {
      await tester.pumpWidget(_alone(AttachmentTransferPanel(
        snapshot: transfer(AttachmentTransferPhase.failed, UserFacingErrorCode.uploadFailed.sentence),
        onRetry: () {},
      )));

      // The error is the description and the banner's message.
      expect(findCopy(_en.errorUploadFailed), findsNWidgets(2));
      expect(findCopy(_en.chatAttachmentStateBanner), findsOneWidget);
      expect(findCopy(UserFacingErrorCode.uploadFailed.sentence), findsNothing);
    });

    // The outbox marks a canceled upload with a sentence of its own, which
    // has no code and says what the description already does.
    testWidgets('says a canceled upload once, in the ARB\'s words', (tester) async {
      await tester.pumpWidget(_alone(AttachmentTransferPanel(
        snapshot: transfer(AttachmentTransferPhase.canceled, 'Attachment upload was canceled on this device.'),
        onRetry: () {},
      )));

      expect(findCopy(_en.chatPhaseDescCanceled), findsOneWidget);
      expect(findCopy(_en.chatPhaseCanceled), findsOneWidget);
      expect(findCopy(_en.chatAttachmentStateBanner), findsNothing);
      expect(findCopyContaining('canceled on this device'), findsNothing);
    });

    testWidgets('says a refused download in the ARB\'s words', (tester) async {
      await tester.pumpWidget(_alone(MessageAttachmentCard(
        attachment: const AttachmentReference(
          attachmentId: 'att-1',
          storageKey: 'blob-1',
          contentType: 'application/pdf',
          sizeBytes: 2048,
          sha256: 'digest',
          encryptedKey: 'wrapped',
          nonce: 'nonce',
        ),
        resolving: false,
        downloadError: UserFacingErrorCode.notFound.sentence,
        onResolve: () {},
      )));

      expect(findCopy(_en.chatAttachmentTicketFailed), findsOneWidget);
      expect(findCopy(_en.errorNotFound), findsOneWidget);
      expect(findCopy(UserFacingErrorCode.notFound.sentence), findsNothing);
    });
  });
}
