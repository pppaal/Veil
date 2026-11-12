import { randomUUID } from 'node:crypto';

import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import {
  FakeEphemeralStoreService,
  FakeRealtimeGateway,
  FakeSafetyService,
} from '../../../test/support/fake-services';
import { CreateGroupDto } from './dto/create-group.dto';
import { GroupsService } from './groups.service';

class GroupRealtimeGateway extends FakeRealtimeGateway {
  readonly deviceEmitted: Array<{ deviceId: string; event: string; payload: unknown }> = [];

  emitToDevice(deviceId: string, event: string, payload: unknown): void {
    this.deviceEmitted.push({ deviceId, event, payload });
  }
}

type User = { userId: string; deviceId: string };

function makeService() {
  const prisma = new FakePrismaService();
  const gateway = new GroupRealtimeGateway();
  const ephemeralStore = new FakeEphemeralStoreService();
  const safety = new FakeSafetyService();
  const service = new GroupsService(
    prisma as never,
    gateway as never,
    ephemeralStore as never,
    new ConversationAccessService(prisma as never, safety as never),
    safety as never,
  );
  const auth = (user: User) => ({ ...user, handle: 'caller' });
  return { prisma, gateway, ephemeralStore, safety, service, auth };
}

// owner, admin and member in one group.
function groupFixture(options: { groupUseSenderKeys?: boolean; currentEpoch?: number } = {}) {
  const fixture = makeService();
  const owner = fixture.prisma.seedUser('owner');
  const admin = fixture.prisma.seedUser('admin');
  const member = fixture.prisma.seedUser('member');
  const outsider = fixture.prisma.seedUser('outsider');
  const groupId = fixture.prisma.seedConversation(
    'group',
    [
      { userId: owner.userId, role: 'owner' },
      { userId: admin.userId, role: 'admin' },
      { userId: member.userId, role: 'member' },
    ],
    options,
  );
  const roleOf = (user: User) =>
    fixture.prisma.conversationMembers.find(
      (m) => m.conversationId === groupId && m.userId === user.userId,
    )?.role;
  return { ...fixture, owner, admin, member, outsider, groupId, roleOf };
}

const membershipRequired = { status: 403, response: { code: 'conversation_membership_required' } };
const roleRequired = { status: 403, response: { code: 'conversation_role_required' } };

