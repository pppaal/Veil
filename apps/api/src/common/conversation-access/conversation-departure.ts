import type { Prisma } from '@prisma/client';

import { apiError } from '../errors/api-error';

type DepartureWriter = Pick<
  Prisma.TransactionClient,
  'conversationMember' | 'deviceConversationState' | 'conversationMute' | 'messageReceipt'
>;

/**
 * Takes a user out of a conversation inside the caller's transaction: the
 * membership row, and the per-conversation rows that would otherwise keep
 * naming them as a former member (their devices' sync cursors, their mute
 * setting, and their receipts with the times they received and read each
 * message, which only they were ever shown). A seized database then lists
 * who is in a conversation, not who ever was.
 *
 * The owner is never taken out: callers refuse an owner before they get
 * here, but that check reads the role outside this transaction, and an
 * ownership transfer to this member can commit in between. The delete
 * matches only a non-owner row, and its row lock waits for such a transfer,
 * so the conversation always keeps its one owner.
 */
export const removeConversationMember = async (
  tx: DepartureWriter,
  conversationId: string,
  userId: string,
): Promise<void> => {
  const removed = await tx.conversationMember.deleteMany({
    where: { conversationId, userId, role: { not: 'owner' } },
  });
  if (removed.count !== 1) {
    const stillOwner = await tx.conversationMember.count({
      where: { conversationId, userId, role: 'owner' },
    });
    throw stillOwner > 0
      ? apiError('owner_immutable', 'Transfer ownership before the owner leaves')
      : apiError('conversation_membership_required', 'Not a member of this conversation');
  }
  await tx.deviceConversationState.deleteMany({
    where: { conversationId, device: { userId } },
  });
  await tx.conversationMute.deleteMany({ where: { conversationId, userId } });
  await tx.messageReceipt.deleteMany({ where: { userId, message: { conversationId } } });
};
