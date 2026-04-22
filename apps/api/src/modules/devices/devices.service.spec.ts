import { ForbiddenException, NotFoundException } from '@nestjs/common';

import { DevicesService } from './devices.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeRealtimeGateway } from '../../../test/support/fake-services';

describe('DevicesService', () => {
  it('lists the device graph ordered by active and recent usage', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never, new FakeRealtimeGateway() as never);

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
      displayName: null,
      avatarPath: null,
      status: 'active',
      activeDeviceId: 'device-2',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    prisma.devices.push(
      {
        id: 'device-1',
        userId: 'user-1',
        platform: 'ios',
        deviceName: 'Old iPhone',
        publicIdentityKey: 'pub-1',
        signedPrekeyBundle: 'prekey-1',
        authPublicKey: 'auth-1',
        pushToken: null,
        isActive: false,
        revokedAt: new Date('2026-04-01T09:00:00.000Z'),
        trustedAt: new Date('2026-03-01T09:00:00.000Z'),
        joinedFromDeviceId: null,
        createdAt: new Date('2026-03-01T09:00:00.000Z'),
        lastSeenAt: new Date('2026-03-31T09:00:00.000Z'),
        lastSyncAt: null,
      },
      {
        id: 'device-2',
        userId: 'user-1',
        platform: 'android',
        deviceName: 'Pixel Fold',
        publicIdentityKey: 'pub-2',
        signedPrekeyBundle: 'prekey-2',
        authPublicKey: 'auth-2',
        pushToken: 'push-2',
        isActive: true,
        revokedAt: null,
        trustedAt: new Date('2026-03-15T09:00:00.000Z'),
        joinedFromDeviceId: null,
        createdAt: new Date('2026-03-15T09:00:00.000Z'),
        lastSeenAt: new Date('2026-04-02T09:00:00.000Z'),
        lastSyncAt: new Date('2026-04-02T08:55:00.000Z'),
      },
    );

    const listed = await service.list('user-1', 'device-2');

    expect(listed.activeDeviceId).toBe('device-2');
    expect(listed.items.map((item) => item.id)).toEqual(['device-2', 'device-1']);
    expect(listed.items[0]).toMatchObject({
      id: 'device-2',
      deviceName: 'Pixel Fold',
      platform: 'android',
      isActive: true,
      trustState: 'current',
    });
    expect((listed.items[0] as unknown as { lastTrustedActivityAt?: string | null }).lastTrustedActivityAt).toBe(
      new Date('2026-04-02T09:00:00.000Z').toISOString(),
    );
  });

  it('keeps a device trusted when recent sync activity is newer than last seen', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never, new FakeRealtimeGateway() as never);

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
      displayName: null,
      avatarPath: null,
      status: 'active',
      activeDeviceId: 'device-current',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    prisma.devices.push(
      {
        id: 'device-current',
        userId: 'user-1',
        platform: 'android',
        deviceName: 'Pixel',
        publicIdentityKey: 'pub-1',
        signedPrekeyBundle: 'prekey-1',
        authPublicKey: 'auth-1',
        pushToken: 'push-current',
        isActive: true,
        revokedAt: null,
        trustedAt: new Date('2026-03-15T09:00:00.000Z'),
        joinedFromDeviceId: null,
        createdAt: new Date('2026-03-15T09:00:00.000Z'),
        lastSeenAt: new Date('2026-04-02T09:00:00.000Z'),
        lastSyncAt: new Date('2026-04-02T09:05:00.000Z'),
      },
      {
        id: 'device-laptop',
        userId: 'user-1',
        platform: 'windows',
        deviceName: 'Desktop',
        publicIdentityKey: 'pub-2',
        signedPrekeyBundle: 'prekey-2',
        authPublicKey: 'auth-2',
        pushToken: 'push-2',
        isActive: true,
        revokedAt: null,
        trustedAt: new Date('2026-03-16T09:00:00.000Z'),
        joinedFromDeviceId: 'device-current',
        createdAt: new Date('2026-03-16T09:00:00.000Z'),
        lastSeenAt: new Date(Date.now() - 1000 * 60 * 60 * 24 * 45),
        lastSyncAt: new Date(),
      },
    );

    const listed = await service.list('user-1', 'device-current');
    const laptop = listed.items.find((item) => item.id === 'device-laptop');

    expect(laptop).toMatchObject({
      trustState: 'trusted',
      lastTrustedActivityAt: expect.any(String),
    });
  });

  it('revokes the current preferred device and promotes another trusted device when available', async () => {
    const prisma = new FakePrismaService();
    const realtime = new FakeRealtimeGateway();
    const service = new DevicesService(prisma as never, realtime as never);

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
      pushToken: 'push-token',
      isActive: true,
      revokedAt: null,
      trustedAt: new Date(),
      joinedFromDeviceId: null,
      createdAt: new Date(),
      lastSeenAt: new Date(),
      lastSyncAt: null,
    });
    prisma.devices.push({
      id: 'device-2',
      userId: 'user-1',
      platform: 'windows',
      deviceName: 'Desktop',
      publicIdentityKey: 'pub-2',
      signedPrekeyBundle: 'prekey-2',
      authPublicKey: 'auth-2',
      pushToken: 'push-2',
      isActive: true,
      revokedAt: null,
      trustedAt: new Date(Date.now() - 1000),
      joinedFromDeviceId: 'device-1',
      createdAt: new Date(),
      lastSeenAt: new Date(Date.now() + 1000),
      lastSyncAt: new Date(),
    });

    const revoked = await service.revoke('user-1', { deviceId: 'device-1' });

    expect(revoked.deviceId).toBe('device-1');
    expect(prisma.devices[0]!.isActive).toBe(false);
    expect(prisma.devices[0]!.revokedAt).not.toBeNull();
    expect(prisma.devices[0]!.pushToken).toBeNull();
    expect(prisma.users[0]!.activeDeviceId).toBe('device-2');
    expect(realtime.disconnectedDevices.has('device-1')).toBe(true);
  });

  it('rejects revoking a device owned by another user', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never, new FakeRealtimeGateway() as never);

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
      trustedAt: new Date(),
      joinedFromDeviceId: null,
      createdAt: new Date(),
      lastSeenAt: new Date(),
      lastSyncAt: null,
    });

    await expect(service.revoke('user-1', { deviceId: 'device-2' })).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('fails when the device does not exist', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never, new FakeRealtimeGateway() as never);

    await expect(service.revoke('user-1', { deviceId: 'missing' })).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('updates the push token on an active device', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never, new FakeRealtimeGateway() as never);

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
      trustedAt: new Date(),
      joinedFromDeviceId: null,
      createdAt: new Date(),
      lastSeenAt: new Date('2026-01-01T00:00:00.000Z'),
      lastSyncAt: null,
    });

    const result = await service.updatePushToken('user-1', 'device-1', 'fcm-token-xyz');

    expect(result.deviceId).toBe('device-1');
    expect(prisma.devices[0]!.pushToken).toBe('fcm-token-xyz');
    expect(prisma.devices[0]!.lastSeenAt.getTime()).toBeGreaterThan(
      new Date('2026-01-01T00:00:00.000Z').getTime(),
    );
  });

  it('refuses to update the push token on a revoked device', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never, new FakeRealtimeGateway() as never);

    prisma.devices.push({
      id: 'device-1',
      userId: 'user-1',
      platform: 'android',
      deviceName: 'Pixel',
      publicIdentityKey: 'pub',
      signedPrekeyBundle: 'prekey',
      authPublicKey: 'auth',
      pushToken: null,
      isActive: false,
      revokedAt: new Date(),
      trustedAt: new Date(),
      joinedFromDeviceId: null,
      createdAt: new Date(),
      lastSeenAt: new Date(),
      lastSyncAt: null,
    });

    await expect(
      service.updatePushToken('user-1', 'device-1', 'fcm-token-xyz'),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('refuses to update a push token on another user\'s device', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never, new FakeRealtimeGateway() as never);

    prisma.devices.push({
      id: 'device-1',
      userId: 'user-2',
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

    await expect(
      service.updatePushToken('user-1', 'device-1', 'fcm-token-xyz'),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('clears the push token', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(prisma as never, new FakeRealtimeGateway() as never);

    prisma.devices.push({
      id: 'device-1',
      userId: 'user-1',
      platform: 'android',
      deviceName: 'Pixel',
      publicIdentityKey: 'pub',
      signedPrekeyBundle: 'prekey',
      authPublicKey: 'auth',
      pushToken: 'existing-token',
      isActive: true,
      revokedAt: null,
      trustedAt: new Date(),
      joinedFromDeviceId: null,
      createdAt: new Date(),
      lastSeenAt: new Date(),
      lastSyncAt: null,
    });

    const result = await service.clearPushToken('user-1', 'device-1');
    expect(result.deviceId).toBe('device-1');
    expect(prisma.devices[0]!.pushToken).toBeNull();
  });
});