describe('GroupsService', () => {
  describe('createGroup', () => {
    it('always makes the caller the owner and excludes them from member handles', async () => {
      const { service, prisma, auth } = makeService();
      const alice = prisma.seedUser('alice');
      prisma.seedUser('bob');

      const result = await service.createGroup(auth(alice), {
        name: 'Coven',
        memberHandles: ['alice', 'bob'],
      });

      expect(result.members.map((m) => [m.handle, m.role]).sort()).toEqual([
        ['alice', 'owner'],
        ['bob', 'member'],
      ]);
    });

    it('seeds an epoch-0 membership window for every founding member', async () => {
      const { service, prisma, auth } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');

      const result = await service.createGroup(auth(alice), {
        name: 'Coven',
        memberHandles: ['bob'],
      });

      expect(prisma.groupMemberEpochs).toEqual(
        expect.arrayContaining([
          { conversationId: result.id, userId: alice.userId, joinedEpoch: 0 },
          { conversationId: result.id, userId: bob.userId, joinedEpoch: 0 },
        ]),
      );
      expect(prisma.groupMemberEpochs).toHaveLength(2);
    });

    it('opts the new group into Sender Keys when requested and defaults it off', async () => {
      const { service, prisma, auth } = makeService();
      const alice = prisma.seedUser('alice');

      const withKeys = await service.createGroup(auth(alice), { name: 'A', useSenderKeys: true });
      const withoutKeys = await service.createGroup(auth(alice), { name: 'B' });

      expect(withKeys.useSenderKeys).toBe(true);
      expect(withKeys.epoch).toBe(0);
      expect(withoutKeys.useSenderKeys).toBe(false);
    });

    it('silently drops handles blocked in either direction', async () => {
      const { service, prisma, safety, auth } = makeService();
      const alice = prisma.seedUser('alice');
      const blocker = prisma.seedUser('blocker');
      const blocked = prisma.seedUser('blocked');
      prisma.seedUser('friend');
      safety.setBlocked(blocker.userId, alice.userId);
      safety.setBlocked(alice.userId, blocked.userId);

      const result = await service.createGroup(auth(alice), {
        name: 'Coven',
        memberHandles: ['blocker', 'blocked', 'friend'],
      });

      expect(result.members.map((m) => m.handle).sort()).toEqual(['alice', 'friend']);
    });

    it('DTO rejects 25 handles', async () => {
      const handles = (count: number) => Array.from({ length: count }, (_, i) => `user${i}`);

      const tooMany = await validate(
        plainToInstance(CreateGroupDto, { name: 'Big', memberHandles: handles(25) }),
      );
      const atCap = await validate(
        plainToInstance(CreateGroupDto, { name: 'Big', memberHandles: handles(24) }),
      );
      const duplicated = await validate(
        plainToInstance(CreateGroupDto, { name: 'Dup', memberHandles: ['bob', 'bob'] }),
      );

      expect(tooMany.map((error) => error.property)).toEqual(['memberHandles']);
      expect(tooMany[0]?.constraints).toHaveProperty('arrayMaxSize');
      expect(atCap).toEqual([]);
      expect(duplicated[0]?.constraints).toHaveProperty('arrayUnique');
    });
  });

  describe('getGroup', () => {
    it('rejects non-members without revealing the group', async () => {
      const { service, outsider, groupId, auth } = groupFixture();

      await expect(service.getGroup(auth(outsider), groupId)).rejects.toMatchObject(
        membershipRequired,
      );
    });

    it('returns the group when the caller is a member', async () => {
      const { service, member, groupId, auth } = groupFixture();

      const result = await service.getGroup(auth(member), groupId);

      expect(result.id).toBe(groupId);
      expect(result.members).toHaveLength(3);
      expect(result.lastMessage).toBeNull();
    });

    it('hides a lastMessage sent before the viewer joined', async () => {
      const { service, prisma, owner, member, groupId, auth } = groupFixture();
      prisma.conversationMembers.find((m) => m.userId === member.userId)!.joinedAt = new Date(
        Date.now() + 60_000,
      );
      prisma.messages.push({
        id: randomUUID(),
        conversationId: groupId,
        senderDeviceId: owner.deviceId,
        clientMessageId: 'client-early',
        conversationOrder: 1,
        ciphertext: 'early',
        nonce: 'nonce',
        messageType: 'text',
        attachmentId: null,
        attachmentRef: null,
        serverReceivedAt: new Date(),
        deletedAt: null,
        expiresAt: null,
      });

      expect((await service.getGroup(auth(member), groupId)).lastMessage).toBeNull();
      expect((await service.getGroup(auth(owner), groupId)).lastMessage?.ciphertext).toBe('early');
    });

    it('answers a non-group conversation with group_not_found', async () => {
      const { service, prisma, owner, member, auth } = groupFixture();
      const directId = prisma.seedConversation('direct', [owner.userId, member.userId]);

      await expect(service.getGroup(auth(owner), directId)).rejects.toMatchObject({
        status: 404,
        response: { code: 'group_not_found' },
      });
    });
  });

  describe('updateGroup', () => {
    it('rejects plain members', async () => {
      const { service, prisma, member, groupId, auth } = groupFixture();

      await expect(
        service.updateGroup(auth(member), groupId, { name: 'New Name' }),
      ).rejects.toMatchObject(roleRequired);
      expect(prisma.groupMetas[0]?.name).not.toBe('New Name');
    });

    it('rejects non-members', async () => {
      const { service, outsider, groupId, auth } = groupFixture();

      await expect(
        service.updateGroup(auth(outsider), groupId, { name: 'New Name' }),
      ).rejects.toMatchObject(membershipRequired);
    });

    it.each(['owner', 'admin'] as const)('lets the %s update the metadata', async (role) => {
      const fixture = groupFixture();
      const actor = role === 'owner' ? fixture.owner : fixture.admin;

      const result = await fixture.service.updateGroup(fixture.auth(actor), fixture.groupId, {
        name: 'New',
        description: 'Updated',
        isPublic: true,
      });

      expect(result).toMatchObject({ name: 'New', description: 'Updated', isPublic: true });
    });

    it('flips the Sender Keys flag on the conversation when asked', async () => {
      const { service, prisma, owner, groupId, auth } = groupFixture();

      const result = await service.updateGroup(auth(owner), groupId, { useSenderKeys: true });

      expect(result.useSenderKeys).toBe(true);
      expect(prisma.conversations[0]?.groupUseSenderKeys).toBe(true);
    });

    it('does not touch the Sender Keys flag on a metadata-only edit', async () => {
      const { service, prisma, owner, groupId, auth } = groupFixture({ groupUseSenderKeys: true });

      const result = await service.updateGroup(auth(owner), groupId, { name: 'New' });

      expect(result.useSenderKeys).toBe(true);
      expect(prisma.conversations[0]?.groupUseSenderKeys).toBe(true);
    });

    it('disable sender keys 400', async () => {
      const { service, prisma, owner, groupId, auth } = groupFixture({ groupUseSenderKeys: true });

      await expect(
        service.updateGroup(auth(owner), groupId, { useSenderKeys: false }),
      ).rejects.toMatchObject({ status: 400, response: { code: 'sender_keys_irreversible' } });
      expect(prisma.conversations[0]?.groupUseSenderKeys).toBe(true);
    });
  });

  describe('addMember', () => {
    it('rejects plain-member callers before looking the handle up', async () => {
      const { service, prisma, member, groupId, auth } = groupFixture();
      const findUser = jest.spyOn(prisma.user, 'findUnique');

      await expect(
        service.addMember(auth(member), groupId, { handle: 'outsider' }),
      ).rejects.toMatchObject(roleRequired);
      expect(findUser).not.toHaveBeenCalled();
    });

    it('returns the existing membership when the handle is already a member', async () => {
      const { service, prisma, owner, groupId, auth } = groupFixture();
      const membersBefore = prisma.conversationMembers.length;

      const result = await service.addMember(auth(owner), groupId, {
        handle: 'admin',
        role: 'member',
      });

      expect(result.role).toBe('admin');
      expect(prisma.conversationMembers).toHaveLength(membersBefore);
    });

    it('lowercases the handle before lookup', async () => {
      const { service, owner, outsider, groupId, auth, roleOf } = groupFixture();

      const result = await service.addMember(auth(owner), groupId, { handle: 'OUTSIDER' });

      expect(result.userId).toBe(outsider.userId);
      expect(roleOf(outsider)).toBe('member');
    });

    it('26th member 409', async () => {
      const { service, prisma, owner, groupId, auth } = groupFixture();
      // 3 founding members + 21 fillers = 24; the newcomer takes seat 25.
      for (let index = 0; index < 21; index += 1) {
        const filler = prisma.seedUser(`filler${index}`);
        prisma.conversationMembers.push({
          id: randomUUID(),
          conversationId: groupId,
          userId: filler.userId,
          role: 'member',
          joinedAt: new Date(),
        });
      }
      prisma.seedUser('newcomer');
      prisma.seedUser('latecomer');

      await service.addMember(auth(owner), groupId, { handle: 'newcomer' });
      const groupSize = () =>
        prisma.conversationMembers.filter((m) => m.conversationId === groupId);
      expect(groupSize()).toHaveLength(25);

      await expect(
        service.addMember(auth(owner), groupId, { handle: 'latecomer' }),
      ).rejects.toMatchObject({ status: 409, response: { code: 'group_member_limit' } });
      expect(groupSize()).toHaveLength(25);
    });

    it('honours a group memberLimit below the global cap', async () => {
      const fixture = makeService();
      const owner = fixture.prisma.seedUser('owner');
      fixture.prisma.seedUser('guest');
      const groupId = fixture.prisma.seedConversation(
        'group',
        [{ userId: owner.userId, role: 'owner' }],
        { memberLimit: 1 },
      );

      await expect(
        fixture.service.addMember(fixture.auth(owner), groupId, { handle: 'guest' }),
      ).rejects.toMatchObject({ status: 409, response: { code: 'group_member_limit' } });
    });

    it('add of user who blocked actor 404', async () => {
      const { service, prisma, safety, owner, outsider, groupId, auth } = groupFixture();
      safety.setBlocked(outsider.userId, owner.userId);

      await expect(
        service.addMember(auth(owner), groupId, { handle: 'outsider' }),
      ).rejects.toMatchObject({ status: 404, response: { code: 'handle_not_found' } });
      expect(prisma.conversationMembers.some((m) => m.userId === outsider.userId)).toBe(false);
    });
  });

  describe('removeMember', () => {
    it('refuses to remove the group owner', async () => {
      const { service, admin, owner, groupId, auth, roleOf } = groupFixture();

      await expect(service.removeMember(auth(admin), groupId, 'owner')).rejects.toMatchObject({
        status: 409,
        response: { code: 'owner_immutable' },
      });
      expect(roleOf(owner)).toBe('owner');
    });

    it('rejects non-admins even if they target another plain member', async () => {
      const { service, member, groupId, auth } = groupFixture();

      await expect(service.removeMember(auth(member), groupId, 'admin')).rejects.toMatchObject(
        roleRequired,
      );
    });

    it('removes a plain member when the caller is an admin', async () => {
      const { service, admin, member, groupId, auth, roleOf } = groupFixture();

      const result = await service.removeMember(auth(admin), groupId, 'member');

      expect(result).toEqual({ conversationId: groupId, removedUserId: member.userId });
      expect(roleOf(member)).toBeUndefined();
    });
  });

  describe('leaveGroup and ownership', () => {
    it('owner leave without transfer 409', async () => {
      const { service, owner, groupId, auth, roleOf } = groupFixture();

      await expect(service.leaveGroup(auth(owner), groupId)).rejects.toMatchObject({
        status: 409,
        response: { code: 'owner_immutable' },
      });
      expect(roleOf(owner)).toBe('owner');
    });

    it('rejects a caller who is not a member', async () => {
      const { service, outsider, groupId, auth } = groupFixture();

      await expect(service.leaveGroup(auth(outsider), groupId)).rejects.toMatchObject(
        membershipRequired,
      );
    });

    it('lets a plain member leave', async () => {
      const { service, member, groupId, auth, roleOf } = groupFixture();

      const result = await service.leaveGroup(auth(member), groupId);

      expect(result).toEqual({ conversationId: groupId, left: true });
      expect(roleOf(member)).toBeUndefined();
    });

    it('owner transfer then leave works', async () => {
      const { service, prisma, owner, admin, groupId, auth, roleOf } = groupFixture();

      const transfer = await service.transferOwnership(auth(owner), groupId, {
        userId: admin.userId,
      });
      expect(transfer).toEqual({
        conversationId: groupId,
        ownerUserId: admin.userId,
        previousOwnerUserId: owner.userId,
      });
      expect(roleOf(admin)).toBe('owner');
      expect(roleOf(owner)).toBe('admin');
      // Account deletion picks the groups to delete by this column, so it
      // follows the owner role.
      expect(prisma.groupMetas.find((meta) => meta.conversationId === groupId)).toMatchObject({
        createdByUserId: admin.userId,
      });

      await expect(service.leaveGroup(auth(owner), groupId)).resolves.toEqual({
        conversationId: groupId,
        left: true,
      });
      expect(roleOf(owner)).toBeUndefined();
    });

    it('only the owner may transfer ownership, and only to a current member', async () => {
      const { service, owner, admin, outsider, groupId, auth } = groupFixture();

      await expect(
        service.transferOwnership(auth(admin), groupId, { userId: admin.userId }),
      ).rejects.toMatchObject(roleRequired);
      await expect(
        service.transferOwnership(auth(owner), groupId, { userId: outsider.userId }),
      ).rejects.toMatchObject(membershipRequired);
    });
  });

  // Every membership change bumps the conversation epoch, records when a
  // current member joined (a departed member's row goes), and fans
  // group.epoch.bumped out to the current members.
  describe('group epoch bumps', () => {
    const epochEvent = (gateway: GroupRealtimeGateway) =>
      gateway.emitted.filter((e) => e.event === 'group.epoch.bumped');

    it('addMember bumps the epoch and announces a join', async () => {
      const { service, prisma, gateway, owner, outsider, groupId, auth } = groupFixture({
        currentEpoch: 3,
      });

      await service.addMember(auth(owner), groupId, { handle: 'outsider' });

      expect(prisma.conversations[0]?.currentEpoch).toBe(4);
      expect(prisma.groupMemberEpochs).toEqual([
        { conversationId: groupId, userId: outsider.userId, joinedEpoch: 4 },
      ]);
      expect(epochEvent(gateway)[0]?.payload).toEqual({
        conversationId: groupId,
        epoch: 4,
        reason: 'join',
        userId: outsider.userId,
      });
    });

    it('removeMember deletes the member epoch row and announces a leave to remaining members only', async () => {
      const { service, prisma, gateway, owner, admin, member, groupId, auth } = groupFixture({
        currentEpoch: 6,
      });
      prisma.groupMemberEpochs.push(
        { conversationId: groupId, userId: member.userId, joinedEpoch: 0 },
        { conversationId: groupId, userId: admin.userId, joinedEpoch: 0 },
      );

      await service.removeMember(auth(admin), groupId, 'member');

      expect(prisma.conversations[0]?.currentEpoch).toBe(7);
      expect(prisma.groupMemberEpochs).toEqual([
        { conversationId: groupId, userId: admin.userId, joinedEpoch: 0 },
      ]);
      const events = epochEvent(gateway);
      expect(events[0]?.payload).toEqual({
        conversationId: groupId,
        epoch: 7,
        reason: 'leave',
        userId: member.userId,
      });
      expect(events.map((e) => e.userId).sort()).toEqual([owner.userId, admin.userId].sort());
    });

    it('a departed member leaves no epoch row, sync cursor or mute behind in that group', async () => {
      const { service, prisma, admin, member, groupId, auth } = groupFixture({ currentEpoch: 1 });
      const memberSecondDevice = prisma.seedDevice(member.userId);
      const otherGroupId = prisma.seedConversation('group', [member.userId]);
      prisma.groupMemberEpochs.push(
        { conversationId: groupId, userId: member.userId, joinedEpoch: 0 },
        { conversationId: groupId, userId: admin.userId, joinedEpoch: 0 },
        { conversationId: otherGroupId, userId: member.userId, joinedEpoch: 0 },
      );
      const cursor = (deviceId: string, conversationId: string) => ({
        id: randomUUID(),
        deviceId,
        conversationId,
        lastSyncedConversationOrder: 5,
        lastReadConversationOrder: 4,
      });
      prisma.deviceConversationStates.push(
        cursor(member.deviceId, groupId),
        cursor(memberSecondDevice, groupId),
        cursor(admin.deviceId, groupId),
        cursor(member.deviceId, otherGroupId),
      );
      const mute = (userId: string, conversationId: string) => ({
        userId,
        conversationId,
        mutedUntil: null,
        createdAt: new Date(),
      });
      prisma.conversationMutes.push(
        mute(member.userId, groupId),
        mute(admin.userId, groupId),
        mute(member.userId, otherGroupId),
      );

      await service.leaveGroup(auth(member), groupId);

      const namesMemberInGroup = (row: {
        conversationId: string;
        userId?: string;
        deviceId?: string;
      }) =>
        row.conversationId === groupId &&
        (row.userId === member.userId ||
          row.deviceId === member.deviceId ||
          row.deviceId === memberSecondDevice);
      expect(prisma.groupMemberEpochs.filter(namesMemberInGroup)).toEqual([]);
      expect(prisma.deviceConversationStates.filter(namesMemberInGroup)).toEqual([]);
      expect(prisma.conversationMutes.filter(namesMemberInGroup)).toEqual([]);
      // Other members' rows, and the member's rows in other conversations, stay.
      expect(prisma.groupMemberEpochs).toHaveLength(2);
      expect(prisma.deviceConversationStates).toHaveLength(2);
      expect(prisma.conversationMutes).toHaveLength(2);
    });

    it('a member who rejoins gets one fresh epoch row at the new epoch', async () => {
      const { service, prisma, owner, member, groupId, auth } = groupFixture({ currentEpoch: 2 });
      prisma.groupMemberEpochs.push({
        conversationId: groupId,
        userId: member.userId,
        joinedEpoch: 0,
      });

      await service.leaveGroup(auth(member), groupId);
      await service.addMember(auth(owner), groupId, { handle: 'member' });

      expect(prisma.groupMemberEpochs).toEqual([
        { conversationId: groupId, userId: member.userId, joinedEpoch: 4 },
      ]);
    });

    it('leaveGroup bumps the epoch and announces a leave', async () => {
      const { service, gateway, member, groupId, auth } = groupFixture({ currentEpoch: 1 });

      await service.leaveGroup(auth(member), groupId);

      expect(epochEvent(gateway)[0]?.payload).toEqual({
        conversationId: groupId,
        epoch: 2,
        reason: 'leave',
        userId: member.userId,
      });
    });
  });

  describe('key distribution', () => {
    const distribution = (recipientUserId: string, recipientDeviceId?: string) => ({
      recipientUserId,
      recipientDeviceId,
      encryptedChainKey: `opaque-ct-${randomUUID().slice(0, 6)}`,
      nonce: 'nonce-1',
      version: 'veil-group-v1',
    });
    const senderKeysGroup = () => groupFixture({ groupUseSenderKeys: true, currentEpoch: 3 });

    it('buffers each blob and fans out group.key.distribution to each recipient', async () => {
      const { service, gateway, ephemeralStore, owner, admin, member, groupId, auth } =
        senderKeysGroup();
      const setJson = jest.spyOn(ephemeralStore, 'setJson');

      const result = await service.distributeKeys(auth(owner), groupId, {
        epoch: 3,
        distributions: [distribution(admin.userId), distribution(member.userId)],
      });

      expect(result).toEqual({
        conversationId: groupId,
        epoch: 3,
        accepted: 2,
        expiresInSeconds: 30 * 60,
      });
      expect(setJson).toHaveBeenCalledTimes(2);
      expect(setJson.mock.calls.every((call) => (call as unknown[])[2] === 30 * 60)).toBe(true);
      expect(gateway.emitted.map((e) => [e.userId, e.event]).sort()).toEqual(
        [
          [admin.userId, 'group.key.distribution'],
          [member.userId, 'group.key.distribution'],
        ].sort(),
      );
      const pickedUp = await service.getKeyDistributions(auth(admin), groupId);
      expect(pickedUp.distributions).toEqual([
        expect.objectContaining({
          fromUserId: owner.userId,
          fromDeviceId: owner.deviceId,
          recipientDeviceId: null,
        }),
      ]);
    });

    it('routes a device-scoped blob to that device only', async () => {
      const { service, gateway, owner, admin, groupId, auth } = senderKeysGroup();

      await service.distributeKeys(auth(owner), groupId, {
        epoch: 3,
        distributions: [distribution(admin.userId, admin.deviceId)],
      });

      expect(gateway.emitted).toEqual([]);
      expect(gateway.deviceEmitted.map((e) => [e.deviceId, e.event])).toEqual([
        [admin.deviceId, 'group.key.distribution'],
      ]);
    });

    it('device-scoped distributions from two sender devices both survive', async () => {
      const { service, prisma, owner, admin, groupId, auth } = senderKeysGroup();
      const ownerTablet = { userId: owner.userId, deviceId: prisma.seedDevice(owner.userId) };

      await service.distributeKeys(auth(owner), groupId, {
        epoch: 3,
        distributions: [distribution(admin.userId, admin.deviceId)],
      });
      await service.distributeKeys(auth(ownerTablet), groupId, {
        epoch: 3,
        distributions: [distribution(admin.userId, admin.deviceId)],
      });

      const pickedUp = await service.getKeyDistributions(auth(admin), groupId);
      expect(pickedUp.distributions.map((d) => d.fromDeviceId).sort()).toEqual(
        [owner.deviceId, ownerTablet.deviceId].sort(),
      );
      expect(pickedUp.distributions.every((d) => d.recipientDeviceId === admin.deviceId)).toBe(
        true,
      );
    });

    it("never hands one device's blob to a sibling device", async () => {
      const { service, prisma, owner, admin, groupId, auth } = senderKeysGroup();
      const adminLaptop = { userId: admin.userId, deviceId: prisma.seedDevice(admin.userId) };

      await service.distributeKeys(auth(owner), groupId, {
        epoch: 3,
        distributions: [distribution(admin.userId, admin.deviceId)],
      });

      expect((await service.getKeyDistributions(auth(adminLaptop), groupId)).distributions).toEqual(
        [],
      );
    });

    it('rejects a recipientDeviceId that is not an active device of the recipient', async () => {
      const { service, prisma, ephemeralStore, owner, admin, member, groupId, auth } =
        senderKeysGroup();
      const setJson = jest.spyOn(ephemeralStore, 'setJson');
      const revokedDevice = prisma.seedDevice(admin.userId, {
        isActive: false,
        revokedAt: new Date(),
      });

      for (const recipientDeviceId of [member.deviceId, revokedDevice, randomUUID()]) {
        await expect(
          service.distributeKeys(auth(owner), groupId, {
            epoch: 3,
            distributions: [distribution(admin.userId, recipientDeviceId)],
          }),
        ).rejects.toMatchObject({ status: 400, response: { code: 'key_distribution_invalid' } });
      }
      expect(setJson).not.toHaveBeenCalled();
    });

    it('rejects a stale epoch without buffering anything', async () => {
      const { service, ephemeralStore, owner, admin, groupId, auth } = senderKeysGroup();
      const setJson = jest.spyOn(ephemeralStore, 'setJson');

      await expect(
        service.distributeKeys(auth(owner), groupId, {
          epoch: 2,
          distributions: [distribution(admin.userId)],
        }),
      ).rejects.toMatchObject({ status: 409, response: { code: 'group_epoch_stale' } });
      expect(setJson).not.toHaveBeenCalled();
    });

    it('rejects recipients outside the current membership, and self-distribution', async () => {
      const { service, ephemeralStore, owner, admin, outsider, groupId, auth } = senderKeysGroup();
      const setJson = jest.spyOn(ephemeralStore, 'setJson');

      await expect(
        service.distributeKeys(auth(owner), groupId, {
          epoch: 3,
          distributions: [distribution(admin.userId), distribution(outsider.userId)],
        }),
      ).rejects.toMatchObject({ response: { code: 'key_distribution_invalid' } });
      await expect(
        service.distributeKeys(auth(owner), groupId, {
          epoch: 3,
          distributions: [distribution(owner.userId)],
        }),
      ).rejects.toMatchObject({ response: { code: 'key_distribution_invalid' } });
      // All-or-nothing: the valid entry of the mixed batch was not buffered.
      expect(setJson).not.toHaveBeenCalled();
    });

    it('rejects callers who are not members without leaking group state', async () => {
      const { service, admin, outsider, groupId, auth } = senderKeysGroup();

      await expect(
        service.distributeKeys(auth(outsider), groupId, {
          epoch: 3,
          distributions: [distribution(admin.userId)],
        }),
      ).rejects.toMatchObject(membershipRequired);
    });

    it('rejects groups that have not opted into Sender Keys', async () => {
      const { service, owner, admin, groupId, auth } = groupFixture({ currentEpoch: 3 });

      await expect(
        service.distributeKeys(auth(owner), groupId, {
          epoch: 3,
          distributions: [distribution(admin.userId)],
        }),
      ).rejects.toMatchObject({ status: 400, response: { code: 'group_sender_keys_disabled' } });
    });

    it('returns only blobs for the current epoch, non-consuming', async () => {
      const { service, prisma, owner, admin, groupId, auth } = senderKeysGroup();
      await service.distributeKeys(auth(owner), groupId, {
        epoch: 3,
        distributions: [distribution(admin.userId)],
      });

      const first = await service.getKeyDistributions(auth(admin), groupId);
      const second = await service.getKeyDistributions(auth(admin), groupId);
      expect(first.distributions).toHaveLength(1);
      expect(second.distributions).toEqual(first.distributions);

      prisma.conversations[0]!.currentEpoch = 4;
      const afterBump = await service.getKeyDistributions(auth(admin), groupId);
      expect(afterBump).toEqual({ conversationId: groupId, epoch: 4, distributions: [] });
    });
  });
});
