import { ForbiddenException, NotFoundException } from '@nestjs/common';

import { PrekeysService } from './prekeys.service';

// FakePrismaService doesn't model OneTimePrekey, so we hand-roll the handful
// of prisma methods each path uses.
type Mocks = {
  device?: { findUnique?: jest.Mock; findMany?: jest.Mock };
  user?: { findUnique?: jest.Mock };
  oneTimePrekey?: {
    createMany?: jest.Mock;
    count?: jest.Mock;
    findFirst?: jest.Mock;
    updateMany?: jest.Mock;
  };
};

function makePrisma(m: Mocks) {
  return {
    device: {
      findUnique: m.device?.findUnique ?? jest.fn(),
      findMany: m.device?.findMany ?? jest.fn(),
    },
    user: { findUnique: m.user?.findUnique ?? jest.fn() },
    oneTimePrekey: {
      createMany: m.oneTimePrekey?.createMany ?? jest.fn(),
      count: m.oneTimePrekey?.count ?? jest.fn(),
      findFirst: m.oneTimePrekey?.findFirst ?? jest.fn(),
      updateMany: m.oneTimePrekey?.updateMany ?? jest.fn(),
    },
  } as never;
}

const USER = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const DEVICE = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const activeDevice = { userId: USER, isActive: true, revokedAt: null };

describe('PrekeysService.upload', () => {
  it('stores the batch (skipping duplicates) and returns uploaded + remaining count', async () => {
    const createMany = jest.fn(async () => ({ count: 2 }));
    const count = jest.fn(async () => 42);
    const svc = new PrekeysService(
      makePrisma({
        device: { findUnique: jest.fn(async () => activeDevice) },
        oneTimePrekey: { createMany, count },
      }),
    );

    const result = await svc.upload(USER, DEVICE, [
      { keyId: 1, publicKey: 'pk1' },
      { keyId: 2, publicKey: 'pk2' },
    ]);

    expect(result).toEqual({ uploaded: 2, available: 42 });
    expect(createMany).toHaveBeenCalledWith(expect.objectContaining({ skipDuplicates: true }));
  });

  it('rejects an upload for a device the caller does not own', async () => {
    const svc = new PrekeysService(
      makePrisma({
        device: { findUnique: jest.fn(async () => ({ ...activeDevice, userId: 'someone-else' })) },
      }),
    );
    await expect(svc.upload(USER, DEVICE, [{ keyId: 1, publicKey: 'pk' }])).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('rejects an upload from a revoked device', async () => {
    const svc = new PrekeysService(
      makePrisma({
        device: { findUnique: jest.fn(async () => ({ ...activeDevice, revokedAt: new Date() })) },
      }),
    );
    await expect(svc.upload(USER, DEVICE, [{ keyId: 1, publicKey: 'pk' }])).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });
});

describe('PrekeysService.claim', () => {
  const resolvableUser = {
    user: { findUnique: jest.fn(async () => ({ id: USER, activeDeviceId: DEVICE })) },
    device: { findMany: jest.fn(async () => [{ id: DEVICE }]) },
  };

  it('claims the lowest unused prekey and marks it consumed', async () => {
    const findFirst = jest.fn(async () => ({ id: 'row1', keyId: 7, publicKey: 'pk7' }));
    const updateMany = jest.fn(async () => ({ count: 1 }));
    const svc = new PrekeysService(
      makePrisma({ ...resolvableUser, oneTimePrekey: { findFirst, updateMany } }),
    );

    const result = await svc.claim('alice');

    expect(result).toEqual({ deviceId: DEVICE, prekey: { keyId: 7, publicKey: 'pk7' } });
    expect(updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'row1', consumedAt: null },
        data: expect.objectContaining({ consumedAt: expect.any(Date) }),
      }),
    );
  });

  it('returns prekey=null when the pool is empty', async () => {
    const findFirst = jest.fn(async () => null);
    const svc = new PrekeysService(makePrisma({ ...resolvableUser, oneTimePrekey: { findFirst } }));

    expect(await svc.claim('alice')).toEqual({ deviceId: DEVICE, prekey: null });
  });

  it('retries when it loses the race for a candidate, then succeeds on the next', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValueOnce({ id: 'row1', keyId: 1, publicKey: 'pk1' })
      .mockResolvedValueOnce({ id: 'row2', keyId: 2, publicKey: 'pk2' });
    // First claim loses the race (0 rows updated), second wins.
    const updateMany = jest
      .fn()
      .mockResolvedValueOnce({ count: 0 })
      .mockResolvedValueOnce({ count: 1 });
    const svc = new PrekeysService(
      makePrisma({ ...resolvableUser, oneTimePrekey: { findFirst, updateMany } }),
    );

    const result = await svc.claim('alice');

    expect(result).toEqual({ deviceId: DEVICE, prekey: { keyId: 2, publicKey: 'pk2' } });
    expect(updateMany).toHaveBeenCalledTimes(2);
  });

  it('rejects a claim for an unknown handle', async () => {
    const svc = new PrekeysService(makePrisma({ user: { findUnique: jest.fn(async () => null) } }));
    await expect(svc.claim('ghost')).rejects.toBeInstanceOf(NotFoundException);
  });
});
