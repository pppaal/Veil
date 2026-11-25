import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { removeConversationMember } from './conversation-departure';

// Callers refuse the owner on a role read outside the departure's
// transaction; the departure itself must refuse one too, so an ownership
// transfer committed in between cannot leave a conversation without an owner.
// The real-Postgres interleaving is in relay-invariants-postgres.spec.ts.
describe('removeConversationMember', () => {
  const setup = () => {
    const prisma = new FakePrismaService();
    const alice = prisma.seedUser('alice');
    const bob = prisma.seedUser('bob');
    const conversationId = prisma.seedConversation('group', [
      { userId: alice.userId, role: 'owner' },
      { userId: bob.userId, role: 'member' },
    ]);
    const roles = () =>
      prisma.conversationMembers
        .filter((member) => member.conversationId === conversationId)
        .map((member) => [member.userId, member.role]);
    return { prisma, alice, bob, conversationId, roles };
  };

  it('takes a member out', async () => {
    const { prisma, alice, bob, conversationId, roles } = setup();

    await removeConversationMember(prisma as never, conversationId, bob.userId);

    expect(roles()).toEqual([[alice.userId, 'owner']]);
  });

  it('refuses to take the owner out and keeps the row', async () => {
    const { prisma, alice, bob, conversationId, roles } = setup();

    await expect(
      removeConversationMember(prisma as never, conversationId, alice.userId),
    ).rejects.toMatchObject({ status: 409, response: { code: 'owner_immutable' } });
    expect(roles()).toEqual([
      [alice.userId, 'owner'],
      [bob.userId, 'member'],
    ]);
  });

  it('answers a departure of someone who is no longer a member', async () => {
    const { prisma, conversationId } = setup();
    const carol = prisma.seedUser('carol');

    await expect(
      removeConversationMember(prisma as never, conversationId, carol.userId),
    ).rejects.toMatchObject({
      status: 403,
      response: { code: 'conversation_membership_required' },
    });
  });
});
