import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/security/device_step_up.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';

import '../support/fake_account_relay.dart';
import '../support/memory_secure_store.dart';

// C-PROOF and C-TRANSFER-RETRY on the real session and transfer controllers,
// against a relay that checks every signature as the API does.

class _Device {
  _Device(this.relay);

  final FakeAccountRelay relay;
  final MemorySecureStore store = MemorySecureStore();
  late final SecureStorageService storage = SecureStorageService(store);
  late AppSessionController session = controller();

  AppSessionController controller() => AppSessionController(
        storage,
        relay,
        createDefaultCryptoAdapter(),
        transferRetryDelay: Duration.zero,
        transferApprovalWait: const Duration(seconds: 2),
      );

  DeviceStepUp get stepUp => DeviceStepUp(
        storage: storage,
        signer: createDefaultCryptoAdapter().deviceAuth,
        apiClient: relay,
      );

  DeviceTransferController transfers({bool canSign = true}) => DeviceTransferController(
        apiClient: relay,
        session: () => session.state,
        onSecurityException: session.handleSecurityException,
        signWithDeviceKey: canSign ? stepUp.sign : null,
      );
}

Future<_Device> _registered(FakeAccountRelay relay, String handle) async {
  final device = _Device(relay);
  await device.storage.persistOnboardingAccepted(true);
  await device.session.bootstrap();
  await device.session.registerAndAuthenticate(handle: handle);
  return device;
}

// An old device that opened a transfer, and a new device that claimed it.
Future<({_Device oldDevice, DeviceTransferController transfers, _Device newDevice, String claimId})> _claimed(
  FakeAccountRelay relay,
) async {
  final oldDevice = await _registered(relay, 'atlas');
  final transfers = oldDevice.transfers();
  await transfers.initTransfer();
  final newDevice = _Device(relay);
  await newDevice.session.bootstrap();
  final claim = await newDevice.session.claimTransfer(
    sessionId: transfers.transferSessionId!,
    transferToken: transfers.transferToken!,
  );
  return (oldDevice: oldDevice, transfers: transfers, newDevice: newDevice, claimId: claim.claimId);
}

Future<void> _complete(_Device newDevice, DeviceTransferController transfers, String claimId) =>
    newDevice.session.completeTransferAndAuthenticate(
      sessionId: transfers.transferSessionId!,
      transferToken: transfers.transferToken!,
      claimId: claimId,
    );

