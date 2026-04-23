import { NotFoundException } from '@nestjs/common';

import { UsersService } from './users.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';

describe('UsersService', () => {
  const baseUser = {
    id: 'user-1',
    handle: 'icarus',
    displayName: 'Icarus',
    avatarPath: null,
    status: 'active' as const,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-04-20T00:00:00.000Z'),
  };

  const trustedDevice = (overrides: Partial<{
    id: string;
    userId: string;
    platform: 'ios' | 'android' | 'windows' | 'macos' | 'linux';
    publicIdentityKey: string;
    signedPrekeyBundle: string;
    isActive: boolean;
    revokedAt: Date | null;
    trustedAt: Date;
    lastSeenAt: Date;
  }>) => ({
    id: overrides.id ?? 'device-1',
    userId: overrides.userId ?? 'user-1',
    platform: overrides.platform ?? 'android',
    deviceName: 'Pixel Fold',
    publicIdentityKey: overrides.publicIdentityKey ?? 'pub-1',
    signedPrekeyBundle: overrides.signedPrekeyBundle ?? 'prekey-1',
    authPublicKey: 'auth-1',
    pushToken: null,
    isActive: overrides.isActive ?? true,
    revokedAt: overrides.revokedAt ?? null,
    trustedAt: overrides.trustedAt ?? new Date('2026-03-15T09:00:00.000Z'),
    joinedFromDeviceId: null,
    createdAt: new Date('2026-03-15T09:00:00.000Z'),
    lastSeenAt: overrides.lastSeenAt ?? new Date('2026-04-02T09:00:00.000Z'),
    lastSyncAt: null,
  });

  describe('getUserByHandle', () => {
    it('lowercases the handle before lookup', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: null });
      const service = new UsersService(prisma as never);

      const result = await service.getUserByHandle('ICARUS');

      expect(result.id).toBe('user-1');
      expect(result.handle).toBe('icarus');
    });

    it('throws handle_not_found when no user matches', async () => {
      const prisma = new FakePrismaService();
      const service = new UsersService(prisma as never);

      await expect(service.getUserByHandle('ghost')).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('getKeyBundle', () => {
    it('returns the active device bundle and every trusted device ordered by most recently trusted', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-2' });
      prisma.devices.push(
        trustedDevice({
          id: 'device-1',
          publicIdentityKey: 'pub-old',
          signedPrekeyBundle: 'prekey-old',
          trustedAt: new Date('2026-01-10T00:00:00.000Z'),
          lastSeenAt: new Date('2026-02-01T00:00:00.000Z'),
        }),
        trustedDevice({
          id: 'device-2',
          publicIdentityKey: 'pub-current',
          signedPrekeyBundle: 'prekey-current',
          trustedAt: new Date('2026-04-10T00:00:00.000Z'),
          lastSeenAt: new Date('2026-04-15T00:00:00.000Z'),
        }),
      );
      const service = new UsersService(prisma as never);

      const result = await service.getKeyBundle('icarus');

      expect(result.bundle.deviceId).toBe('device-2');
      expect(result.bundle.identityPublicKey).toBe('pub-current');
      expect(result.deviceBundles.map((b) => b.deviceId)).toEqual(['device-2', 'device-1']);
    });

    it('falls back to the most recently trusted device when activeDeviceId is null', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: null });
      prisma.devices.push(
        trustedDevice({
          id: 'device-1',
          publicIdentityKey: 'pub-old',
          trustedAt: new Date('2026-01-10T00:00:00.000Z'),
        }),
        trustedDevice({
          id: 'device-2',
          publicIdentityKey: 'pub-newer',
          trustedAt: new Date('2026-04-10T00:00:00.000Z'),
        }),
      );
      const service = new UsersService(prisma as never);

      const result = await service.getKeyBundle('icarus');

      expect(result.bundle.deviceId).toBe('device-2');
      expect(result.bundle.identityPublicKey).toBe('pub-newer');
    });

    it('falls back to another trusted device when activeDeviceId points to a revoked device', async () => {
      // The query filters revokedAt:null, so a stale activeDeviceId pointing
      // at a revoked device is simply absent from the fetched list — the
      // fallback picks the head of the trust-ordered list.
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-revoked' });
      prisma.devices.push(
        trustedDevice({
          id: 'device-current',
          publicIdentityKey: 'pub-current',
          trustedAt: new Date('2026-04-10T00:00:00.000Z'),
        }),
      );
      const service = new UsersService(prisma as never);

      const result = await service.getKeyBundle('icarus');

      expect(result.bundle.deviceId).toBe('device-current');
      expect(result.bundle.identityPublicKey).toBe('pub-current');
    });

    it('throws active_device_not_found when the user exists but has no trusted devices', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: null });
      const service = new UsersService(prisma as never);

      await expect(service.getKeyBundle('icarus')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws active_device_not_found when every device is revoked', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-1' });
      prisma.devices.push(
        trustedDevice({
          id: 'device-1',
          isActive: false,
          revokedAt: new Date('2026-04-01T00:00:00.000Z'),
        }),
      );
      const service = new UsersService(prisma as never);

      await expect(service.getKeyBundle('icarus')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws handle_not_found when the user does not exist', async () => {
      const prisma = new FakePrismaService();
      const service = new UsersService(prisma as never);

      await expect(service.getKeyBundle('ghost')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('lowercases the handle before lookup', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-1' });
      prisma.devices.push(trustedDevice({ id: 'device-1' }));
      const service = new UsersService(prisma as never);

      const result = await service.getKeyBundle('ICARUS');

      expect(result.user.handle).toBe('icarus');
    });
  });
});
