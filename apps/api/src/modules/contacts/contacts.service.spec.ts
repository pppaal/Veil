import { randomUUID } from 'node:crypto';

import { ContactsService } from './contacts.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeRealtimeGateway } from '../../../test/support/fake-services';
import { AddContactDto } from './dto/add-contact.dto';

type Seed = {
  prisma: FakePrismaService;
  service: ContactsService;
};

function makeService(): Seed {
  const prisma = new FakePrismaService();
  const gateway = new FakeRealtimeGateway();
  const service = new ContactsService(prisma as never, gateway as never);
  return { prisma, service };
}

function seedUser(prisma: FakePrismaService, handle: string, displayName?: string): string {
  const userId = randomUUID();
  prisma.users.push({
    id: userId,
    handle,
    displayName: displayName ?? handle,
    avatarPath: null,
    status: 'active',
    activeDeviceId: null,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  return userId;
}

function seedProfile(prisma: FakePrismaService, userId: string, avatarPath: string): void {
  prisma.userProfiles.push({
    id: randomUUID(),
    userId,
    bio: null,
    statusMessage: null,
    statusEmoji: null,
    lastStatusAt: null,
    avatarPath,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
}

function buildAddDto(handle: string, nickname?: string): AddContactDto {
  const dto = new AddContactDto();
  dto.handle = handle;
  dto.nickname = nickname;
  return dto;
}

describe('ContactsService', () => {
  describe('addContact', () => {
    it('creates a contact row and returns the resolved handle', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      seedUser(prisma, 'bob');

      const result = await service.addContact(
        { userId: alice },
        buildAddDto('bob', 'Bobby'),
      );

      expect(result.handle).toBe('bob');
      expect(result.nickname).toBe('Bobby');
      expect(prisma.userContacts).toHaveLength(1);
    });

    it('rejects when the handle does not exist', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');

      await expect(
        service.addContact({ userId: alice }, buildAddDto('ghost')),
      ).rejects.toMatchObject({ response: { code: 'contact_not_found' } });
    });

    it('rejects self-add attempts', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');

      await expect(
        service.addContact({ userId: alice }, buildAddDto('alice')),
      ).rejects.toMatchObject({ response: { code: 'cannot_add_self' } });
    });

    it('rejects duplicate contacts', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');
      prisma.userContacts.push({
        id: randomUUID(),
        userId: alice,
        contactUserId: bob,
        nickname: null,
        createdAt: new Date(),
      });

      await expect(
        service.addContact({ userId: alice }, buildAddDto('bob')),
      ).rejects.toMatchObject({ response: { code: 'contact_already_exists' } });
    });
  });

  describe('listContacts', () => {
    it('returns contacts with profile avatar path hydrated', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob', 'Bob Smith');
      seedProfile(prisma, bob, 'profiles/bob.jpg');
      prisma.userContacts.push({
        id: randomUUID(),
        userId: alice,
        contactUserId: bob,
        nickname: 'B',
        createdAt: new Date(),
      });

      const result = await service.listContacts({ userId: alice });

      expect(result).toHaveLength(1);
      expect(result[0]).toMatchObject({
        handle: 'bob',
        displayName: 'Bob Smith',
        nickname: 'B',
        avatarPath: 'profiles/bob.jpg',
      });
    });

    it('returns an empty list when the user has no contacts', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');

      const result = await service.listContacts({ userId: alice });

      expect(result).toEqual([]);
    });
  });

  describe('removeContact', () => {
    it('removes the contact row', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');
      prisma.userContacts.push({
        id: randomUUID(),
        userId: alice,
        contactUserId: bob,
        nickname: null,
        createdAt: new Date(),
      });

      const result = await service.removeContact({ userId: alice }, 'bob');

      expect(result.removed).toBe(true);
      expect(prisma.userContacts).toHaveLength(0);
    });

    it('rejects when handle is unknown', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');

      await expect(
        service.removeContact({ userId: alice }, 'ghost'),
      ).rejects.toMatchObject({ response: { code: 'contact_not_found' } });
    });

    it('rejects when the contact row does not exist', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      seedUser(prisma, 'bob');

      await expect(
        service.removeContact({ userId: alice }, 'bob'),
      ).rejects.toMatchObject({ response: { code: 'contact_not_found' } });
    });
  });
});
