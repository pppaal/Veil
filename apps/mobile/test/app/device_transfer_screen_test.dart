import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/security/device_step_up.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../support/async_wait.dart';
import '../support/fake_account_relay.dart';
import '../support/memory_secure_store.dart';

// C-TRANSFER-RETRY on the transfer screen. Once the relay committed a
// transfer, the old device is revoked and the claimed keys are the only ones
// the account trusts, so the login that follows must stay reachable from the
// screen however long ago the claim was made. The same holds while the relay
// may have committed it (a /complete went out and its answer was lost): the
// relay answers a retry of a committed transfer at any age, and only its
// transfer_session_inactive ends such a claim. The claim window
// (VEIL_TRANSFER_TOKEN_TTL_SECONDS) bounds only a claim with no /complete
// left unanswered.

AppSessionController _controller(SecureStorageService storage, FakeAccountRelay relay) => AppSessionController(
      storage,
      relay,
      createDefaultCryptoAdapter(),
      transferRetryDelay: Duration.zero,
      transferApprovalWait: const Duration(seconds: 2),
    );

// How far the new device got after the old device approved its claim.
enum _Completion {
  // It never sent /complete.
  none,
  // The relay committed the transfer and the login that followed failed.
  loginFailed,
  // The relay committed the transfer and the answer was lost (the
  // connection dropped); both retries then got a 503.
  answerLost,
  // All three attempts got a 503 before the relay committed anything.
  relayDown,
}

// The new device's keystore after it claimed a transfer the old device
// approved and got as far as [completion], with the claim window
// ([PendingTransferRecord.expiresAt]) moved [age] into the past.
Future<SecureStorageService> _newDeviceKeystore(
  FakeAccountRelay relay, {
  required _Completion completion,
  required Duration age,
}) async {
  final oldStorage = SecureStorageService(MemorySecureStore());
  await oldStorage.persistOnboardingAccepted(true);
  final oldSession = _controller(oldStorage, relay);
  await oldSession.bootstrap();
  await oldSession.registerAndAuthenticate(handle: 'atlas');
  final transfers = DeviceTransferController(
    apiClient: relay,
    session: () => oldSession.state,
    onSecurityException: oldSession.handleSecurityException,
    signWithDeviceKey: DeviceStepUp(
      storage: oldStorage,
      signer: createDefaultCryptoAdapter().deviceAuth,
      apiClient: relay,
    ).sign,
  );
  await transfers.initTransfer();

  final storage = SecureStorageService(MemorySecureStore());
  await storage.persistOnboardingAccepted(true);
  final newSession = _controller(storage, relay);
  await newSession.bootstrap();
  final claim = await newSession.claimTransfer(
    sessionId: transfers.transferSessionId!,
    transferToken: transfers.transferToken!,
  );
  await transfers.approveTransfer(claim.claimId);
  expect(transfers.errorMessage, isNull);

  Future<void> completeFails() => expectLater(
        newSession.completeTransferAndAuthenticate(
          sessionId: transfers.transferSessionId!,
          transferToken: transfers.transferToken!,
          claimId: claim.claimId,
        ),
        throwsA(anything),
      );
  switch (completion) {
    case _Completion.none:
      break;
    case _Completion.loginFailed:
      relay.failChallenges = 1;
      await completeFails();
      expect(relay.callsTo('POST /device-transfer/complete'), 1);
    case _Completion.answerLost:
      relay.dropCompletionResponses = 1;
      relay.onComplete = () {
        if (relay.callsTo('POST /device-transfer/complete') == 2) relay.failCompletions = 2;
      };
      await completeFails();
      relay.onComplete = null;
      expect(relay.callsTo('POST /device-transfer/complete'), 3);
      expect(relay.transfers.values.single.newDeviceId, isNotNull);
      expect(relay.devices[oldSession.state.deviceId]!.active, isFalse);
    case _Completion.relayDown:
      relay.failCompletions = 3;
      await completeFails();
      expect(relay.callsTo('POST /device-transfer/complete'), 3);
      expect(relay.transfers.values.single.newDeviceId, isNull);
  }
  final pending = (await storage.readPendingTransfer())!;
  expect(pending.isCompleted, completion == _Completion.loginFailed);
  expect(
    pending.completionOutcomeUnknown,
    completion == _Completion.answerLost || completion == _Completion.relayDown,
  );

  await storage.persistPendingTransfer(PendingTransferRecord(
    sessionId: pending.sessionId,
    transferToken: pending.transferToken,
    claimId: pending.claimId,
    claimantFingerprint: pending.claimantFingerprint,
    expiresAt: DateTime.now().subtract(age),
    identity: pending.identity,
    authKey: pending.authKey,
    newDeviceId: pending.newDeviceId,
    handle: pending.handle,
    completionOutcomeUnknown: pending.completionOutcomeUnknown,
    ended: pending.ended,
  ));
  return storage;
}

