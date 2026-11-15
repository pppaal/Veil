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
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_step.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/splash_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// A failure the app has words of its own for reaches a screen as the English
// sentence formatUserFacingError returned for it. The chat and the list say
// it in the app's language (veilErrorText); so does every other screen that
// shows a controller's error: the splash, the handle form, both sides of a
// device transfer, and an attachment in a chat. What has no code (a relay's
// own message, or a failure the data layer words itself and
// formatUserFacingError does not know) is shown as it came.

final _ko = lookupAppLocalizations(const Locale('ko'));
final _en = lookupAppLocalizations(const Locale('en'));

// What a relay says in its own words: no code, no translation.
const _relaysOwn = 'handle_taken';

Widget _alone(Widget child, {String locale = 'ko'}) => MaterialApp(
      theme: VeilTheme.dark(),
      locale: Locale(locale),
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

  test('the English of the app and the sentence a controller reports are not always the same words', () {
    // Which is why a test of an English run cannot tell a translated error
    // from a printed one, and these run in Korean.
    expect(_en.errorRelayFailed, isNot(UserFacingErrorCode.relayFailed.sentence));
    for (final code in UserFacingErrorCode.values) {
      expect(isOtherLanguage(code.sentence, 'ko'), isTrue, reason: '${code.name} is English copy');
    }
  });

  testWidgets('the splash says why the app cannot start in the app\'s language', (tester) async {
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedOut,
      locale: 'ko',
      bootstrapping: true,
      sessionError: UserFacingErrorCode.apiNeedsTls.sentence,
    );
    try {
      await tester.pumpWidget(world.app(location: '/splash'));
      await pumpFrames(tester);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(findCopy(_ko.splashErrorTitle), findsOneWidget);
      expect(findCopy(_ko.errorApiNeedsTls), findsOneWidget);
      expect(otherLanguageTextsOnScreen(tester, 'ko'), isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      world.dispose();
    }
  });

  testWidgets('the handle form says a refused handle in the app\'s language, and a relay\'s own words as they came',
      (tester) async {
    await withPhoneApp(tester, identities,
        location: '/choose-handle',
        account: LayoutAccount.signedOut,
        locale: 'ko',
        sessionError: UserFacingErrorCode.conflict.sentence, body: (world) async {
      expect(find.byType(ChooseHandleScreen), findsOneWidget);
      expect(findCopy(_ko.authHandleFailedTitle), findsOneWidget);
      expect(findCopy(_ko.errorConflict), findsOneWidget);
      expect(await otherLanguageTextsOfScreen(tester, 'ko'), isEmpty);
    });

    await withPhoneApp(tester, identities,
        location: '/choose-handle',
        account: LayoutAccount.signedOut,
        locale: 'ko',
        sessionError: _relaysOwn, body: (world) async {
      expect(findCopy(_ko.authHandleFailedTitle), findsOneWidget);
      expect(findCopy(_relaysOwn), findsOneWidget);
    });
  });

  testWidgets('a new device says a failed login in the app\'s language, in the step in hand', (tester) async {
    await withPhoneApp(tester, identities,
        location: '/device-transfer',
        account: LayoutAccount.signedOut,
        locale: 'ko',
        sessionError: UserFacingErrorCode.relayFailed.sentence, body: (world) async {
      expect(find.byType(DeviceTransferScreen), findsOneWidget);
      final failure = findCopy(_ko.errorRelayFailed);
      expect(failure, findsOneWidget);
      expect(tester.widget<TransferStep>(find.ancestor(of: failure, matching: find.byType(TransferStep))).number, 1);
      expect(findCopy(_ko.deviceTransferFailedTitle), findsOneWidget);
      expect(await otherLanguageTextsOfScreen(tester, 'ko'), isEmpty);
    });
  });

  testWidgets('an old device says a failed approval in the app\'s language', (tester) async {
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
        ));
    tester.view
      ..physicalSize = const Size(400, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(panel(UserFacingErrorCode.notAllowed.sentence));
    await tester.pump();
    final failure = findCopy(_ko.errorNotAllowed);
    expect(failure, findsOneWidget);
    expect(tester.widget<TransferStep>(find.ancestor(of: failure, matching: find.byType(TransferStep))).number, 3);
    expect(findCopy(UserFacingErrorCode.notAllowed.sentence), findsNothing);

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

    testWidgets('says a failed upload in the app\'s language', (tester) async {
      await tester.pumpWidget(_alone(AttachmentTransferPanel(
        snapshot: transfer(AttachmentTransferPhase.failed, UserFacingErrorCode.uploadFailed.sentence),
        onRetry: () {},
      )));

      // The error is the description and the banner's message.
      expect(findCopy(_ko.errorUploadFailed), findsNWidgets(2));
      expect(findCopy(_ko.chatAttachmentStateBanner), findsOneWidget);
      expect(otherLanguageTextsOnScreen(tester, 'ko'), isEmpty);
    });

    // The outbox marks a canceled upload with a sentence of its own, which
    // has no translation and says what the description already does.
    testWidgets('says a canceled upload once, in the app\'s language', (tester) async {
      await tester.pumpWidget(_alone(AttachmentTransferPanel(
        snapshot: transfer(AttachmentTransferPhase.canceled, 'Attachment upload was canceled on this device.'),
        onRetry: () {},
      )));

      expect(findCopy(_ko.chatPhaseDescCanceled), findsOneWidget);
      expect(findCopy(_ko.chatPhaseCanceled), findsOneWidget);
      expect(findCopy(_ko.chatAttachmentStateBanner), findsNothing);
      expect(findCopyContaining('canceled'), findsNothing);
      expect(otherLanguageTextsOnScreen(tester, 'ko'), isEmpty);
    });

    testWidgets('says a refused download in the app\'s language', (tester) async {
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

      expect(findCopy(_ko.chatAttachmentTicketFailed), findsOneWidget);
      expect(findCopy(_ko.errorNotFound), findsOneWidget);
      expect(otherLanguageTextsOnScreen(tester, 'ko'), isEmpty);
    });
  });
}
