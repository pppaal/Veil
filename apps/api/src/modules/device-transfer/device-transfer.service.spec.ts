import { createHash } from 'node:crypto';

import { Ed25519DeviceAuthVerifier } from '../auth/device-auth-verifier';
import { DeviceTransferService } from './device-transfer.service';
import { DeviceAuthTestHelper } from '../../../test/support/device-auth-test-helper';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import {
  FakeConfigService,
  FakeEphemeralStoreService,
  FakeRealtimeGateway,
} from '../../../test/support/fake-services';

describe('DeviceTransferService', () => {
  it('requires the old trusted device and adds the new one without revoking the old device', async () => {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const config = new FakeConfigService();
    const verifier = new Ed25519DeviceAuthVerifier();
    const keyHelper = new DeviceAuthTestHelper();
    const realtime = new FakeRealtimeGateway();
    const keyPair = keyHelper.createKeyPair();
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
      displayName: null,
      avatarPath: null,
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

    await service.approve({ userId: 'user-1', deviceId: 'device-old' }, {
      sessionId: init.sessionId,
      claimId: claim.claimId,
    });

    const completed = await service.complete({
      sessionId: init.sessionId,
      transferToken: init.transferToken,
      claimId: claim.claimId,
      authProof: keyHelper.createProof({
        challenge: `transfer-complete:${init.sessionId}:${claim.claimId}:${init.transferToken}`,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });

    expect(completed.revokedDeviceId).toBeNull();
    expect(prisma.users[0]!.activeDeviceId).toBe(completed.newDeviceId);
    expect(prisma.devices.find((item) => item.id == 'device-old')!.isActive).toBe(true);
    expect(prisma.devices.find((item) => item.id == completed.newDeviceId)!.joinedFromDeviceId).toBe('device-old');
    expect(realtime.disconnectedDevices.has('device-old')).toBe(false);
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
      displayName: null,
      avatarPath: null,
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
      displayName: null,
      avatarPath: null,
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

  it('rejects initiating a join for a different old device id', async () => {
    const prisma = new FakePrismaService();
    const service = new DeviceTransferService(
      prisma as never,
      new FakeEphemeralStoreService() as never,
      new FakeConfigService() as never,
      new Ed25519DeviceAuthVerifier(),
      new FakeRealtimeGateway() as never,
    );

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
      displayName: null,
      avatarPath: null,
      status: 'active',
      activeDeviceId: 'device-old',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    prisma.devices.push(
      {
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
      },
      {
        id: 'device-other',
        userId: 'user-1',
        platform: 'windows',
        deviceName: 'Desktop',
        publicIdentityKey: 'pub-other',
        signedPrekeyBundle: 'prekey-other',
        authPublicKey: 'auth-other',
        pushToken: null,
        isActive: true,
        revokedAt: null,
        trustedAt: new Date(),
        joinedFromDeviceId: null,
        createdAt: new Date(),
        lastSeenAt: new Date(),
        lastSyncAt: null,
      },
    );

    await expect(
      service.init({ userId: 'user-1', deviceId: 'device-old' }, { oldDeviceId: 'device-other' }),
    ).rejects.toThrow('Transfer must be initiated from the trusted old device');
  });

  it('rejects replaying completion after the join already succeeded', async () => {
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
      displayName: null,
      avatarPath: null,
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
      { sessionId: init.sessionId, claimId: claim.claimId },
    );

    const proof = keyHelper.createProof({
      challenge: `transfer-complete:${init.sessionId}:${claim.claimId}:${init.transferToken}`,
      authPrivateKey: keyPair.authPrivateKey,
    });

    await service.complete({
      sessionId: init.sessionId,
      transferToken: init.transferToken,
      claimId: claim.claimId,
      authProof: proof,
    });

    await expect(
      service.complete({
        sessionId: init.sessionId,
        transferToken: init.transferToken,
        claimId: claim.claimId,
        authProof: proof,
      }),
    ).rejects.toThrow('Transfer session already completed');
  });
});
