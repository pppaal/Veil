import { NotFoundException } from '@nestjs/common';

import { IS_PUBLIC_KEY } from '../../common/guards/public.decorator';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeSafetyService } from '../../../test/support/fake-services';

const REQUESTER = 'user-requester';

const makeService = (prisma: FakePrismaService, safety = new FakeSafetyService()) =>
  new UsersService(prisma as never, safety as never);

describe('UsersService', () => {
  const baseUser = {
    id: 'user-1',
    handle: 'icarus',
    status: 'active' as const,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-04-20T00:00:00.000Z'),
  };

  describe('getUserByHandle', () => {
    it('lowercases the handle before lookup', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: null });
      const service = makeService(prisma);

      const result = await service.getUserByHandle(REQUESTER, 'ICARUS');

      expect(result.id).toBe('user-1');
      expect(result.handle).toBe('icarus');
    });

    it('returns only id, handle and status', async () => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-1' });
      const service = makeService(prisma);

      expect(await service.getUserByHandle(REQUESTER, 'icarus')).toEqual({
        id: 'user-1',
        handle: 'icarus',
        status: 'active',
      });
    });

    it('throws handle_not_found when no user matches', async () => {
      const prisma = new FakePrismaService();
      const service = makeService(prisma);

      await expect(service.getUserByHandle(REQUESTER, 'ghost')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    // createDirect hides a block behind handle_not_found; this lookup must
    // not give the block away by answering 200 for the same handle.
    it.each([
      ['the user blocked the requester', 'user-1', REQUESTER],
      ['the requester blocked the user', REQUESTER, 'user-1'],
    ])('answers like an unknown handle when %s', async (_case, blocker, blocked) => {
      const prisma = new FakePrismaService();
      prisma.users.push({ ...baseUser, activeDeviceId: 'device-1' });
      const safety = new FakeSafetyService();
      safety.setBlocked(blocker, blocked);
      const service = makeService(prisma, safety);

      await expect(service.getUserByHandle(REQUESTER, 'icarus')).rejects.toMatchObject({
        status: 404,
        response: { code: 'handle_not_found' },
      });
    });
  });
});

describe('UsersController', () => {
  it('GET /users/:handle is not @Public', () => {
    expect(
      Reflect.getMetadata(IS_PUBLIC_KEY, UsersController.prototype.getByHandle),
    ).toBeUndefined();
  });

  it('serves no key material: keys come from the authenticated GET /keys/:handle', () => {
    expect(Object.getOwnPropertyNames(UsersController.prototype).sort()).toEqual([
      'constructor',
      'getByHandle',
    ]);
  });
});
