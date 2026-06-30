import { ForbiddenException, NotFoundException } from '@nestjs/common';

import { GroupsService } from './groups.service';

// Authorization-focused spec. The FakePrismaService doesn't model groupMeta
// or role-bearing members, and extending it just for these tests adds noise.
// We mock the handful of prisma calls each path actually makes — one test,
// one failure mode.

type MockPrisma = {
  user: {
    findUnique: jest.Mock;
    findMany: jest.Mock;
  };
  conversation: {
    findUnique: jest.Mock;
    create: jest.Mock;
    update: jest.Mock;
  };
  conversationMember: {
    findUnique: jest.Mock;
    findMany: jest.Mock;
    create: jest.Mock;
    delete: jest.Mock;
  };
  groupMeta: {
    update: jest.Mock;
  };
  groupMemberEpoch: {
    upsert: jest.Mock;
    updateMany: jest.Mock;
    createMany: jest.Mock;
  };
  $transaction: jest.Mock;
};

function createPrismaMock(): MockPrisma {
  const prisma: MockPrisma = {
    user: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
    },
    conversation: {
      findUnique: jest.fn(),
      create: jest.fn(),
      // bumpEpochForChange increments and reads back the new epoch.
      update: jest.fn().mockResolvedValue({ currentEpoch: 1 }),
    },
    conversationMember: {
      findUnique: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn(),
      delete: jest.fn(),
    },
    groupMeta: {
      update: jest.fn(),
    },
    groupMemberEpoch: {
      upsert: jest.fn(),
      updateMany: jest.fn(),
      createMany: jest.fn(),
    },
    $transaction: jest.fn(async (cb: (tx: unknown) => Promise<unknown>) => cb(prisma)),
  };
  return prisma;
}

function createRealtimeGatewayMock() {
  return { emitConversationMembers: jest.fn() };
}

function buildService() {
  const prisma = createPrismaMock();
  const realtime = createRealtimeGatewayMock();
  const service = new GroupsService(prisma as never, realtime as never);
  return { prisma, realtime, service };
}

const auth = (userId: string) => ({ userId, deviceId: 'device-1', handle: `h-${userId}` });

