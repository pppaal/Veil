import { createHash } from 'node:crypto';

import { ConflictException } from '@nestjs/common';

import { REVOKED_DEVICE_NAME } from '../../src/common/device-revocation';
import { Ed25519DeviceAuthVerifier } from '../../src/modules/auth/device-auth-verifier';
import {
  buildApprovalChallenge,
  DeviceTransferService,
} from '../../src/modules/device-transfer/device-transfer.service';
import { DeviceAuthTestHelper } from '../support/device-auth-test-helper';
import { FakePrismaService } from '../support/fake-prisma.service';
import {
  FakeConfigService,
  FakeEphemeralStoreService,
  FakeRealtimeGateway,
} from '../support/fake-services';

describe('DeviceTransferService', () => {
  it('requires the old trusted device, adds the new one, and revokes the old device atomically', async () => {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const config = new FakeConfigService();
    const verifier = new Ed25519DeviceAuthVerifier();
    const keyHelper = new DeviceAuthTestHelper();
    const realtime = new FakeRealtimeGateway();
    const keyPair = keyHelper.createKeyPair();
    const oldKeyPair = keyHelper.createKeyPair();
    const service = new DeviceTransferService(
      prisma as never,
      store as never,
      config as never,
      verifier,
      realtime as never,
    );

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
      status: 'active',
      activeDeviceId: 'device-old',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    prisma.devices.push({
      id: 'device-old',
      userId: 'user-1',
      platform: 'android',
      deviceName: 'Pixel',
      publicIdentityKey: 'pub',
      signedPrekeyBundle: 'prekey',
      authPublicKey: oldKeyPair.authPublicKey,
      pushToken: null,
      isActive: true,
      revokedAt: null,
      trustedAt: new Date(),
      joinedFromDeviceId: null,
      createdAt: new Date(),
      lastSeenAt: new Date(),
      lastSyncAt: null,
    });
    prisma.oneTimePrekeys.push({
      id: 'opk-old',
      deviceId: 'device-old',
      keyId: 1,
      publicKey: 'opk-pub',
      consumedAt: null,
      createdAt: new Date(),
    });
    prisma.deviceConversationStates.push({
      id: 'state-old',
      deviceId: 'device-old',
      conversationId: 'conversation-1',
      lastSyncedConversationOrder: 3,
      lastReadConversationOrder: 2,
    });

    const init = await service.init(
      { userId: 'user-1', deviceId: 'device-old' },
      { oldDeviceId: 'device-old' },
    );

    prisma.transferSessions[0]!.tokenHash = createHash('sha256')
      .update(init.transferToken)
      .digest('hex');

    const claim = await service.claim({
      sessionId: init.sessionId,
      transferToken: init.transferToken,
      newDeviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-new',
      signedPrekeyBundle: 'prekey-new',
      authPublicKey: keyPair.authPublicKey,
      authProof: keyHelper.createProof({
        challenge: `transfer-claim:${init.sessionId}:${init.transferToken}`,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });

    await service.approve(
      { userId: 'user-1', deviceId: 'device-old' },
      {
        sessionId: init.sessionId,
        claimId: claim.claimId,
        approvalProof: keyHelper.createProof({
          challenge: buildApprovalChallenge(
            init.sessionId,
            claim.claimId,
            claim.claimantFingerprint,
          ),
          authPrivateKey: oldKeyPair.authPrivateKey,
        }),
      },
    );

    const completed = await service.complete({
      sessionId: init.sessionId,
      transferToken: init.transferToken,
      claimId: claim.claimId,
      authProof: keyHelper.createProof({
        challenge: `transfer-complete:${init.sessionId}:${claim.claimId}:${init.transferToken}`,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });

    expect(completed.revokedDeviceId).toBe('device-old');
    expect(prisma.users[0]!.activeDeviceId).toBe(completed.newDeviceId);
    const oldDeviceAfter = prisma.devices.find((item) => item.id == 'device-old')!;
    expect(oldDeviceAfter.isActive).toBe(false);
    expect(oldDeviceAfter.revokedAt).toBeInstanceOf(Date);
    expect(oldDeviceAfter.pushToken).toBeNull();
    // A revoked device keeps no label, one-time prekeys or sync cursors.
    expect(oldDeviceAfter.deviceName).toBe(REVOKED_DEVICE_NAME);
    expect(prisma.oneTimePrekeys).toEqual([]);
    expect(prisma.deviceConversationStates).toEqual([]);
    expect(
      prisma.devices.find((item) => item.id == completed.newDeviceId)!.joinedFromDeviceId,
    ).toBe('device-old');
    expect(realtime.disconnectedDevices.has('device-old')).toBe(true);
  });

  it('rejects an expired join session before claim', async () => {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const config = new FakeConfigService();
    const verifier = new Ed25519DeviceAuthVerifier();
    const keyHelper = new DeviceAuthTestHelper();
    const keyPair = keyHelper.createKeyPair();
    const service = new DeviceTransferService(
      prisma as never,
      store as never,
      config as never,
      verifier,
      new FakeRealtimeGateway() as never,
    );

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
      status: 'active',
      activeDeviceId: 'device-old',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    prisma.devices.push({
      id: 'device-old',
      userId: 'user-1',
      platform: 'android',
      deviceName: 'Pixel',
      publicIdentityKey: 'pub',
      signedPrekeyBundle: 'prekey',
      authPublicKey: 'auth',
      pushToken: null,
      isActive: true,
      revokedAt: null,
      trustedAt: new Date(),
      joinedFromDeviceId: null,
      createdAt: new Date(),
      lastSeenAt: new Date(),
      lastSyncAt: null,
    });

    const init = await service.init(
      { userId: 'user-1', deviceId: 'device-old' },
      { oldDeviceId: 'device-old' },
    );
    prisma.transferSessions[0]!.tokenHash = createHash('sha256')
      .update(init.transferToken)
      .digest('hex');
    prisma.transferSessions[0]!.expiresAt = new Date(Date.now() - 1000);

    await expect(
      service.claim({
        sessionId: init.sessionId,
        transferToken: init.transferToken,
        newDeviceName: 'VEIL Desktop',
        platform: 'windows',
        publicIdentityKey: 'pub-new',
        signedPrekeyBundle: 'prekey-new',
        authPublicKey: keyPair.authPublicKey,
        authProof: keyHelper.createProof({
          challenge: `transfer-claim:${init.sessionId}:${init.transferToken}`,
          authPrivateKey: keyPair.authPrivateKey,
        }),
      }),
    ).rejects.toThrow('Transfer session is no longer active');
  });

  it('marks expired open sessions completed when a fresh init begins', async () => {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const config = new FakeConfigService();
    const service = new DeviceTransferService(
      prisma as never,
      store as never,
      config as never,
      new Ed25519DeviceAuthVerifier(),
      new FakeRealtimeGateway() as never,
    );

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
      status: 'active',
      activeDeviceId: 'device-old',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    prisma.devices.push({
      id: 'device-old',
      userId: 'user-1',
      platform: 'android',
      deviceName: 'Pixel',
      publicIdentityKey: 'pub',
      signedPrekeyBundle: 'prekey',
      authPublicKey: 'auth',
      pushToken: null,
      isActive: true,
      revokedAt: null,
      trustedAt: new Date(),
      joinedFromDeviceId: null,
      createdAt: new Date(),
      lastSeenAt: new Date(),
      lastSyncAt: null,
    });
    prisma.transferSessions.push({
      id: 'expired-session',
      userId: 'user-1',
      oldDeviceId: 'device-old',
      tokenHash: 'stale',
      expiresAt: new Date(Date.now() - 1000),
      completedAt: null,
      createdAt: new Date(Date.now() - 5000),
    });
    await store.setJson('transfer:claim:expired-session', {
      claimId: 'claim-stale',
    });

    const fresh = await service.init(
      { userId: 'user-1', deviceId: 'device-old' },
      { oldDeviceId: 'device-old' },
    );

    expect(fresh.sessionId).not.toBe('expired-session');
    expect(
      prisma.transferSessions.find((item) => item.id === 'expired-session')?.completedAt,
    ).not.toBeNull();
    await expect(store.getJson('transfer:claim:expired-session')).resolves.toBeNull();
  });
});

describe('DeviceTransferService first-claim-wins', () => {
  async function startTransfer(options: { isProduction?: boolean } = {}) {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const keyHelper = new DeviceAuthTestHelper();
    const config = Object.assign(new FakeConfigService(), {
      isProduction: options.isProduction ?? false,
    });
    const oldKeyPair = keyHelper.createKeyPair();
    const service = new DeviceTransferService(
      prisma as never,
      store as never,
      config as never,
      new Ed25519DeviceAuthVerifier(),
      new FakeRealtimeGateway() as never,
    );
    const oldDevice = { userId: 'user-1', deviceId: 'device-old' };
    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
      status: 'active',
      activeDeviceId: 'device-old',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    prisma.devices.push({
      id: 'device-old',
      userId: 'user-1',
      platform: 'android',
      deviceName: 'Pixel',
      publicIdentityKey: 'pub',
      signedPrekeyBundle: 'prekey',
      authPublicKey: oldKeyPair.authPublicKey,
      pushToken: null,
      isActive: true,
      revokedAt: null,
      trustedAt: new Date(),
      joinedFromDeviceId: null,
      createdAt: new Date(),
      lastSeenAt: new Date(),
      lastSyncAt: null,
    });
    const init = await service.init(oldDevice, { oldDeviceId: 'device-old' });

    const claimant = (publicIdentityKey = Buffer.alloc(32, 0x42).toString('base64url')) => {
      const keyPair = keyHelper.createKeyPair();
      return {
        keyPair,
        publicIdentityKey,
        claim: () =>
          service.claim({
            sessionId: init.sessionId,
            transferToken: init.transferToken,
            newDeviceName: 'Claimant',
            platform: 'ios',
            publicIdentityKey,
            signedPrekeyBundle: 'spk',
            authPublicKey: keyPair.authPublicKey,
            authProof: keyHelper.createProof({
              challenge: `transfer-claim:${init.sessionId}:${init.transferToken}`,
              authPrivateKey: keyPair.authPrivateKey,
            }),
          }),
        complete: (claimId: string) =>
          service.complete({
            sessionId: init.sessionId,
            transferToken: init.transferToken,
            claimId,
            authProof: keyHelper.createProof({
              challenge: `transfer-complete:${init.sessionId}:${claimId}:${init.transferToken}`,
              authPrivateKey: keyPair.authPrivateKey,
            }),
          }),
      };
    };
    const status = () => service.getSessionStatus({ sessionId: init.sessionId, auth: oldDevice });
    const signApproval = (
      claimId: string,
      fingerprint: string,
      authPrivateKey = oldKeyPair.authPrivateKey,
    ) =>
      keyHelper.createProof({
        challenge: buildApprovalChallenge(init.sessionId, claimId, fingerprint),
        authPrivateKey,
      });
    const approveSigned = (claimId: string, approvalProof?: string) =>
      service.approve(oldDevice, { sessionId: init.sessionId, claimId, approvalProof });
    // What the old device does: it reads the claimant's fingerprint from the
    // session status it polls, and signs the approval over it.
    const approve = async (claimId: string) => {
      const { pendingClaim } = await status();
      return approveSigned(claimId, signApproval(claimId, pendingClaim?.claimantFingerprint ?? ''));
    };

    const restart = () => service.init(oldDevice, { oldDeviceId: 'device-old' });

    return {
      prisma,
      store,
      init,
      claimant,
      status,
      approve,
      approveSigned,
      signApproval,
      restart,
    };
  }

  const codeOf = async (promise: Promise<unknown>) =>
    promise.then(
      () => 'resolved',
      (error) => (error as { response?: { code?: string } }).response?.code,
    );

  // The completion commits before its response leaves the server. When that
  // response is lost, the new device must be able to ask again: the old
  // device is already revoked, and nothing else tells it its device id.
  it('answers a retried completion exactly as the first and changes nothing', async () => {
    const { prisma, claimant, approve } = await startTransfer();
    const newDevice = claimant();
    const { claimId } = await newDevice.claim();
    await approve(claimId);
    const first = await newDevice.complete(claimId);
    const devicesAfterFirst = JSON.stringify(prisma.devices);

    await expect(newDevice.complete(claimId)).resolves.toEqual(first);

    expect(JSON.stringify(prisma.devices)).toBe(devicesAfterFirst);
    expect(prisma.devices.filter((device) => device.isActive).map((device) => device.id)).toEqual([
      first.newDeviceId,
    ]);
  });

  it('refuses a retried completion signed by any other key', async () => {
    const { prisma, claimant, approve } = await startTransfer();
    const newDevice = claimant();
    const { claimId } = await newDevice.claim();
    await approve(claimId);
    await newDevice.complete(claimId);

    expect(await codeOf(claimant().complete(claimId))).toBe('transfer_completion_invalid');
    expect(prisma.devices).toHaveLength(2);
  });

  it('refuses a retried completion once the new device has been revoked', async () => {
    const { prisma, claimant, approve } = await startTransfer();
    const newDevice = claimant();
    const { claimId } = await newDevice.claim();
    await approve(claimId);
    const first = await newDevice.complete(claimId);
    const created = prisma.devices.find((device) => device.id === first.newDeviceId)!;
    created.isActive = false;
    created.revokedAt = new Date();

    expect(await codeOf(newDevice.complete(claimId))).toBe('transfer_session_inactive');
  });

  // A stolen bearer token of the old device must not be enough to hand the
  // account to the thief's keys: the approval is signed with the old
  // device's auth key over the claim and the fingerprint the user compared.
  // Every relay requires it, whatever VEIL_ENV says.
  describe.each([
    ['a production relay', true],
    ['a development relay', false],
  ])('approval proof on %s', (_relay, isProduction) => {
    it('approves with a signature by the old device over the claim and its fingerprint', async () => {
      const { claimant, approveSigned, signApproval, status } = await startTransfer({
        isProduction,
      });
      const newDevice = claimant();
      const { claimId, claimantFingerprint } = await newDevice.claim();

      await expect(
        approveSigned(claimId, signApproval(claimId, claimantFingerprint)),
      ).resolves.toMatchObject({ approved: true });
      expect((await status()).status).toBe('approved');
      await expect(newDevice.complete(claimId)).resolves.toMatchObject({
        revokedDeviceId: 'device-old',
      });
    });

    it('refuses an approval without a proof, by another key or over another fingerprint', async () => {
      const { claimant, approveSigned, signApproval, status } = await startTransfer({
        isProduction,
      });
      const newDevice = claimant();
      const { claimId, claimantFingerprint } = await newDevice.claim();
      const thief = claimant();

      for (const approvalProof of [
        undefined,
        signApproval(claimId, claimantFingerprint, thief.keyPair.authPrivateKey),
        signApproval(claimId, '0000 '.repeat(15) + '0000'),
      ]) {
        expect(await codeOf(approveSigned(claimId, approvalProof))).toBe(
          'invalid_device_signature',
        );
      }
      expect((await status()).status).toBe('claimed');
      expect(await codeOf(newDevice.complete(claimId))).toBe('transfer_approval_required');
    });

    it("refuses an approval signed by the claimant's own key", async () => {
      const { claimant, approveSigned, signApproval } = await startTransfer({ isProduction });
      const newDevice = claimant();
      const { claimId, claimantFingerprint } = await newDevice.claim();

      expect(
        await codeOf(
          approveSigned(
            claimId,
            signApproval(claimId, claimantFingerprint, newDevice.keyPair.authPrivateKey),
          ),
        ),
      ).toBe('invalid_device_signature');
    });
  });

  it('second claim returns 409 and invalidates session', async () => {
    const { prisma, store, init, claimant, status } = await startTransfer();
    const first = claimant();
    const attacker = claimant();
    await first.claim();

    const rejection = await attacker.claim().catch((error) => error);

    expect(rejection).toBeInstanceOf(ConflictException);
    expect(rejection.getResponse()).toMatchObject({ code: 'transfer_claim_invalid' });
    await expect(store.getJson(`transfer:claim:${init.sessionId}`)).resolves.toBeNull();
    const session = prisma.transferSessions.find((item) => item.id === init.sessionId)!;
    expect(session.completedAt).not.toBeNull();
    expect(await status()).toMatchObject({
      status: 'invalidated',
      completedAt: null,
      pendingClaim: null,
    });
  });

  it('an invalidated session can be neither approved nor completed', async () => {
    const { claimant, approve } = await startTransfer();
    const first = claimant();
    const { claimId } = await first.claim();
    await approve(claimId);
    await claimant()
      .claim()
      .catch(() => undefined);

    expect(await codeOf(approve(claimId))).toBe('transfer_session_inactive');
    expect(await codeOf(first.complete(claimId))).toBe('transfer_session_inactive');
    expect(await codeOf(claimant().claim())).toBe('transfer_session_inactive');
  });

  it('approve with non-first claimId fails', async () => {
    const { claimant, approve, status } = await startTransfer();
    const { claimId } = await claimant().claim();

    expect(await codeOf(approve('00000000-0000-4000-8000-000000000000'))).toBe(
      'transfer_claim_required',
    );
    expect((await status()).pendingClaim?.claimId).toBe(claimId);
    await expect(approve(claimId)).resolves.toMatchObject({ approved: true });
  });

  it('fingerprint is 64 hex', async () => {
    const { claimant, status } = await startTransfer();
    const first = claimant();

    const { claimantFingerprint } = await first.claim();

    const expected = createHash('sha256')
      .update(Buffer.from(first.keyPair.authPublicKey, 'base64url'))
      .update(Buffer.from(first.publicIdentityKey, 'base64url'))
      .digest('hex');
    expect(claimantFingerprint).toMatch(/^([0-9a-f]{4} ){15}[0-9a-f]{4}$/);
    expect(claimantFingerprint.replace(/ /g, '')).toBe(expected);
    expect((await status()).pendingClaim?.claimantFingerprint).toBe(claimantFingerprint);
  });

  it('a claim arriving after expiry leaves the old device seeing expired, not completed', async () => {
    const { prisma, init, claimant, status } = await startTransfer();
    prisma.transferSessions.find((item) => item.id === init.sessionId)!.expiresAt = new Date(
      Date.now() - 1000,
    );

    expect(await codeOf(claimant().claim())).toBe('transfer_session_inactive');
    expect(await status()).toMatchObject({ status: 'expired', completedAt: null });
  });

  it('a session superseded by a new transfer reports expired, not completed', async () => {
    const { claimant, status, restart } = await startTransfer();
    await claimant().claim();

    await restart();

    expect(await status()).toMatchObject({
      status: 'expired',
      completedAt: null,
      pendingClaim: null,
    });
  });

  it('a completed transfer keeps reporting completed after a late claim', async () => {
    const { claimant, approve, status } = await startTransfer();
    const first = claimant();
    const { claimId } = await first.claim();
    await approve(claimId);
    await first.complete(claimId);

    expect(await codeOf(claimant().claim())).toBe('transfer_session_inactive');
    expect((await status()).status).toBe('completed');
  });
});
