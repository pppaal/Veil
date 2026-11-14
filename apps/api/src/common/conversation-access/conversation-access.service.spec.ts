import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeSafetyService } from '../../../test/support/fake-services';
import { ConversationAccessService } from './conversation-access.service';

function fixture() {
  const prisma = new FakePrismaService();
  const safety = new FakeSafetyService();
  const access = new ConversationAccessService(prisma as never, safety as never);
  const alice = prisma.seedUser('alice');
  const bob = prisma.seedUser('bob');
  const directId = prisma.seedConversation('direct', [alice.userId, bob.userId], {
    disappearingTimerSeconds: 60,
  });
  return { prisma, safety, access, alice, bob, directId };
}

describe('ConversationAccessService', () => {
  it('returns the conversation and the caller membership for an allowed action', async () => {
    const { access, alice, directId } = fixture();

    const result = await access.requireAccess(alice.userId, directId, 'send');

    expect(result.conversation).toEqual({
      id: directId,
      type: 'direct',
      disappearingTimerSeconds: 60,
      groupUseSenderKeys: false,
      currentEpoch: 0,
    });
    expect(result.member).toMatchObject({ userId: alice.userId, role: 'member' });
    expect(result.member.joinedAt).toBeInstanceOf(Date);
  });

  it('validates the id before querying', async () => {
    const { access, prisma, alice } = fixture();
    const findUnique = jest.spyOn(prisma.conversationMember, 'findUnique');

    await expect(access.requireAccess(alice.userId, 'not-a-uuid', 'send')).rejects.toMatchObject({
      status: 400,
      response: { code: 'validation_failed' },
    });
    expect(findUnique).not.toHaveBeenCalled();
  });

  it('answers non-members and unknown conversations alike', async () => {
    const { access, prisma, directId } = fixture();
    const mallory = prisma.seedUser('mallory');

    for (const conversationId of [directId, '00000000-0000-4000-8000-000000000000']) {
      await expect(
        access.requireAccess(mallory.userId, conversationId, 'readHistory'),
      ).rejects.toMatchObject({
        status: 403,
        response: { code: 'conversation_membership_required' },
      });
    }
  });

  it('refuses a role the policy does not grant', async () => {
    const { access, prisma, alice, bob } = fixture();
    const channelId = prisma.seedConversation('channel', [
      { userId: alice.userId, role: 'owner' },
      { userId: bob.userId, role: 'subscriber' },
    ]);

    await expect(access.requireAccess(bob.userId, channelId, 'send')).rejects.toMatchObject({
      status: 403,
      response: { code: 'conversation_role_required' },
    });
    await expect(access.requireAccess(bob.userId, channelId, 'readHistory')).resolves.toBeDefined();
  });

  it('makes a blocked direct peer unreachable for peer-reaching actions only', async () => {
    const { access, safety, alice, bob, directId } = fixture();
    safety.setBlocked(bob.userId, alice.userId);

    for (const action of ['send', 'edit', 'typing', 'call'] as const) {
      await expect(access.requireAccess(alice.userId, directId, action)).rejects.toMatchObject({
        status: 403,
        response: { code: 'peer_unreachable' },
      });
    }
    for (const action of ['delete', 'readHistory', 'markRead', 'setTimer'] as const) {
      await expect(access.requireAccess(alice.userId, directId, action)).resolves.toBeDefined();
    }
  });

  it('reports a direct peer unreachable after a block in either direction', async () => {
    const { access, safety, alice, bob, directId } = fixture();
    const membership = await access.requireMember(bob.userId, directId);
    expect(await access.isPeerReachable(membership)).toBe(true);

    safety.setBlocked(bob.userId, alice.userId);

    expect(await access.isPeerReachable(membership)).toBe(false);
    expect(await access.isPeerReachable(await access.requireMember(alice.userId, directId))).toBe(
      false,
    );
  });

  it('does not apply direct block rules to groups', async () => {
    const { access, prisma, safety, alice, bob } = fixture();
    const groupId = prisma.seedConversation('group', [alice.userId, bob.userId]);
    safety.setBlocked(bob.userId, alice.userId);

    await expect(access.requireAccess(alice.userId, groupId, 'send')).resolves.toBeDefined();
  });
});