void main() {
  group('step-up proofs', () {
    test('account deletion is signed by the device and only then wipes it', () async {
      final relay = FakeAccountRelay();
      final device = await _registered(relay, 'atlas');

      await device.session.deleteAccount();

      expect(relay.usersByHandle['atlas']!.deleted, isTrue);
      expect(relay.calls, containsAllInOrder(['POST /auth/challenge', 'DELETE /account']));
      expect(device.session.state.isAuthenticated, isFalse);
      expect(await device.storage.hasDeviceSecretRefs(), isFalse);
    });

    test('a refused deletion keeps the account and this device as they were', () async {
      final relay = FakeAccountRelay();
      final device = await _registered(relay, 'atlas');
      // The keystore holds another auth key than the one the relay trusts,
      // so the proof does not verify.
      final foreign = await createDefaultCryptoAdapter().deviceAuth.generateAuthKeyMaterial();
      await device.store.write(key: 'veil.auth.private_key', value: foreign.privateKey);
      await device.store.write(key: 'veil.auth.public_key', value: foreign.publicKey);

      await expectLater(
        device.session.deleteAccount(),
        throwsA(isA<VeilApiException>().having((e) => e.code, 'code', 'invalid_device_signature')),
      );

      expect(relay.usersByHandle['atlas']!.deleted, isFalse);
      expect(device.session.state.isAuthenticated, isTrue);
      expect(await device.storage.readSession(), isNotNull);
      expect(await device.storage.hasDeviceSecretRefs(), isTrue);
    });

    test('a deletion the relay never answered keeps this device signed in', () async {
      final relay = FakeAccountRelay();
      final device = await _registered(relay, 'atlas');
      relay.failChallenges = 1;

      await expectLater(device.session.deleteAccount(), throwsA(isA<VeilApiException>()));

      expect(device.session.state.isAuthenticated, isTrue);
      expect(await device.storage.readSession(), isNotNull);
    });

    test('revoking this device is signed by it and only then wipes it', () async {
      final relay = FakeAccountRelay();
      final device = await _registered(relay, 'atlas');
      final deviceId = device.session.state.deviceId!;

      await device.session.revokeCurrentDevice();

      expect(relay.devices[deviceId]!.active, isFalse);
      expect(device.session.state.isAuthenticated, isFalse);
      expect(await device.storage.hasDeviceSecretRefs(), isFalse);
    });

    test('a refused revocation of this device keeps it signed in', () async {
      final relay = FakeAccountRelay();
      final device = await _registered(relay, 'atlas');
      final deviceId = device.session.state.deviceId!;
      final foreign = await createDefaultCryptoAdapter().deviceAuth.generateAuthKeyMaterial();
      await device.store.write(key: 'veil.auth.private_key', value: foreign.privateKey);
      await device.store.write(key: 'veil.auth.public_key', value: foreign.publicKey);

      await expectLater(device.session.revokeCurrentDevice(), throwsA(isA<VeilApiException>()));

      expect(relay.devices[deviceId]!.active, isTrue);
      expect(device.session.state.isAuthenticated, isTrue);
      expect(await device.storage.hasDeviceSecretRefs(), isTrue);
    });

    test('a device the relay dropped meanwhile is wiped when it tries to delete the account', () async {
      final relay = FakeAccountRelay();
      final device = await _registered(relay, 'atlas');
      // Revoked from elsewhere between the challenge and the deletion.
      relay.onChallenge = () => relay.devices[device.session.state.deviceId]!.active = false;

      await expectLater(device.session.deleteAccount(), throwsA(isA<VeilApiException>()));

      expect(device.session.state.isAuthenticated, isFalse);
      expect(await device.storage.hasDeviceSecretRefs(), isFalse);
    });

    test('the old device signs its approval over the claimant fingerprint', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);

      await claimed.transfers.approveTransfer(claimed.claimId);

      expect(claimed.transfers.errorMessage, isNull);
      final session = relay.transfers[claimed.transfers.transferSessionId]!;
      expect(session.claim!.approved, isTrue);
      expect(claimed.transfers.transferStatus, contains(session.claim!.claimantFingerprint));
    });

    test('an approval this device cannot sign is refused and the claim stays unapproved', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);
      final foreign = await createDefaultCryptoAdapter().deviceAuth.generateAuthKeyMaterial();
      await claimed.oldDevice.store.write(key: 'veil.auth.private_key', value: foreign.privateKey);
      await claimed.oldDevice.store.write(key: 'veil.auth.public_key', value: foreign.publicKey);

      await claimed.transfers.approveTransfer(claimed.claimId);

      expect(claimed.transfers.errorMessage, isNotNull);
      expect(relay.transfers[claimed.transfers.transferSessionId]!.claim!.approved, isFalse);
      await expectLater(
        _complete(claimed.newDevice, claimed.transfers, claimed.claimId),
        throwsA(isA<VeilApiException>().having((e) => e.code, 'code', 'transfer_approval_required')),
      );
    });
  });

  group('transfer completion', () {
    test('a completion whose response was lost is retried and answered with the same device', () async {
      final relay = FakeAccountRelay()..dropCompletionResponses = 1;
      final claimed = await _claimed(relay);
      await claimed.transfers.approveTransfer(claimed.claimId);

      await _complete(claimed.newDevice, claimed.transfers, claimed.claimId);

      final newDeviceId = relay.transfers[claimed.transfers.transferSessionId]!.newDeviceId;
      expect(relay.callsTo('POST /device-transfer/complete'), 2);
      expect(relay.devices.values.where((device) => device.active).map((device) => device.id), [newDeviceId]);
      expect(claimed.newDevice.session.state.isAuthenticated, isTrue);
      expect(claimed.newDevice.session.state.deviceId, newDeviceId);
      expect(await claimed.newDevice.storage.readPendingTransfer(), isNull);
    });

    test('a 5xx before the commit is retried', () async {
      final relay = FakeAccountRelay()..failCompletions = 1;
      final claimed = await _claimed(relay);
      await claimed.transfers.approveTransfer(claimed.claimId);

      await _complete(claimed.newDevice, claimed.transfers, claimed.claimId);

      expect(relay.callsTo('POST /device-transfer/complete'), 2);
      expect(claimed.newDevice.session.state.isAuthenticated, isTrue);
    });

    test('a failed login after the commit is redone without completing again', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);
      await claimed.transfers.approveTransfer(claimed.claimId);
      relay.failChallenges = 1;

      await expectLater(_complete(claimed.newDevice, claimed.transfers, claimed.claimId), throwsA(isA<VeilApiException>()));
      final pending = await claimed.newDevice.storage.readPendingTransfer();
      expect(pending?.newDeviceId, relay.transfers[claimed.transfers.transferSessionId]!.newDeviceId);

      await _complete(claimed.newDevice, claimed.transfers, claimed.claimId);

      expect(relay.callsTo('POST /device-transfer/complete'), 1);
      expect(claimed.newDevice.session.state.isAuthenticated, isTrue);
    });

    test('an app stopped between the commit and the login finishes the login on its next start', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);
      await claimed.transfers.approveTransfer(claimed.claimId);
      relay.failChallenges = 1;
      await expectLater(_complete(claimed.newDevice, claimed.transfers, claimed.claimId), throwsA(isA<VeilApiException>()));

      // A fresh controller over the same keystore, as after the app restarts.
      final restarted = claimed.newDevice.controller();
      await restarted.bootstrap();
      expect(restarted.pendingTransfer?.isCompleted, isTrue);
      await restarted.resumeCompletedTransfer();

      expect(restarted.state.isAuthenticated, isTrue);
      expect(restarted.state.deviceId, relay.transfers[claimed.transfers.transferSessionId]!.newDeviceId);
      expect(relay.callsTo('POST /device-transfer/complete'), 1);
      expect(await claimed.newDevice.storage.hasDeviceSecretRefs(), isTrue);
    });

    test('a committed transfer whose login has not finished is not replaced by a new claim', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);
      await claimed.transfers.approveTransfer(claimed.claimId);
      relay.failChallenges = 1;
      await expectLater(_complete(claimed.newDevice, claimed.transfers, claimed.claimId), throwsA(isA<VeilApiException>()));
      final committed = await claimed.newDevice.storage.readPendingTransfer();

      await expectLater(
        claimed.newDevice.session.claimTransfer(sessionId: 'another-session', transferToken: 'another-token'),
        throwsA(isA<StateError>()),
      );

      final kept = await claimed.newDevice.storage.readPendingTransfer();
      expect(kept?.newDeviceId, committed?.newDeviceId);
      expect(kept?.authKey.privateKey, committed?.authKey.privateKey);
      expect(relay.callsTo('POST /device-transfer/claim'), 1);
    });

    test('the login resumed at start and a tap on the screen log in once', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);
      await claimed.transfers.approveTransfer(claimed.claimId);
      relay.failChallenges = 1;
      await expectLater(_complete(claimed.newDevice, claimed.transfers, claimed.claimId), throwsA(isA<VeilApiException>()));
      final challengesBefore = relay.callsTo('POST /auth/challenge');
      final verifiesBefore = relay.callsTo('POST /auth/verify');

      // The start resumes the login; the screen asks for it meanwhile.
      final restarted = claimed.newDevice.controller();
      await restarted.bootstrap();
      final pending = restarted.pendingTransfer!;
      await restarted.completeTransferAndAuthenticate(
        sessionId: pending.sessionId,
        transferToken: pending.transferToken,
        claimId: pending.claimId,
      );

      expect(restarted.state.isAuthenticated, isTrue);
      expect(relay.callsTo('POST /auth/challenge') - challengesBefore, 1);
      expect(relay.callsTo('POST /auth/verify') - verifiesBefore, 1);
      expect(relay.callsTo('POST /device-transfer/complete'), 1);

      // A run that ended is not joined again: nothing is left to complete.
      await expectLater(
        restarted.completeTransferAndAuthenticate(
          sessionId: pending.sessionId,
          transferToken: pending.transferToken,
          claimId: pending.claimId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a claim this device holds is not sent again for the same session', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);
      final pending = claimed.newDevice.session.pendingTransfer!;

      final restarted = claimed.newDevice.controller();
      await restarted.bootstrap();
      await expectLater(
        restarted.claimTransfer(sessionId: pending.sessionId, transferToken: pending.transferToken),
        throwsA(isA<StateError>()),
      );

      expect(relay.callsTo('POST /device-transfer/claim'), 1);
      expect(relay.transfers[pending.sessionId]!.invalidated, isFalse);
      expect((await claimed.newDevice.storage.readPendingTransfer())?.claimId, claimed.claimId);
      await claimed.transfers.approveTransfer(claimed.claimId);
      await restarted.completeTransferAndAuthenticate(
        sessionId: pending.sessionId,
        transferToken: pending.transferToken,
        claimId: pending.claimId,
      );
      expect(restarted.state.isAuthenticated, isTrue);
    });

    test('a claim survives an app restart and is completed, not claimed again', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);
      await claimed.transfers.approveTransfer(claimed.claimId);

      final restarted = claimed.newDevice.controller();
      await restarted.bootstrap();
      expect(restarted.pendingTransfer?.claimId, claimed.claimId);
      await restarted.completeTransferAndAuthenticate(
        sessionId: restarted.pendingTransfer!.sessionId,
        transferToken: restarted.pendingTransfer!.transferToken,
        claimId: restarted.pendingTransfer!.claimId,
      );

      expect(restarted.state.isAuthenticated, isTrue);
      expect(relay.callsTo('POST /device-transfer/claim'), 1);
    });

    test('completion waits while the old device has not approved yet', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);
      final session = relay.transfers[claimed.transfers.transferSessionId]!;
      var polls = 0;
      relay.onComplete = () {
        polls += 1;
        if (polls == 3) session.claim?.approved = true;
      };

      await _complete(claimed.newDevice, claimed.transfers, claimed.claimId);

      expect(polls, 3);
      expect(claimed.newDevice.session.state.isAuthenticated, isTrue);
    });

    test('a refusal stops at once and keeps the claimed keys', () async {
      final relay = FakeAccountRelay();
      final claimed = await _claimed(relay);
      relay.transfers[claimed.transfers.transferSessionId]!.invalidated = true;

      await expectLater(
        _complete(claimed.newDevice, claimed.transfers, claimed.claimId),
        throwsA(isA<VeilApiException>().having((e) => e.code, 'code', 'transfer_session_inactive')),
      );

      expect(relay.callsTo('POST /device-transfer/complete'), 1);
      final pending = await claimed.newDevice.storage.readPendingTransfer();
      expect(pending?.claimId, claimed.claimId);
      expect(claimed.newDevice.session.pendingTransfer, isNotNull);
    });
  });
}
