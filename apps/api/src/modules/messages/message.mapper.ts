import type { Prisma } from '@prisma/client';
import type { ConversationMessageSummary, OuterAttachmentPointer } from '@veil/contracts';

// Relations every summary needs. senderDevice is not part of the summary
// itself; callers use it to tell a viewer's own messages from incoming ones.
export const MESSAGE_SUMMARY_INCLUDE = {
  senderDevice: { select: { userId: true } },
  receipts: { select: { userId: true, deliveredAt: true, readAt: true } },
} satisfies Prisma.MessageInclude;

export type MessageSummaryRow = Prisma.MessageGetPayload<{
  include: typeof MESSAGE_SUMMARY_INCLUDE;
}>;

// Expired rows are hidden at read time; the retention sweep deletes them
// later, so this filter is what actually enforces expiry for readers.
export const notExpiredWhere = (now: Date): Prisma.MessageWhereInput => ({
  OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
});

export interface MessageSummaryOptions {
  // Receipt timestamps are taken from this user's own receipt only.
  viewerUserId?: string;
  // Fan-out payloads go to many users at once, so they carry no receipt
  // timestamps at all.
  broadcast?: boolean;
}

// Legacy rows stored the full client attachment block. Only the id is ever
// returned, whatever the row holds.
const toOuterAttachmentPointer = (
  attachmentRef: Prisma.JsonValue,
): OuterAttachmentPointer | null => {
  if (attachmentRef && typeof attachmentRef === 'object' && !Array.isArray(attachmentRef)) {
    const attachmentId = attachmentRef['attachmentId'];
    if (typeof attachmentId === 'string') {
      return { attachmentId };
    }
  }
  return null;
};

export const toMessageSummary = (
  row: MessageSummaryRow,
  { viewerUserId, broadcast = false }: MessageSummaryOptions = {},
): ConversationMessageSummary => {
  const receipt =
    broadcast || !viewerUserId
      ? undefined
      : row.receipts.find((candidate) => candidate.userId === viewerUserId);
  return {
    id: row.id,
    clientMessageId: row.clientMessageId,
    conversationId: row.conversationId,
    senderDeviceId: row.senderDeviceId,
    conversationOrder: row.conversationOrder,
    version: row.envelopeVersion,
    ciphertext: row.ciphertext,
    nonce: row.nonce,
    messageType: row.messageType,
    attachment: toOuterAttachmentPointer(row.attachmentRef),
    expiresAt: row.expiresAt?.toISOString() ?? null,
    viewOnce: row.viewOnce,
    serverReceivedAt: row.serverReceivedAt.toISOString(),
    deletedAt: row.deletedAt?.toISOString() ?? null,
    editedAt: row.editedAt?.toISOString() ?? null,
    editCount: row.editCount,
    replyToMessageId: row.replyToMessageId,
    deliveredAt: receipt?.deliveredAt?.toISOString() ?? null,
    readAt: receipt?.readAt?.toISOString() ?? null,
  };
};
