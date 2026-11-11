import { HttpStatus, NotFoundException } from '@nestjs/common';
import { ThrottlerException } from '@nestjs/throttler';

import { IS_PUBLIC_KEY } from '../../common/guards/public.decorator';
import { DirectoryBudget } from '../prekeys/directory-budget';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeEphemeralStoreService } from '../../../test/support/fake-services';

const CLIENT = 'ip:203.0.113.7';

const makeService = (prisma: FakePrismaService, store = new FakeEphemeralStoreService()) =>
  new UsersService(prisma as never, new DirectoryBudget(store as never));

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

  const trustedDevice = (
    overrides: Partial<{
      id: string;
      userId: string;
      platform: 'ios' | 'android' | 'windows' | 'macos' | 'linux';
      publicIdentityKey: string;
      signedPrekeyBundle: string;
      isActive: boolean;
      revokedAt: Date | null;
      trustedAt: Date;
      lastSeenAt: Date;
    }>,
  ) => ({
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
      const service = makeService(prisma);

      const result = await service.getUserByHandle('ICARUS');

      expect(result.id).toBe('user-1');
      expect(result.handle).toBe('icarus');
    });

    it('returns only id, handle and status', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-1' });
      const service = makeService(prisma);

      expect(await service.getUserByHandle('icarus')).toEqual({
        id: 'user-1',
        handle: 'icarus',
        status: 'active',
      });
    });

    it('throws handle_not_found when no user matches', async () => {
      const prisma = new FakePrismaService();
      const service = makeService(prisma);

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
      const service = makeService(prisma);

      const result = await service.getKeyBundle('icarus', CLIENT);

      expect(result.bundle.deviceId).toBe('device-2');
      expect(result.bundle.identityPublicKey).toBe('pub-current');
      expect(result.deviceBundles.map((b) => b.deviceId)).toEqual(['device-2', 'device-1']);
    });

    it('reports unconsumed one-time prekey counts per device without consuming any', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-1' });
      prisma.devices.push(
        trustedDevice({ id: 'device-1', trustedAt: new Date('2026-04-10T00:00:00.000Z') }),
        trustedDevice({ id: 'device-2', trustedAt: new Date('2026-01-10T00:00:00.000Z') }),
      );
      prisma.oneTimePrekeys.push(
        // device-1: two live, one consumed. device-2: none at all.
        {
          id: 'p1',
          deviceId: 'device-1',
          keyId: 1,
          publicKey: 'otpk-1',
          consumedAt: null,
          createdAt: new Date(),
        },
        {
          id: 'p2',
          deviceId: 'device-1',
          keyId: 2,
          publicKey: 'otpk-2',
          consumedAt: null,
          createdAt: new Date(),
        },
        {
          id: 'p3',
          deviceId: 'device-1',
          keyId: 3,
          publicKey: 'otpk-3',
          consumedAt: new Date(),
          createdAt: new Date(),
        },
      );
      const service = makeService(prisma);

      const result = await service.getKeyBundle('icarus', CLIENT);

      expect(result.bundle.oneTimePrekeyAvailable).toBe(2);
      expect(result.deviceBundles.map((b) => [b.deviceId, b.oneTimePrekeyAvailable])).toEqual([
        ['device-1', 2],
        ['device-2', 0],
      ]);
      // Reading the bundle is advisory: nothing was marked consumed.
      expect(prisma.oneTimePrekeys.filter((p) => p.consumedAt === null)).toHaveLength(2);
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
      const service = makeService(prisma);

      const result = await service.getKeyBundle('icarus', CLIENT);

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
      const service = makeService(prisma);

      const result = await service.getKeyBundle('icarus', CLIENT);

      expect(result.bundle.deviceId).toBe('device-current');
      expect(result.bundle.identityPublicKey).toBe('pub-current');
    });

    it('throws active_device_not_found when the user exists but has no trusted devices', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: null });
      const service = makeService(prisma);

      await expect(service.getKeyBundle('icarus', CLIENT)).rejects.toBeInstanceOf(
        NotFoundException,
      );
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
      const service = makeService(prisma);

      await expect(service.getKeyBundle('icarus', CLIENT)).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    it('throws handle_not_found when the user does not exist', async () => {
      const prisma = new FakePrismaService();
      const service = makeService(prisma);

      await expect(service.getKeyBundle('ghost', CLIENT)).rejects.toBeInstanceOf(NotFoundException);
    });

    it('lowercases the handle before lookup', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-1' });
      prisma.devices.push(trustedDevice({ id: 'device-1' }));
      const service = makeService(prisma);

      const result = await service.getKeyBundle('ICARUS', CLIENT);

      expect(result.user.handle).toBe('icarus');
    });

    it('key-bundle response has no displayName/avatarPath/platform', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-1' });
      prisma.devices.push(trustedDevice({ id: 'device-1' }), trustedDevice({ id: 'device-2' }));
      const service = makeService(prisma);

      const result = await service.getKeyBundle('icarus', CLIENT);

      expect(result.user).toEqual({
        id: 'user-1',
        handle: 'icarus',
        status: 'active',
        activeDeviceId: 'device-1',
      });
      for (const bundle of [result.bundle, ...result.deviceBundles]) {
        expect(bundle).not.toHaveProperty('platform');
        expect(bundle).not.toHaveProperty('updatedAt');
      }
      expect(JSON.stringify(result)).not.toMatch(/displayName|avatarPath|Pixel Fold|android/);
    });

    it('key-bundle budget returns 429 after 20 lookups', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-1' });
      prisma.devices.push(trustedDevice({ id: 'device-1' }));
      const store = new FakeEphemeralStoreService();
      const service = makeService(prisma, store);

      for (let lookup = 0; lookup < 20; lookup += 1) {
        await service.getKeyBundle('icarus', CLIENT);
      }

      const rejection = await service.getKeyBundle('ICARUS', CLIENT).catch((error) => error);
      expect(rejection).toBeInstanceOf(ThrottlerException);
      expect(rejection.getStatus()).toBe(HttpStatus.TOO_MANY_REQUESTS);
      // The budget is per (client, handle): another client is unaffected.
      await expect(service.getKeyBundle('icarus', 'ip:198.51.100.1')).resolves.toBeDefined();
    });

    it('spends the budget on unknown handles too, so probing costs the same', async () => {
      const prisma = new FakePrismaService();
      const service = makeService(prisma);

      for (let lookup = 0; lookup < 20; lookup += 1) {
        await expect(service.getKeyBundle('ghost', CLIENT)).rejects.toBeInstanceOf(
          NotFoundException,
        );
      }
      await expect(service.getKeyBundle('ghost', CLIENT)).rejects.toBeInstanceOf(
        ThrottlerException,
      );
    });
  });
});

describe('UsersController', () => {
  it('GET /users/:handle is not @Public', () => {
    expect(
      Reflect.getMetadata(IS_PUBLIC_KEY, UsersController.prototype.getByHandle),
    ).toBeUndefined();
  });

  it('marks the public key-bundle route deprecated with a successor link', async () => {
    const usersService = { getKeyBundle: jest.fn(async () => ({})) };
    const tracker = { trackerFor: jest.fn(async () => CLIENT) };
    const controller = new UsersController(usersService as never, tracker as never);
    const headers = new Map<string, string>();
    const response = { setHeader: (name: string, value: string) => headers.set(name, value) };

    await controller.getKeyBundle('Icarus', {} as never, response as never);

    expect(Reflect.getMetadata(IS_PUBLIC_KEY, UsersController.prototype.getKeyBundle)).toBe(true);
    expect(headers.get('Deprecation')).toBe('true');
    expect(headers.get('Link')).toBe('</v1/keys/icarus>; rel=successor-version');
    expect(usersService.getKeyBundle).toHaveBeenCalledWith('Icarus', CLIENT);
  });
});
