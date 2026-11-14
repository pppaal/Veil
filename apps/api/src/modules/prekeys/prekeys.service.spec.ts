import { NotFoundException } from '@nestjs/common';

import { DirectoryBudget } from './directory-budget';
import { MAX_UNCONSUMED_PREKEYS_PER_DEVICE } from './dto/upload-prekeys.dto';
import { PrekeysService } from './prekeys.service';
import { FakeEphemeralStoreService, FakeSafetyService } from '../../../test/support/fake-services';

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
  const prisma = {
    $transaction: async (run: (tx: unknown) => Promise<unknown>) => run(prisma),
    // The device row lock an upload takes.
    $queryRaw: jest.fn(async () => [{ '?column?': 1 }]),
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
  };
  return prisma as never;
}

const makeService = (prisma: never, safety = new FakeSafetyService()) =>
  new PrekeysService(
    prisma,
    new DirectoryBudget(new FakeEphemeralStoreService() as never),
    safety as never,
  );

const USER = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const DEVICE = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const activeDevice = { userId: USER, isActive: true, revokedAt: null };
const REQUESTER = {
  userId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
  deviceId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
};

describe('PrekeysService.upload', () => {
  it('stores the batch (skipping duplicates) and returns uploaded + remaining count', async () => {
    const createMany = jest.fn(async () => ({ count: 2 }));
    const count = jest.fn(async () => 42);
    const svc = makeService(
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

  // Unused prekeys are never swept, so the pool a device may hold is capped.
  it('refuses a batch that would leave the device over the unused-prekey cap', async () => {
    const createMany = jest.fn(async () => ({ count: 100 }));
    const count = jest.fn(async () => MAX_UNCONSUMED_PREKEYS_PER_DEVICE + 1);
    const svc = makeService(
      makePrisma({
        device: { findUnique: jest.fn(async () => activeDevice) },
        oneTimePrekey: { createMany, count },
      }),
    );

    await expect(svc.upload(USER, DEVICE, [{ keyId: 1, publicKey: 'pk' }])).rejects.toMatchObject({
      status: 400,
      response: { code: 'validation_failed' },
    });
  });

  it('accepts a batch that fills the pool exactly to the cap', async () => {
    const svc = makeService(
      makePrisma({
        device: { findUnique: jest.fn(async () => activeDevice) },
        oneTimePrekey: {
          createMany: jest.fn(async () => ({ count: 100 })),
          count: jest.fn(async () => MAX_UNCONSUMED_PREKEYS_PER_DEVICE),
        },
      }),
    );

    await expect(svc.upload(USER, DEVICE, [{ keyId: 1, publicKey: 'pk' }])).resolves.toEqual({
      uploaded: 100,
      available: MAX_UNCONSUMED_PREKEYS_PER_DEVICE,
    });
  });

  it('rejects an upload for a device the caller does not own', async () => {
    const svc = makeService(
      makePrisma({
        device: { findUnique: jest.fn(async () => ({ ...activeDevice, userId: 'someone-else' })) },
      }),
    );
    await expect(svc.upload(USER, DEVICE, [{ keyId: 1, publicKey: 'pk' }])).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('rejects an upload from a revoked device', async () => {
    const svc = makeService(
      makePrisma({
        device: { findUnique: jest.fn(async () => ({ ...activeDevice, revokedAt: new Date() })) },
      }),
    );
    await expect(svc.upload(USER, DEVICE, [{ keyId: 1, publicKey: 'pk' }])).rejects.toMatchObject({
      status: 401,
      response: { code: 'device_not_active' },
    });
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
    const svc = makeService(
      makePrisma({ ...resolvableUser, oneTimePrekey: { findFirst, updateMany } }),
    );

    const result = await svc.claim(REQUESTER, 'alice');

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
    const svc = makeService(makePrisma({ ...resolvableUser, oneTimePrekey: { findFirst } }));

    expect(await svc.claim(REQUESTER, 'alice')).toEqual({ deviceId: DEVICE, prekey: null });
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
    const svc = makeService(
      makePrisma({ ...resolvableUser, oneTimePrekey: { findFirst, updateMany } }),
    );

    const result = await svc.claim(REQUESTER, 'alice');

    expect(result).toEqual({ deviceId: DEVICE, prekey: { keyId: 2, publicKey: 'pk2' } });
    expect(updateMany).toHaveBeenCalledTimes(2);
  });

  // A block either way answers exactly like an unknown handle, and spends
  // none of the blocker's prekeys.
  it.each(['the target blocked the requester', 'the requester blocked the target'])(
    'answers like an unknown handle when %s',
    async (direction) => {
      const safety = new FakeSafetyService();
      if (direction === 'the target blocked the requester')
        safety.setBlocked(USER, REQUESTER.userId);
      else safety.setBlocked(REQUESTER.userId, USER);
      const findFirst = jest.fn();
      const svc = makeService(
        makePrisma({ ...resolvableUser, oneTimePrekey: { findFirst } }),
        safety,
      );
      const unknown = makeService(makePrisma({ user: { findUnique: jest.fn(async () => null) } }));

      const blockedRefusal = await svc.claim(REQUESTER, 'alice').catch((error) => error);
      const unknownRefusal = await unknown.claim(REQUESTER, 'ghost').catch((error) => error);

      expect(blockedRefusal.getStatus()).toBe(404);
      expect(blockedRefusal.getResponse()).toEqual(unknownRefusal.getResponse());
      expect(findFirst).not.toHaveBeenCalled();
    },
  );

  it('rejects a claim for an unknown handle', async () => {
    const svc = makeService(makePrisma({ user: { findUnique: jest.fn(async () => null) } }));
    await expect(svc.claim(REQUESTER, 'ghost')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('gives up with prekey=null after losing the race CLAIM_MAX_ATTEMPTS times', async () => {
    // A candidate is always available but every claim loses the race
    // (count:0) — the loop must terminate and report the pool as depleted
    // rather than spin forever.
    const findFirst = jest.fn(async () => ({ id: 'row', keyId: 1, publicKey: 'pk' }));
    const updateMany = jest.fn(async () => ({ count: 0 }));
    const svc = makeService(
      makePrisma({ ...resolvableUser, oneTimePrekey: { findFirst, updateMany } }),
    );

    expect(await svc.claim(REQUESTER, 'alice')).toEqual({ deviceId: DEVICE, prekey: null });
    // 5 attempts (CLAIM_MAX_ATTEMPTS), all lost.
    expect(updateMany).toHaveBeenCalledTimes(5);
  });

  it('rejects when the handle exists but has no active/trusted device', async () => {
    const svc = makeService(
      makePrisma({
        user: { findUnique: jest.fn(async () => ({ id: USER, activeDeviceId: DEVICE })) },
        device: { findMany: jest.fn(async () => []) },
      }),
    );
    await expect(svc.claim(REQUESTER, 'alice')).rejects.toBeInstanceOf(NotFoundException);
  });
});
