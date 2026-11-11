import { NotFoundException } from '@nestjs/common';

import { RelationshipService } from '../safety/relationship.service';
import { SafetyService } from '../safety/safety.service';
import { ProfileService } from './profile.service';
import { RetentionFakePrismaService } from '../../../test/support/fake-prisma-retention';
import { FakeRealtimeGateway } from '../../../test/support/fake-services';

async function setup() {
  const prisma = new RetentionFakePrismaService();
  const relationships = new RelationshipService(
    prisma as never,
    new SafetyService(prisma as never),
  );
  const service = new ProfileService(
    prisma as never,
    new FakeRealtimeGateway() as never,
    relationships,
  );
  const viewerId = await prisma.addUser('viewer');
  const targetId = await prisma.addUser('target');
  prisma.userProfiles.push({
    id: 'profile-target',
    userId: targetId,
    bio: 'sealed bio',
    statusMessage: null,
    statusEmoji: null,
    lastStatusAt: null,
    avatarPath: null,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  const read = () => service.getPublicProfile({ userId: viewerId }, 'TARGET');
  return { prisma, viewerId, targetId, read, service };
}

const expectProfileNotFound = async (promise: Promise<unknown>) => {
  const error = await promise.catch((caught: NotFoundException) => caught);
  expect(error).toBeInstanceOf(NotFoundException);
  expect((error as NotFoundException).getResponse()).toMatchObject({ code: 'profile_not_found' });
};

describe('ProfileService.getPublicProfile', () => {
  it('unrelated user 404', async () => {
    const { read } = await setup();
    await expectProfileNotFound(read());
  });

  it('gives a stranger the same 404 as a missing handle', async () => {
    const { service, viewerId } = await setup();
    await expectProfileNotFound(service.getPublicProfile({ userId: viewerId }, 'ghost'));
  });

  it('a one-way contact is not a relationship', async () => {
    const { prisma, viewerId, targetId, read } = await setup();
    prisma.addContact(viewerId, targetId);

    await expectProfileNotFound(read());
  });

  it('mutual contacts can read', async () => {
    const { prisma, viewerId, targetId, read } = await setup();
    prisma.addMutualContacts(viewerId, targetId);

    await expect(read()).resolves.toMatchObject({ handle: 'target', bio: 'sealed bio' });
  });

  it('conversation peer can read', async () => {
    const { prisma, viewerId, targetId, read } = await setup();
    await prisma.addConversation('direct', [viewerId, targetId]);

    await expect(read()).resolves.toMatchObject({ handle: 'target', bio: 'sealed bio' });
  });

  it('a shared channel is not a relationship', async () => {
    const { prisma, viewerId, targetId, read } = await setup();
    await prisma.addConversation('channel', [viewerId, targetId]);

    await expectProfileNotFound(read());
  });

  it('blocked user 404', async () => {
    for (const blockedByTarget of [true, false]) {
      const { prisma, viewerId, targetId, read } = await setup();
      await prisma.addConversation('group', [viewerId, targetId]);
      prisma.addMutualContacts(viewerId, targetId);
      if (blockedByTarget) {
        prisma.addBlock(targetId, viewerId);
      } else {
        prisma.addBlock(viewerId, targetId);
      }

      await expectProfileNotFound(read());
    }
  });

  it('lets a user read their own profile by handle', async () => {
    const { service, targetId } = await setup();
    await expect(service.getPublicProfile({ userId: targetId }, 'target')).resolves.toMatchObject({
      handle: 'target',
    });
  });
});