Widget _app(AppSessionController session, FakeAccountRelay relay, SecureStorageService storage) {
  final router = GoRouter(
    initialLocation: '/device-transfer',
    routes: [
      GoRoute(path: '/device-transfer', builder: (_, __) => const DeviceTransferScreen()),
      GoRoute(path: '/conversations', builder: (_, __) => const Text('conversations')),
    ],
  );
  return ProviderScope(
    overrides: [
      appSessionProvider.overrideWith((ref) => session),
      apiClientProvider.overrideWithValue(relay),
      secureStorageProvider.overrideWithValue(storage),
      cryptoAdapterProvider.overrideWithValue(createDefaultCryptoAdapter()),
    ],
    child: MaterialApp.router(
      theme: VeilTheme.dark(),
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

final _en = lookupAppLocalizations(const Locale('en'));

Finder get _completeButton => find.ancestor(
      of: find.text(_en.deviceTransferCompleteOnDevice),
      matching: find.byType(FilledButton),
    );

// Tall enough that the whole screen is built, banners and buttons included.
void _tallView(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1200, 6000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

bool _enabled(WidgetTester tester) => tester.widget<FilledButton>(_completeButton).onPressed != null;

// Lets both the test's fake clock and real time move until [condition].
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  expect(condition(), isTrue);
}

void main() {
  testWidgets('a committed transfer past its claim window still finishes its login from the screen', (tester) async {
    final relay = FakeAccountRelay();
    late SecureStorageService storage;
    late AppSessionController session;
    await tester.runAsync(() async {
      storage = await _newDeviceKeystore(relay, completion: _Completion.loginFailed, age: const Duration(minutes: 6));
      // The app restarts and the login it resumes at boot fails too.
      relay.failChallenges = 1;
      session = _controller(storage, relay);
      await session.bootstrap();
      await waitFor(() => relay.failChallenges == 0 && session.state.errorMessage != null);
    });
    expect(session.pendingTransfer?.isCompleted, isTrue);
    expect(session.state.isAuthenticated, isFalse);

    _tallView(tester);
    await tester.pumpWidget(_app(session, relay, storage));
    await tester.pump();

    expect(find.text(_en.deviceTransferWindowExpiredTitle), findsNothing);
    expect(find.text(_en.deviceTransferClaimExpiredPill), findsNothing);
    expect(find.text(_en.deviceTransferClaimExpired), findsNothing);
    expect(find.text(_en.deviceTransferExpires(_en.deviceTransferExpiryNow)), findsNothing);
    await tester.ensureVisible(_completeButton);
    expect(_enabled(tester), isTrue);

    // A login that fails again leaves the way to finish it open.
    relay.failChallenges = 1;
    await tester.tap(_completeButton);
    await _pumpUntil(tester, () => relay.failChallenges == 0 && session.state.errorMessage != null);
    expect(session.state.isAuthenticated, isFalse);
    expect(_enabled(tester), isTrue);

    // The relay answers again: the login is redone, never the completion.
    await tester.tap(_completeButton);
    await _pumpUntil(tester, () => session.state.isAuthenticated);
    await tester.pumpAndSettle();

    final transfer = relay.transfers.values.single;
    expect(session.state.deviceId, transfer.newDeviceId);
    expect(relay.callsTo('POST /device-transfer/complete'), 1);
    expect(await tester.runAsync(storage.readPendingTransfer), isNull);
    expect(find.text('conversations'), findsOneWidget);
  });

  testWidgets('a claim the relay has not committed still expires with its window', (tester) async {
    final relay = FakeAccountRelay();
    late SecureStorageService storage;
    late AppSessionController session;
    await tester.runAsync(() async {
      storage = await _newDeviceKeystore(relay, completion: _Completion.none, age: const Duration(minutes: 6));
      session = _controller(storage, relay);
      await session.bootstrap();
    });
    expect(session.pendingTransfer?.isCompleted, isFalse);

    _tallView(tester);
    await tester.pumpWidget(_app(session, relay, storage));
    await tester.pump();

    expect(find.text(_en.deviceTransferWindowExpiredTitle), findsOneWidget);
    expect(find.text(_en.deviceTransferClaimExpiredPill), findsOneWidget);
    expect(find.text(_en.deviceTransferExpires(_en.deviceTransferExpiryNow)), findsOneWidget);
    await tester.ensureVisible(_completeButton);
    expect(_enabled(tester), isFalse);
    expect(relay.callsTo('POST /device-transfer/complete'), 0);
  });

  // closing F1: the relay committed, the answer was lost and the retries
  // failed, the app restarted past the claim window and the completion it
  // asks again at start failed as well. Only the relay can say the transfer
  // went through, and it answers the same completion at any age.
  testWidgets('a completion whose answer was lost finishes from the screen however long ago the window closed',
      (tester) async {
    final relay = FakeAccountRelay();
    late SecureStorageService storage;
    late AppSessionController session;
    await tester.runAsync(() async {
      storage = await _newDeviceKeystore(relay, completion: _Completion.answerLost, age: const Duration(minutes: 6));
      relay.failCompletions = 3;
      session = _controller(storage, relay);
      await session.bootstrap();
      await waitFor(() => relay.failCompletions == 0 && session.state.errorMessage != null);
    });
    expect(relay.callsTo('POST /device-transfer/complete'), 6);
    expect(session.pendingTransfer?.isCompleted, isFalse);
    expect(session.pendingTransfer?.completionOutcomeUnknown, isTrue);
    expect(session.state.isAuthenticated, isFalse);

    _tallView(tester);
    await tester.pumpWidget(_app(session, relay, storage));
    await tester.pump();

    expect(find.text(_en.deviceTransferWindowExpiredTitle), findsNothing);
    expect(find.text(_en.deviceTransferClaimExpiredPill), findsNothing);
    expect(find.text(_en.deviceTransferClaimExpired), findsNothing);
    expect(find.text(_en.deviceTransferExpires(_en.deviceTransferExpiryNow)), findsNothing);
    await tester.ensureVisible(_completeButton);
    expect(_enabled(tester), isTrue);

    await tester.tap(_completeButton);
    await _pumpUntil(tester, () => session.state.isAuthenticated);
    await tester.pumpAndSettle();

    final transfer = relay.transfers.values.single;
    expect(session.state.deviceId, transfer.newDeviceId);
    expect(relay.devices, hasLength(2), reason: 'one commit: the old device and the new one');
    expect(relay.callsTo('POST /device-transfer/complete'), 7);
    expect(await tester.runAsync(storage.readPendingTransfer), isNull);
    expect(find.text('conversations'), findsOneWidget);
  });

  testWidgets('an unanswered completion the relay never committed shows as expired once the relay says so',
      (tester) async {
    final relay = FakeAccountRelay();
    late SecureStorageService storage;
    late AppSessionController session;
    await tester.runAsync(() async {
      storage = await _newDeviceKeystore(relay, completion: _Completion.relayDown, age: const Duration(minutes: 6));
      relay.failCompletions = 3;
      session = _controller(storage, relay);
      await session.bootstrap();
      await waitFor(() => relay.failCompletions == 0 && session.state.errorMessage != null);
    });
    expect(session.pendingTransfer?.completionOutcomeUnknown, isTrue);
    expect(session.pendingTransfer?.ended, isFalse);

    _tallView(tester);
    await tester.pumpWidget(_app(session, relay, storage));
    await tester.pump();

    // The relay has not answered yet: completing stays possible.
    expect(find.text(_en.deviceTransferWindowExpiredTitle), findsNothing);
    await tester.ensureVisible(_completeButton);
    expect(_enabled(tester), isTrue);

    // Its session ran out as well; it ends the claim.
    relay.transfers.values.single.expiresAt = DateTime.now().subtract(const Duration(minutes: 1));
    await tester.tap(_completeButton);
    await _pumpUntil(tester, () => session.pendingTransfer?.ended ?? false);
    await tester.pump();

    expect(relay.callsTo('POST /device-transfer/complete'), 7);
    expect(session.state.isAuthenticated, isFalse);
    expect(find.text(_en.deviceTransferWindowExpiredTitle), findsOneWidget);
    expect(find.text(_en.deviceTransferClaimExpiredPill), findsOneWidget);
    await tester.ensureVisible(_completeButton);
    expect(_enabled(tester), isFalse);
    expect((await tester.runAsync(storage.readPendingTransfer))?.ended, isTrue);
  });

  // closing F2: importing again the payload of the session this device
  // already claimed keeps that claim, so it can still be completed.
  testWidgets('re-importing the payload of the claimed session keeps the claim completable', (tester) async {
    final relay = FakeAccountRelay();
    late SecureStorageService storage;
    late AppSessionController session;
    await tester.runAsync(() async {
      storage = await _newDeviceKeystore(relay, completion: _Completion.none, age: const Duration(minutes: -4));
      session = _controller(storage, relay);
      await session.bootstrap();
    });
    final transfer = relay.transfers.values.single;
    final claimId = session.pendingTransfer!.claimId;

    _tallView(tester);
    await tester.pumpWidget(_app(session, relay, storage));
    await tester.pump();
    expect(find.text(_en.deviceTransferClaimCode(claimId)), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, _en.deviceTransferPayloadInputLabel),
      'VEIL_TRANSFER::${transfer.id}::${transfer.transferToken}',
    );
    await tester.tap(find.text(_en.deviceTransferImportPayload));
    await tester.pump();

    expect(find.text(_en.deviceTransferPayloadImported), findsOneWidget);
    expect(find.text(_en.deviceTransferClaimCode(claimId)), findsOneWidget);
    await tester.ensureVisible(_completeButton);
    expect(_enabled(tester), isTrue);

    await tester.tap(_completeButton);
    await _pumpUntil(tester, () => session.state.isAuthenticated);
    await tester.pumpAndSettle();
    expect(session.state.deviceId, transfer.newDeviceId);
    expect(relay.callsTo('POST /device-transfer/claim'), 1);
  });

  testWidgets('another payload does not replace a claim the relay may have committed', (tester) async {
    final relay = FakeAccountRelay();
    late SecureStorageService storage;
    late AppSessionController session;
    await tester.runAsync(() async {
      storage = await _newDeviceKeystore(relay, completion: _Completion.answerLost, age: const Duration(minutes: 6));
      relay.failCompletions = 3;
      session = _controller(storage, relay);
      await session.bootstrap();
      await waitFor(() => relay.failCompletions == 0 && session.state.errorMessage != null);
    });
    final claimId = session.pendingTransfer!.claimId;

    _tallView(tester);
    await tester.pumpWidget(_app(session, relay, storage));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, _en.deviceTransferPayloadInputLabel),
      'VEIL_TRANSFER::another-session::another-token',
    );
    await tester.tap(find.text(_en.deviceTransferImportPayload));
    await tester.pump();

    expect(find.text(_en.deviceTransferFinishStartedFirst), findsOneWidget);
    expect(find.text(_en.deviceTransferClaimCode(claimId)), findsOneWidget);
    await tester.ensureVisible(_completeButton);
    expect(_enabled(tester), isTrue);
    await tester.tap(_completeButton);
    await _pumpUntil(tester, () => session.state.isAuthenticated);
    expect(session.state.deviceId, relay.transfers.values.single.newDeviceId);
    expect(relay.callsTo('POST /device-transfer/claim'), 1);
    await tester.pumpAndSettle();
  });
}
