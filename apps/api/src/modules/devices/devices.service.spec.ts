import { ForbiddenException, NotFoundException, UnauthorizedException } from '@nestjs/common';

import { REVOKED_DEVICE_NAME } from '../../common/device-revocation';
import { DevicesService } from './devices.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeRealtimeGateway } from '../../../test/support/fake-services';

const pushConfig = (
  overrides: Partial<{
    pushProvider: string;
    unifiedPushAllowedHosts: string[];
    isProduction: boolean;
  }> = {},
) =>
  ({
    pushProvider: 'none',
    unifiedPushAllowedHosts: [],
    isProduction: false,
    ...overrides,
  }) as never;

// Most cases revoke another device of the caller's; the step-up proof is
// covered on its own below.
const noStepUp = { verifyDeviceStepUp: async () => undefined } as never;

describe('DevicesService', () => {
  it('lists the device graph ordered by active and recent usage', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      noStepUp,
    );

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
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
    expect(
      (listed.items[0] as unknown as { lastTrustedActivityAt?: string | null })
        .lastTrustedActivityAt,
    ).toBe(new Date('2026-04-02T09:00:00.000Z').toISOString());
  });

  it('keeps a device trusted when recent sync activity is newer than last seen', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      noStepUp,
    );

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
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
    const service = new DevicesService(prisma as never, realtime as never, pushConfig(), noStepUp);

    prisma.users.push({
      id: 'user-1',
      handle: 'icarus',
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

    const revoked = await service.revoke('user-1', { deviceId: 'device-1' }, 'caller-device');

    expect(revoked.deviceId).toBe('device-1');
    expect(prisma.devices[0]!.isActive).toBe(false);
    expect(prisma.devices[0]!.revokedAt).not.toBeNull();
    expect(prisma.devices[0]!.pushToken).toBeNull();
    expect(prisma.users[0]!.activeDeviceId).toBe('device-2');
    expect(realtime.disconnectedDevices.has('device-1')).toBe(true);
  });

  it('drops the revoked device label, one-time prekeys and sync cursors, and keeps the others', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      noStepUp,
    );
    const { userId, deviceId: revokedId } = prisma.seedUser('icarus');
    const keptId = prisma.seedDevice(userId);
    for (const deviceId of [revokedId, keptId]) {
      prisma.oneTimePrekeys.push({
        id: `opk-${deviceId}`,
        deviceId,
        keyId: 1,
        publicKey: 'opk-pub',
        consumedAt: null,
        createdAt: new Date(),
      });
      prisma.deviceConversationStates.push({
        id: `state-${deviceId}`,
        deviceId,
        conversationId: 'conversation-1',
        lastSyncedConversationOrder: 3,
        lastReadConversationOrder: 2,
      });
    }

    await service.revoke(userId, { deviceId: revokedId }, 'caller-device');

    const revoked = prisma.devices.find((device) => device.id === revokedId)!;
    expect(revoked.revokedAt).not.toBeNull();
    expect(revoked.deviceName).toBe(REVOKED_DEVICE_NAME);
    expect(prisma.devices.find((device) => device.id === keptId)!.deviceName).toBe('Test device');
    expect(prisma.oneTimePrekeys.map((prekey) => prekey.deviceId)).toEqual([keptId]);
    expect(prisma.deviceConversationStates.map((state) => state.deviceId)).toEqual([keptId]);
  });

  it('rejects revoking a device owned by another user', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      noStepUp,
    );

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

    await expect(
      service.revoke('user-1', { deviceId: 'device-2' }, 'caller-device'),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('fails when the device does not exist', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      noStepUp,
    );

    await expect(
      service.revoke('user-1', { deviceId: 'missing' }, 'caller-device'),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('updates the push token on an active device', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      noStepUp,
    );

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

  it('updatePushToken rejects http:// and private hosts', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig({ pushProvider: 'unifiedpush', isProduction: true }),
      noStepUp,
    );
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
      lastSeenAt: new Date(),
      lastSyncAt: null,
    });

    for (const endpoint of [
      'http://ntfy.example.org/up',
      'http://localhost:8080/up',
      'https://10.0.0.5/up',
      'https://[::ffff:127.0.0.1]/up',
      'https://169.254.169.254/latest/meta-data',
      'https://user:secret@ntfy.example.org/up',
    ]) {
      await expect(service.updatePushToken('user-1', 'device-1', endpoint)).rejects.toMatchObject({
        status: 400,
        response: { code: 'validation_failed' },
      });
    }
    expect(prisma.devices[0]!.pushToken).toBeNull();

    await service.updatePushToken('user-1', 'device-1', 'https://ntfy.example.org/up?id=abc');
    expect(prisma.devices[0]!.pushToken).toBe('https://ntfy.example.org/up?id=abc');
  });

  it('validates URL-shaped push tokens even when another provider is configured', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig({ pushProvider: 'fcm', isProduction: true }),
      noStepUp,
    );

    await expect(
      service.updatePushToken('user-1', 'device-1', 'https://192.168.1.1/up'),
    ).rejects.toMatchObject({ response: { code: 'validation_failed' } });
  });

  it('refuses to update the push token on a revoked device', async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      noStepUp,
    );

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

  it("refuses to update a push token on another user's device", async () => {
    const prisma = new FakePrismaService();
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      noStepUp,
    );

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
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      noStepUp,
    );

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

// Revoking the calling device, or the last active one, cannot be undone (no
// recovery), so it needs the device's signed challenge, not only its token.
describe('DevicesService.revoke step-up', () => {
  function setupRevoke(
    stepUp: (deviceId: string, purpose: string, proof: unknown) => Promise<void>,
  ) {
    const prisma = new FakePrismaService();
    const calls: Array<[string, string]> = [];
    const service = new DevicesService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      pushConfig(),
      {
        verifyDeviceStepUp: async (deviceId: string, purpose: string, proof: unknown) => {
          calls.push([deviceId, purpose]);
          await stepUp(deviceId, purpose, proof);
        },
      } as never,
    );
    const { userId, deviceId: phone } = prisma.seedUser('icarus');
    const laptop = prisma.seedDevice(userId);
    return { prisma, service, calls, userId, phone, laptop };
  }

  it('asks the calling device to sign when it revokes itself', async () => {
    const { service, calls, userId, phone } = setupRevoke(async () => undefined);

    await service.revoke(userId, { deviceId: phone }, phone);

    expect(calls).toEqual([[phone, `device-revoke:${phone}`]]);
  });

  it('asks for a signature when the target is the last active device', async () => {
    const { prisma, service, calls, userId, phone, laptop } = setupRevoke(async () => undefined);
    prisma.devices.find((device) => device.id === phone)!.isActive = false;

    await service.revoke(userId, { deviceId: laptop }, phone);

    expect(calls).toEqual([[phone, `device-revoke:${laptop}`]]);
  });

  it('revokes another device while one stays active without asking', async () => {
    const { service, calls, userId, phone, laptop } = setupRevoke(async () => undefined);

    await service.revoke(userId, { deviceId: laptop }, phone);

    expect(calls).toEqual([]);
  });

  it('leaves the device active when the signature is refused', async () => {
    const { prisma, service, userId, phone } = setupRevoke(async () => {
      throw new UnauthorizedException({ code: 'invalid_device_signature' });
    });

    await expect(service.revoke(userId, { deviceId: phone }, phone)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );

    const device = prisma.devices.find((item) => item.id === phone)!;
    expect(device.isActive).toBe(true);
    expect(device.revokedAt).toBeNull();
  });
});
