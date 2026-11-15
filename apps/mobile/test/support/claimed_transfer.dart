import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/security/device_step_up.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import 'fake_account_relay.dart';
import 'memory_secure_store.dart';

/// A new device that claimed a transfer its old device opened, both over
/// one [FakeAccountRelay]: what the transfer screen finds when the app is
/// started again on the new device. Everything here talks to the relay in
/// real time, so build it inside `tester.runAsync`.
class ClaimedTransfer {
  ClaimedTransfer._(this.relay, this.oldDevice, this.storage);

  final FakeAccountRelay relay;

  /// The old device's half: it issues further codes and approves claims.
  final DeviceTransferController oldDevice;

  /// The new device's keystore, holding the claim.
  final SecureStorageService storage;

  /// The code the old device shows for the transfer it has open.
  String get code => oldDevice.transferPayload!;

  static AppSessionController _session(SecureStorageService storage, FakeAccountRelay relay) => AppSessionController(
        storage,
        relay,
        createDefaultCryptoAdapter(),
        transferRetryDelay: Duration.zero,
        transferApprovalWait: const Duration(seconds: 2),
      );

  /// The old device registers and opens a transfer, the new device claims
  /// it, and the claim's window is moved to close [window] from now: a
  /// negative [window] is a claim that already ran out.
  static Future<ClaimedTransfer> create({Duration window = const Duration(minutes: 4)}) async {
    final relay = FakeAccountRelay();
    final oldStorage = SecureStorageService(MemorySecureStore());
    await oldStorage.persistOnboardingAccepted(true);
    final oldSession = _session(oldStorage, relay);
    await oldSession.bootstrap();
    await oldSession.registerAndAuthenticate(handle: 'atlas');
    final oldDevice = DeviceTransferController(
      apiClient: relay,
      session: () => oldSession.state,
      onSecurityException: oldSession.handleSecurityException,
      signWithDeviceKey: DeviceStepUp(
        storage: oldStorage,
        signer: createDefaultCryptoAdapter().deviceAuth,
        apiClient: relay,
      ).sign,
    );
    await oldDevice.initTransfer();

    final storage = SecureStorageService(MemorySecureStore());
    await storage.persistOnboardingAccepted(true);
    final newSession = _session(storage, relay);
    await newSession.bootstrap();
    await newSession.claimTransfer(
      sessionId: oldDevice.transferSessionId!,
      transferToken: oldDevice.transferToken!,
    );

    // The relay's session runs out with the claim, as it does for real.
    final closesAt = DateTime.now().add(window);
    relay.transfers[oldDevice.transferSessionId!]!.expiresAt = closesAt;
    final pending = (await storage.readPendingTransfer())!;
    await storage.persistPendingTransfer(PendingTransferRecord(
      sessionId: pending.sessionId,
      transferToken: pending.transferToken,
      claimId: pending.claimId,
      claimantFingerprint: pending.claimantFingerprint,
      expiresAt: closesAt,
      identity: pending.identity,
      authKey: pending.authKey,
    ));
    return ClaimedTransfer._(relay, oldDevice, storage);
  }

  /// The new device's session after the app started again.
  Future<AppSessionController> restart() async {
    final session = _session(storage, relay);
    await session.bootstrap();
    return session;
  }

  /// The transfer screen of the new device, in [locale].
  Widget app(AppSessionController session, {String locale = 'en'}) {
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
        debugShowCheckedModeBanner: false,
        locale: Locale(locale),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }
}
