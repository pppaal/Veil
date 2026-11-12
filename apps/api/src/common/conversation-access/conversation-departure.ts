import type { Prisma } from '@prisma/client';

type DepartureWriter = Pick<
  Prisma.TransactionClient,
  'conversationMember' | 'deviceConversationState' | 'conversationMute'
>;

/**
 * Takes a user out of a conversation inside the caller's transaction: the
 * membership row, and the per-conversation rows that would otherwise keep
 * naming them as a former member (their devices' sync cursors and their mute
 * setting). A seized database then lists who is in a conversation, not who
 * ever was.
 */
export const removeConversationMember = async (
  tx: DepartureWriter,
  conversationId: string,
  userId: string,
): Promise<void> => {
  await tx.conversationMember.delete({
    where: { conversationId_userId: { conversationId, userId } },
  });
  await tx.deviceConversationState.deleteMany({
    where: { conversationId, device: { userId } },
  });
  await tx.conversationMute.deleteMany({ where: { conversationId, userId } });
};
