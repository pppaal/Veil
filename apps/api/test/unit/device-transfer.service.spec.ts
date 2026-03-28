import { createHash } from 'node:crypto';

import { DeviceTransferService } from '../../src/modules/device-transfer/device-transfer.service';
import { FakePrismaService } from '../support/fake-prisma.service';
import { FakeConfigService, FakeEphemeralStoreService } from '../support/fake-services';

describe('DeviceTransferService', () => {
  it('requires the old active device and revokes it on completion', async () => {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const config = new FakeConfigService();
    const service = new DeviceTransferService(
      prisma as never,
      store as never,
      config as never,
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
      createdAt: new Date(),
      lastSeenAt: new Date(),
    });

    const init = await service.init(
      { userId: 'user-1', deviceId: 'device-old' },
      { oldDeviceId: 'device-old' },
    );

    prisma.transferSessions[0]!.tokenHash = createHash('sha256')
      .update(init.transferToken)
      .digest('hex');

    await service.approve(
      { userId: 'user-1', deviceId: 'device-old' },
      {
        sessionId: init.sessionId,
        newDeviceName: 'iPhone',
        platform: 'ios',
        publicIdentityKey: 'pub-new',
        signedPrekeyBundle: 'prekey-new',
        authPublicKey: 'auth-new',
      },
    );

    const completed = await service.complete({
      sessionId: init.sessionId,
      transferToken: init.transferToken,
    });

    expect(completed.revokedDeviceId).toBe('device-old');
    expect(prisma.users[0]!.activeDeviceId).toBe(completed.newDeviceId);
    expect(prisma.devices.find((item) => item.id == 'device-old')!.isActive).toBe(false);
  });
});
