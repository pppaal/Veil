import { HttpException } from '@nestjs/common';

import { ProfileController } from './profile.controller';
import { ProfileService } from './profile.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';

function setup() {
  const prisma = new FakePrismaService();
  const service = new ProfileService(prisma as never);
  const controller = new ProfileController(service);
  return { prisma, service, controller };
}

const expectProfilePending = (handler: () => unknown) => {
  let thrown: unknown;
  try {
    handler();
  } catch (error) {
    thrown = error;
  }
  expect(thrown).toBeInstanceOf(HttpException);
  expect((thrown as HttpException).getStatus()).toBe(410);
  expect((thrown as HttpException).getResponse()).toMatchObject({ code: 'profile_e2e_pending' });
};

describe('ProfileService', () => {
  it('returns only the user id and handle', async () => {
    const { prisma, service } = setup();
    const { userId } = prisma.seedUser('icarus');

    await expect(service.getProfile({ userId })).resolves.toEqual({ userId, handle: 'icarus' });
  });

  it('answers profile_not_found for a missing user', async () => {
    const { service } = setup();

    await expect(service.getProfile({ userId: 'missing' })).rejects.toMatchObject({
      status: 404,
      response: { code: 'profile_not_found' },
    });
  });
});

describe('ProfileController', () => {
  it('profile PATCH 410', () => {
    expectProfilePending(() => setup().controller.updateProfile());
  });

  it('profile PUT and lookups by handle answer 410 profile_e2e_pending', () => {
    const { controller } = setup();
    expectProfilePending(() => controller.replaceProfile());
    expectProfilePending(() => controller.getPublicProfile());
  });
});
