import { ForbiddenException, NotFoundException } from '@nestjs/common';

import { DevicesService } from './devices.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';

describe('DevicesService', () => {
  it('revokes the current device and clears activeDeviceId when needed', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never);

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
      displayName: null,
      avatarPath: null,
      status: 'active',
      activeDeviceId: 'device-1',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    prisma.devices.push({
      id: 'device-1',
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

    const revoked = await service.revoke('user-1', { deviceId: 'device-1' });

    expect(revoked.deviceId).toBe('device-1');
    expect(prisma.devices[0]!.isActive).toBe(false);
    expect(prisma.devices[0]!.revokedAt).not.toBeNull();
    expect(prisma.users[0]!.activeDeviceId).toBeNull();
  });

  it('rejects revoking a device owned by another user', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never);

    prisma.devices.push({
      id: 'device-2',
      userId: 'user-2',
      platform: 'ios',
      deviceName: 'iPhone',
      publicIdentityKey: 'pub',
      signedPrekeyBundle: 'prekey',
      authPublicKey: 'auth',
      pushToken: null,
      isActive: true,
      revokedAt: null,
      createdAt: new Date(),
      lastSeenAt: new Date(),
    });

    await expect(service.revoke('user-1', { deviceId: 'device-2' })).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('fails when the device does not exist', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never);

    await expect(service.revoke('user-1', { deviceId: 'missing' })).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});
