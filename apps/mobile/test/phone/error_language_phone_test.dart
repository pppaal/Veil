import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/auth/presentation/choose_handle_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_file_card.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_time.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_old_device_panel.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_screen.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/splash_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_notice.dart';

import '../support/copy_finder.dart';
import '../support/fake_relay.dart';
import '../support/mock_relay_parties.dart';
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
const _relaysOwn = 'Request rejected';

// The error under the one text field on screen.
String? _fieldError(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).decoration?.errorText;

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
      // The handle field's error, in place of its helper line.
      expect(_fieldError(tester), _en.errorConflict);
      expect(findCopy(_en.errorConflict), findsOneWidget);
      expect(findCopy(UserFacingErrorCode.conflict.sentence), findsNothing);
      expect(find.byType(VeilNotice), findsNothing);
    });

    await withPhoneApp(tester, identities,
        location: '/choose-handle', account: LayoutAccount.signedOut, sessionError: _relaysOwn, body: (world) async {
      expect(_fieldError(tester), _relaysOwn);
      expect(findCopy(_relaysOwn), findsOneWidget);
    });
  });

  testWidgets('a new device says a failed login in the ARB\'s words, under the button in hand', (tester) async {
    await withPhoneApp(tester, identities,
        location: '/device-transfer',
        account: LayoutAccount.signedOut,
        sessionError: UserFacingErrorCode.relayFailed.sentence, body: (world) async {
      expect(find.byType(DeviceTransferScreen), findsOneWidget);
      final failure = findCopy(_en.errorRelayFailed);
      expect(failure, findsOneWidget);
      // Under the first screen's one button.
      expect(tester.getRect(failure).top,
          greaterThanOrEqualTo(tester.getRect(find.widgetWithText(FilledButton, _en.commonContinue)).bottom));
      // One line, not a box.
      expect(find.byType(VeilNotice), findsNothing);
      expect(findCopy(UserFacingErrorCode.relayFailed.sentence), findsNothing);
    });
  });

  testWidgets('an old device says a failed approval in the ARB\'s words', (tester) async {
    final now = DateTime(2026, 4, 2, 12);
    Widget panel(String error) => _alone(TransferOldDevicePanel(
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
          now: now,
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

  // Changed on purpose: an upload's progress panel, which put the outbox's
  // error in the ARB's words, is gone (D26). A file that did not go is said
  // the way every failed send is, under its own bubble; neither the
  // controller's sentence nor the outbox's note of a cancel ever shows.
  group('an attachment in a chat', () {
    for (final (phase, error) in [
      (AttachmentTransferPhase.failed, UserFacingErrorCode.uploadFailed.sentence),
      (AttachmentTransferPhase.canceled, 'Attachment upload was canceled on this device.'),
    ]) {
      testWidgets('says an upload that ended ${phase.name} as a failed send, in the ARB\'s words', (tester) async {
        final relay = FakeRelay();
        seedMockParties(relay, 'conv-1', ['atlas', 'selene']);
        final messenger = mockPartyController(relay, 'atlas');
        // The provider scope disposes it with the widget tree.
        final message = ChatMessage(
          id: 'local-client-1',
          clientMessageId: 'client-1',
          senderDeviceId: 'dev-atlas',
          sentAt: DateTime.utc(2026, 4, 7, 9, 52),
          isMine: true,
          deliveryState: MessageDeliveryState.failed,
          envelope: const CryptoEnvelope(
            version: 'v2',
            conversationId: 'conv-1',
            senderDeviceId: 'dev-atlas',
            recipientUserId: 'user-selene',
            ciphertext: '',
            nonce: '',
            messageKind: MessageKind.file,
          ),
        );
        await tester.pumpWidget(ProviderScope(
          overrides: [messengerControllerProvider.overrideWith((ref) => messenger)],
          child: _alone(Builder(
            builder: (context) => MessageBubble(
              message: message,
              conversationId: 'conv-1',
              highlighted: false,
              sentAtFormat: MessageTimeFormat.of(context),
              decryptFuture: Future.value(const DecryptedMessage(
                body: 'scan.pdf',
                messageKind: MessageKind.file,
                attachment: AttachmentReference(
                  attachmentId: '6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f',
                  storageKey: '',
                  contentType: 'application/pdf',
                  sizeBytes: 120000,
                  sha256: 'digest',
                  encryptedKey: 'key',
                  nonce: 'nonce',
                  algorithmHint: 'aes256gcm-v2',
                ),
              )),
              onCancelAttachment: () {},
              transferSnapshot: AttachmentTransferSnapshot(
                clientMessageId: 'client-1',
                phase: phase,
                progress: 0.5,
                filename: 'scan.pdf',
                contentType: 'application/pdf',
                errorMessage: error,
                canRetry: true,
                canCancel: true,
              ),
              expiryNow: () => DateTime.utc(2026, 4, 7, 10),
              onRetryMessage: () {},
            ),
          )),
        ));
        await tester.pump();

        expect(find.byWidgetPredicate((widget) => widget is MiddleEllipsisText && widget.text == 'scan.pdf'),
            findsOneWidget);
        expect(findCopy(_en.chatNotSentTapToRetry), findsOneWidget);
        expect(findCopy(error), findsNothing);
        expect(findCopy(_en.errorUploadFailed), findsNothing);
        expect(findCopyContaining('canceled on this device'), findsNothing);
        expect(find.byType(VeilNotice), findsNothing);
      });
    }
  });
}
