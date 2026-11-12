import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_providers.dart';

import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';
import '../support/messenger_party.dart';

/// The relay's side of a device transfer, for both devices.
class _TransferApi extends VeilApiClient {
  _TransferApi() : super(baseUrl: 'http://relay.invalid/v1');

  @override
  Future<Map<String, dynamic>> initTransfer(String accessToken, String oldDeviceId) async => {
        'sessionId': 'transfer-1',
        'transferToken': 'token-1',
        'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      };

  @override
  Future<Map<String, dynamic>> claimTransfer(Map<String, dynamic> body) async => {
        'claimId': 'claim-1',
        'claimantFingerprint': 'FPR-ALPHA',
        'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      };

  @override
  Future<Map<String, dynamic>> completeTransfer(Map<String, dynamic> body) async =>
      {'newDeviceId': 'dev-new', 'handle': 'atlas'};

  @override
  Future<Map<String, dynamic>> challenge(Map<String, dynamic> body) async =>
      {'challengeId': 'challenge-1', 'challenge': 'sign-me'};

  @override
  Future<Map<String, dynamic>> verify(Map<String, dynamic> body) async => {
        'accessToken': 'access-new',
        'refreshToken': 'refresh-new',
        'userId': 'user-atlas',
        'deviceId': 'dev-new',
      };
}

// The encrypted cache opens asynchronously, and is reopened after a wipe.
// Long-lived controllers read it through a stable handle, so neither event
// rebuilds them or drops what they hold in memory.
void main() {
  late Completer<AppDatabase> database;
  late ProviderContainer container;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = Completer<AppDatabase>();
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(SecureStorageService(MemorySecureStore())),
      appDatabaseFutureProvider.overrideWith((ref) => database.future),
      apiClientProvider.overrideWithValue(_TransferApi()),
      realtimeServiceProvider.overrideWithValue(FakeRelayRealtime()),
      localNotificationServiceProvider.overrideWithValue(RecordingNotifications()),
      cryptoAdapterProvider.overrideWithValue(createDefaultCryptoAdapter()),
    ]);
    addTearDown(container.dispose);
  });

  Future<void> resolveCache() async {
    if (!database.isCompleted) database.complete(AppDatabase(NativeDatabase.memory()));
    expect(await container.read(conversationCacheProvider.future), isNotNull);
  }

  test('AppSessionController and VeilMessengerController constructed once across cache resolution', () async {
    final session = container.read(appSessionProvider.notifier);
    final messenger = container.read(messengerControllerProvider);

    await resolveCache();
    expect(container.read(appSessionProvider.notifier), same(session));
    expect(container.read(messengerControllerProvider), same(messenger));

    // A wipe reopens the cache under a new key; the controllers stay.
    container.read(cacheEpochProvider.notifier).state++;
    await resolveCache();
    expect(container.read(appSessionProvider.notifier), same(session));
    expect(container.read(messengerControllerProvider), same(messenger));
  });

  test('transfer claim state survives cache resolution', () async {
    // The new device claims before its database opened...
    final session = container.read(appSessionProvider.notifier);
    final claim = await session.claimTransfer(sessionId: 'transfer-1', transferToken: 'token-1');

    await resolveCache();

    // ...and completes with the claim it still holds once it has.
    await container.read(appSessionProvider.notifier).completeTransferAndAuthenticate(
          sessionId: 'transfer-1',
          transferToken: 'token-1',
          claimId: claim.claimId,
        );
    expect(container.read(appSessionProvider).deviceId, 'dev-new');

    // The old device's open transfer survives the cache reopening too.
    final transfer = container.read(deviceTransferControllerProvider);
    await transfer.initTransfer();
    expect(transfer.transferSessionId, 'transfer-1');
    container.read(cacheEpochProvider.notifier).state++;
    await resolveCache();
    expect(container.read(deviceTransferControllerProvider), same(transfer));
    expect(container.read(deviceTransferControllerProvider).transferPayload, 'VEIL_TRANSFER::transfer-1::token-1');
  });
}