describe('GroupsService', () => {
  describe('getGroup', () => {
    it('rejects non-members with forbidden', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue(null);

      await expect(service.getGroup(auth('intruder'), 'conv-1')).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      // Must short-circuit before fetching the conversation — no information
      // about the group (even existence) should leak to a non-member.
      expect(prisma.conversation.findUnique).not.toHaveBeenCalled();
    });

    it('returns the group when the caller is a member', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue({
        conversationId: 'conv-1',
        userId: 'member-1',
        role: 'member',
      });
      prisma.conversation.findUnique.mockResolvedValue({
        id: 'conv-1',
        type: 'group',
        createdAt: new Date('2026-04-20T00:00:00.000Z'),
        groupMeta: { name: 'Coven', description: null, isPublic: false },
        members: [
          {
            userId: 'member-1',
            role: 'member',
            user: { id: 'member-1', handle: 'alice', displayName: 'Alice' },
          },
        ],
        messages: [],
      });

      const result = await service.getGroup(auth('member-1'), 'conv-1');

      expect(result.id).toBe('conv-1');
      expect(result.name).toBe('Coven');
      expect(result.lastMessage).toBeNull();
    });
  });

  describe('updateGroup', () => {
    it('rejects plain members with forbidden', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue({
        conversationId: 'conv-1',
        userId: 'member-1',
        role: 'member',
      });

      await expect(
        service.updateGroup(auth('member-1'), 'conv-1', { name: 'New Name' } as never),
      ).rejects.toBeInstanceOf(ForbiddenException);
      expect(prisma.groupMeta.update).not.toHaveBeenCalled();
    });

    it('rejects non-members with forbidden (no group existence leak)', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue(null);

      await expect(
        service.updateGroup(auth('stranger'), 'conv-1', { name: 'New Name' } as never),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('allows owners to update the group metadata', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue({
        conversationId: 'conv-1',
        userId: 'owner-1',
        role: 'owner',
      });
      prisma.conversation.findUnique.mockResolvedValue({
        id: 'conv-1',
        type: 'group',
        groupMeta: { name: 'Old', description: null, isPublic: false },
      });
      prisma.groupMeta.update.mockResolvedValue({
        name: 'New',
        description: 'Updated',
        isPublic: true,
      });

      const result = await service.updateGroup(auth('owner-1'), 'conv-1', {
        name: 'New',
        description: 'Updated',
        isPublic: true,
      } as never);

      expect(result.name).toBe('New');
      expect(prisma.groupMeta.update).toHaveBeenCalledTimes(1);
    });

    it('allows admins to update the group metadata', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue({
        conversationId: 'conv-1',
        userId: 'admin-1',
        role: 'admin',
      });
      prisma.conversation.findUnique.mockResolvedValue({
        id: 'conv-1',
        type: 'group',
        groupMeta: { name: 'Old', description: null, isPublic: false },
      });
      prisma.groupMeta.update.mockResolvedValue({
        name: 'New',
        description: null,
        isPublic: false,
      });

      await expect(
        service.updateGroup(auth('admin-1'), 'conv-1', { name: 'New' } as never),
      ).resolves.toMatchObject({ name: 'New' });
    });
  });

  describe('removeMember', () => {
    it('refuses to remove the group owner', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique
        // admin asserting themselves (requireAdminOrOwner)
        .mockResolvedValueOnce({ role: 'admin', userId: 'admin-1', conversationId: 'conv-1' })
        // the membership about to be removed
        .mockResolvedValueOnce({ role: 'owner', userId: 'owner-1', conversationId: 'conv-1' });
      prisma.user.findUnique.mockResolvedValue({ id: 'owner-1' });

      await expect(
        service.removeMember(auth('admin-1'), 'conv-1', 'founder'),
      ).rejects.toBeInstanceOf(ForbiddenException);
      expect(prisma.conversationMember.delete).not.toHaveBeenCalled();
    });

    it('rejects non-admins even if they target another plain member', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValueOnce({
        role: 'member',
        userId: 'member-1',
        conversationId: 'conv-1',
      });

      await expect(
        service.removeMember(auth('member-1'), 'conv-1', 'someone-else'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('removes a plain member when caller is admin', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique
        .mockResolvedValueOnce({ role: 'admin', userId: 'admin-1', conversationId: 'conv-1' })
        .mockResolvedValueOnce({ role: 'member', userId: 'member-2', conversationId: 'conv-1' });
      prisma.user.findUnique.mockResolvedValue({ id: 'member-2' });
      prisma.conversationMember.delete.mockResolvedValue(undefined);

      const result = await service.removeMember(auth('admin-1'), 'conv-1', 'bob');

      expect(result).toEqual({ conversationId: 'conv-1', removedUserId: 'member-2' });
      expect(prisma.conversationMember.delete).toHaveBeenCalledTimes(1);
    });
  });

  describe('leaveGroup', () => {
    it('refuses to let the owner leave', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue({
        role: 'owner',
        userId: 'owner-1',
        conversationId: 'conv-1',
      });

      await expect(service.leaveGroup(auth('owner-1'), 'conv-1')).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(prisma.conversationMember.delete).not.toHaveBeenCalled();
    });

    it('throws not-found when caller is not a member', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue(null);

      await expect(service.leaveGroup(auth('stranger'), 'conv-1')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    it('lets a plain member leave', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue({
        role: 'member',
        userId: 'member-1',
        conversationId: 'conv-1',
      });
      prisma.conversationMember.delete.mockResolvedValue(undefined);

      const result = await service.leaveGroup(auth('member-1'), 'conv-1');

      expect(result).toEqual({ conversationId: 'conv-1', left: true });
      expect(prisma.conversationMember.delete).toHaveBeenCalledTimes(1);
    });
  });

  describe('addMember', () => {
    it('rejects plain-member callers even when the handle is valid', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValueOnce({
        role: 'member',
        userId: 'member-1',
        conversationId: 'conv-1',
      });

      await expect(
        service.addMember(auth('member-1'), 'conv-1', { handle: 'newbie' } as never),
      ).rejects.toBeInstanceOf(ForbiddenException);
      expect(prisma.user.findUnique).not.toHaveBeenCalled();
    });

    it('returns the existing membership when handle is already a member (idempotent)', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique
        .mockResolvedValueOnce({ role: 'owner', userId: 'owner-1', conversationId: 'conv-1' })
        .mockResolvedValueOnce({ role: 'admin', userId: 'member-2', conversationId: 'conv-1' });
      prisma.conversation.findUnique.mockResolvedValue({ id: 'conv-1', type: 'group' });
      prisma.user.findUnique.mockResolvedValue({
        id: 'member-2',
        handle: 'bob',
        displayName: 'Bob',
      });

      const result = await service.addMember(auth('owner-1'), 'conv-1', {
        handle: 'bob',
        role: 'member',
      } as never);

      expect(result.role).toBe('admin');
      expect(prisma.conversationMember.create).not.toHaveBeenCalled();
    });

    it('lowercases the handle before lookup', async () => {
      const { prisma, service } = buildService();
      prisma.conversationMember.findUnique
        .mockResolvedValueOnce({ role: 'owner', userId: 'owner-1', conversationId: 'conv-1' })
        .mockResolvedValueOnce(null);
      prisma.conversation.findUnique.mockResolvedValue({ id: 'conv-1', type: 'group' });
      prisma.user.findUnique.mockResolvedValue({
        id: 'new-user',
        handle: 'newbie',
        displayName: null,
      });

      await service.addMember(auth('owner-1'), 'conv-1', { handle: 'NEWBIE' } as never);

      expect(prisma.user.findUnique).toHaveBeenCalledWith(
        expect.objectContaining({ where: expect.objectContaining({ handle: 'newbie' }) }),
      );
    });
  });

  describe('createGroup', () => {
    it('always makes the caller the owner and excludes them from member handles', async () => {
      const { prisma, service } = buildService();
      // caller tries to sneak themselves in as a plain member via memberHandles
      prisma.user.findMany.mockResolvedValue([
        { id: 'user-1' }, // caller — must be deduplicated
        { id: 'user-2' },
      ]);
      prisma.conversation.create.mockResolvedValue({
        id: 'conv-new',
        type: 'group',
        createdAt: new Date('2026-04-23T00:00:00.000Z'),
        groupMeta: { name: 'Coven', description: null, isPublic: false },
        members: [
          {
            userId: 'user-1',
            role: 'owner',
            user: { id: 'user-1', handle: 'alice', displayName: 'Alice' },
          },
          {
            userId: 'user-2',
            role: 'member',
            user: { id: 'user-2', handle: 'bob', displayName: 'Bob' },
          },
        ],
      });

      const result = await service.createGroup(auth('user-1'), {
        name: 'Coven',
        memberHandles: ['alice', 'bob'],
      } as never);

      expect(result.members.find((m) => m.userId === 'user-1')?.role).toBe('owner');
      // user-1 must appear exactly once — not duplicated as a member
      expect(result.members.filter((m) => m.userId === 'user-1')).toHaveLength(1);

      const createCall = prisma.conversation.create.mock.calls[0][0];
      const membersCreated = createCall.data.members.create as Array<{
        userId: string;
        role: string;
      }>;
      expect(membersCreated.filter((m) => m.userId === 'user-1')).toHaveLength(1);
      expect(membersCreated.find((m) => m.userId === 'user-1')?.role).toBe('owner');
    });

    it('seeds an epoch-0 membership window for every founding member', async () => {
      const { prisma, service } = buildService();
      prisma.user.findMany.mockResolvedValue([{ id: 'user-2' }]);
      prisma.conversation.create.mockResolvedValue({
        id: 'conv-new',
        type: 'group',
        createdAt: new Date('2026-04-23T00:00:00.000Z'),
        groupMeta: { name: 'Coven', description: null, isPublic: false },
        members: [
          { userId: 'user-1', role: 'owner', user: { id: 'user-1', handle: 'a', displayName: null } },
          { userId: 'user-2', role: 'member', user: { id: 'user-2', handle: 'b', displayName: null } },
        ],
      });

      await service.createGroup(auth('user-1'), {
        name: 'Coven',
        memberHandles: ['b'],
      } as never);

      expect(prisma.groupMemberEpoch.createMany).toHaveBeenCalledTimes(1);
      const seeded = prisma.groupMemberEpoch.createMany.mock.calls[0][0].data as Array<{
        userId: string;
        joinedEpoch: number;
        leftEpoch: number | null;
      }>;
      expect(seeded).toEqual([
        { conversationId: 'conv-new', userId: 'user-1', joinedEpoch: 0, leftEpoch: null },
        { conversationId: 'conv-new', userId: 'user-2', joinedEpoch: 0, leftEpoch: null },
      ]);
    });
  });

  // Group Sender Keys, phase AB.1: every membership change bumps the
  // conversation epoch, records the member's joined/left window, and fans a
  // group.epoch.bumped event to the current members.
  describe('group epoch bumps', () => {
    const lastEpochEvent = (realtime: { emitConversationMembers: jest.Mock }) =>
      realtime.emitConversationMembers.mock.calls.find(
        (call) => call[1] === 'group.epoch.bumped',
      );

    it('addMember bumps the epoch and announces a join', async () => {
      const { prisma, realtime, service } = buildService();
      prisma.conversationMember.findUnique
        .mockResolvedValueOnce({ role: 'owner', userId: 'owner-1', conversationId: 'conv-1' })
        .mockResolvedValueOnce(null);
      prisma.conversation.findUnique.mockResolvedValue({ id: 'conv-1', type: 'group' });
      prisma.user.findUnique.mockResolvedValue({ id: 'new-user', handle: 'newbie', displayName: null });
      prisma.conversation.update.mockResolvedValue({ currentEpoch: 4 });

      await service.addMember(auth('owner-1'), 'conv-1', { handle: 'newbie' } as never);

      expect(prisma.conversation.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { currentEpoch: { increment: 1 } } }),
      );
      expect(prisma.groupMemberEpoch.upsert).toHaveBeenCalledTimes(1);
      const event = lastEpochEvent(realtime);
      expect(event?.[2]).toEqual({
        conversationId: 'conv-1',
        epoch: 4,
        reason: 'join',
        userId: 'new-user',
      });
    });

    it('removeMember stamps leftEpoch and announces a leave to remaining members only', async () => {
      const { prisma, realtime, service } = buildService();
      prisma.conversationMember.findUnique
        .mockResolvedValueOnce({ role: 'admin', userId: 'admin-1', conversationId: 'conv-1' })
        .mockResolvedValueOnce({ role: 'member', userId: 'member-2', conversationId: 'conv-1' });
      prisma.user.findUnique.mockResolvedValue({ id: 'member-2' });
      prisma.conversationMember.delete.mockResolvedValue(undefined);
      // Remaining members after the removal.
      prisma.conversationMember.findMany.mockResolvedValue([{ userId: 'admin-1' }]);
      prisma.conversation.update.mockResolvedValue({ currentEpoch: 7 });

      await service.removeMember(auth('admin-1'), 'conv-1', 'bob');

      expect(prisma.groupMemberEpoch.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { conversationId: 'conv-1', userId: 'member-2', leftEpoch: null },
          data: { leftEpoch: 7 },
        }),
      );
      const event = lastEpochEvent(realtime);
      expect(event?.[2]).toEqual({
        conversationId: 'conv-1',
        epoch: 7,
        reason: 'leave',
        userId: 'member-2',
      });
      // The removed user must not be told the new epoch.
      const recipients = (event?.[0] as Array<{ userId: string }>).map((m) => m.userId);
      expect(recipients).not.toContain('member-2');
      expect(recipients).toEqual(['admin-1']);
    });

    it('leaveGroup bumps the epoch and announces a leave', async () => {
      const { prisma, realtime, service } = buildService();
      prisma.conversationMember.findUnique.mockResolvedValue({
        role: 'member',
        userId: 'member-1',
        conversationId: 'conv-1',
      });
      prisma.conversationMember.delete.mockResolvedValue(undefined);
      prisma.conversationMember.findMany.mockResolvedValue([{ userId: 'owner-1' }]);
      prisma.conversation.update.mockResolvedValue({ currentEpoch: 2 });

      await service.leaveGroup(auth('member-1'), 'conv-1');

      expect(prisma.groupMemberEpoch.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { conversationId: 'conv-1', userId: 'member-1', leftEpoch: null },
          data: { leftEpoch: 2 },
        }),
      );
      const event = lastEpochEvent(realtime);
      expect(event?.[2]).toEqual({
        conversationId: 'conv-1',
        epoch: 2,
        reason: 'leave',
        userId: 'member-1',
      });
    });
  });
});
