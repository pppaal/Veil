import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type {
  ConversationMessageSummary,
  DeleteLocalMessageResponse,
  MarkMessageReadResponse,
  SendMessageResponse,
} from '@veil/contracts';
import type { EncryptedAttachmentReference } from '@veil/shared';

import { PrismaService } from '../../common/prisma.service';
import {
  badRequest,
  conflict,
  forbidden,
  notFound,
  serviceUnavailable,
} from '../../common/errors/api-error';
import { PushService } from '../push/push.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { SafetyService } from '../safety/safety.service';
import { SendMessageDto } from './dto/send-message.dto';

type PersistedMessage = {
  id: string;
  clientMessageId: string;
  conversationId: string;
  senderDeviceId: string;
  conversationOrder: number;
  ciphertext: string;
  nonce: string;
  messageType: 'text' | 'image' | 'file' | 'system' | 'voice' | 'sticker' | 'reaction' | 'call';
  attachmentRef?: unknown;
  expiresAt: Date | null;
  viewOnce?: boolean;
  serverReceivedAt: Date;
  deletedAt: Date | null;
  receipts?: Array<{ deliveredAt: Date | null; readAt: Date | null }>;
};

@Injectable()
export class MessagesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pushService: PushService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly safetyService: SafetyService,
  ) {}

  async send(
    auth: { userId: string; deviceId: string },
    dto: SendMessageDto,
  ): Promise<SendMessageResponse> {
    if (
      dto.envelope.senderDeviceId !== auth.deviceId ||
      dto.conversationId !== dto.envelope.conversationId
    ) {
      throw forbidden('envelope_context_mismatch', 'Envelope sender context mismatch');
    }

    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId: dto.conversationId,
          userId: auth.userId,
        },
      },
      select: { id: true },
    });

    if (!membership) {
      throw forbidden('conversation_membership_required', 'Conversation membership required');
    }

    const attachmentId =
      typeof dto.envelope.attachment === 'object' &&
      dto.envelope.attachment &&
      'attachmentId' in dto.envelope.attachment
        ? String(dto.envelope.attachment.attachmentId)
        : null;

    if (attachmentId) {
      const attachment = await this.prisma.attachment.findUnique({
        where: { id: attachmentId },
        select: { id: true, uploaderDeviceId: true },
      });

      if (!attachment || attachment.uploaderDeviceId !== auth.deviceId) {
        throw notFound('attachment_not_found', 'Attachment not found for sender device');
      }
    }

    const conversation = await this.prisma.conversation.findUnique({
      where: { id: dto.conversationId },
      select: { type: true, groupUseSenderKeys: true, currentEpoch: true },
    });

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId: dto.conversationId },
      select: { userId: true },
    });

    const recipientUserIds = members
      .map((member) => member.userId)
      .filter((userId) => userId !== auth.userId);

    if (conversation?.type === 'direct') {
      if (recipientUserIds.length !== 1 || dto.envelope.recipientUserId !== recipientUserIds[0]) {
        throw forbidden(
          'direct_peer_mismatch',
          'Envelope recipient does not match direct conversation peer',
        );
      }

      // Either-direction block stops delivery on direct conversations.
      // Groups intentionally don't enforce here: a blocked member is expected
      // to be removed from the group, and per-sender filtering would make
      // conversation ordering diverge across members.
      const peerId = recipientUserIds[0];
      if (await this.safetyService.isBlockedEitherWay(auth.userId, peerId)) {
        throw forbidden('peer_unreachable', 'Peer is unreachable');
      }
    }

    const existing = await this.findExistingMessage(auth.deviceId, dto.clientMessageId);
    if (existing) {
      return {
        message: this.toMessageSummary(existing),
        idempotent: true,
      };
    }

    // Group Sender Keys epoch gate (phase AB.2). Only enforced for groups that
    // have opted in — legacy groups and direct conversations skip it entirely.
    // Runs after the idempotency short-circuit so a retry of an already-accepted
    // message still succeeds even if the epoch has since bumped. A genuinely new
    // send must carry the current membership generation; a stale epoch (e.g. a
    // member was removed and the epoch bumped after the sender last synced) is
    // rejected so the client refetches and re-encrypts.
    if (conversation?.type === 'group' && conversation.groupUseSenderKeys) {
      if (dto.groupEpoch === undefined) {
        throw badRequest('group_epoch_required', 'Group epoch required for this conversation');
      }
      if (dto.groupEpoch !== conversation.currentEpoch) {
        throw conflict(
          'group_epoch_stale',
          'Group membership has changed; refetch the current epoch and resend',
        );
      }
    }

    const created = await this.createMessageWithRetry(auth, dto, attachmentId, members);

    const summary = this.toMessageSummary(created.message);
    await this.prisma.deviceConversationState.upsert({
      where: {
        deviceId_conversationId: {
          deviceId: auth.deviceId,
          conversationId: dto.conversationId,
        },
      },
      update: {
        lastSyncedConversationOrder: summary.conversationOrder,
      },
      create: {
        deviceId: auth.deviceId,
        conversationId: dto.conversationId,
        lastSyncedConversationOrder: summary.conversationOrder,
      },
    });
    await this.prisma.device.update({
      where: { id: auth.deviceId },
      data: { lastSyncAt: new Date() },
    });

    for (const member of members) {
      if (member.userId !== auth.userId) {
        this.realtimeGateway.emitToUser(member.userId, 'message.new', summary);
        await this.dispatchPushFallbackIfNeeded(member.userId, summary);
      }
      this.realtimeGateway.emitToUser(member.userId, 'conversation.sync', {
        conversationId: dto.conversationId,
        reason: 'message',
      });
    }

    return { message: summary, idempotent: created.idempotent };
  }

  private async createMessageWithRetry(
    auth: { userId: string; deviceId: string },
    dto: SendMessageDto,
    attachmentId: string | null,
    members: Array<{ userId: string }>,
  ): Promise<{ message: PersistedMessage; idempotent: boolean }> {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        const message = await this.prisma.$transaction(
          async (tx) => {
            const lastMessage = await tx.message.findFirst({
              where: { conversationId: dto.conversationId },
              orderBy: { conversationOrder: 'desc' },
              select: { conversationOrder: true },
            });

            return tx.message.create({
              data: {
                conversationId: dto.conversationId,
                senderDeviceId: auth.deviceId,
                clientMessageId: dto.clientMessageId,
                conversationOrder: (lastMessage?.conversationOrder ?? 0) + 1,
                ciphertext: dto.envelope.ciphertext,
                nonce: dto.envelope.nonce,
                messageType: dto.envelope.messageType,
                attachmentId,
                attachmentRef: dto.envelope.attachment
                  ? (dto.envelope.attachment as unknown as Prisma.InputJsonValue)
                  : undefined,
                expiresAt: dto.envelope.expiresAt ? new Date(dto.envelope.expiresAt) : null,
                viewOnce: dto.envelope.viewOnce === true,
                replyToMessageId: dto.replyToMessageId ?? null,
                receipts: {
                  create: members
                    .filter((member) => member.userId !== auth.userId)
                    .map((member) => ({
                      userId: member.userId,
                    })),
                },
              },
              include: {
                receipts: true,
              },
            });
          },
          {
            isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          },
        );
        return { message, idempotent: false };
      } catch (error) {
        const code = this.prismaErrorCode(error);
        if (code === 'P2002') {
          const existing = await this.findExistingMessage(auth.deviceId, dto.clientMessageId);
          if (existing) {
            return { message: existing as PersistedMessage, idempotent: true };
          }
        }
        if (code === 'P2034' && attempt < 2) {
          continue;
        }
        throw error;
      }
    }

    throw serviceUnavailable('internal_error', 'Message relay is temporarily unavailable');
  }

  private findExistingMessage(senderDeviceId: string, clientMessageId: string) {
    return this.prisma.message.findFirst({
      where: {
        senderDeviceId,
        clientMessageId,
      },
      include: {
        receipts: true,
      },
    });
  }

  private prismaErrorCode(error: unknown): string | undefined {
    if (typeof error === 'object' && error !== null && 'code' in error) {
      const code = (error as { code?: unknown }).code;
      return typeof code === 'string' ? code : undefined;
    }
    return undefined;
  }

  async markRead(
    auth: { userId: string; deviceId: string },
    messageId: string,
  ): Promise<MarkMessageReadResponse> {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      include: {
        conversation: {
          include: { members: true },
        },
        senderDevice: {
          select: { userId: true },
        },
      },
    });

    if (!message || !message.conversation.members.some((member) => member.userId === auth.userId)) {
      throw notFound('message_not_found', 'Message not found for actor');
    }

    const now = new Date();
    const existingReceipt = await this.prisma.messageReceipt.findUnique({
      where: {
        messageId_userId: {
          messageId,
          userId: auth.userId,
        },
      },
    });
    const hadDelivered = Boolean(existingReceipt?.deliveredAt);
    const hadRead = Boolean(existingReceipt?.readAt);

    // Wrap the receipt upsert and (for view-once) the row delete in a single
    // transaction. Without this, a crash between "read recorded" and "row
    // deleted" leaves view-once ciphertext on disk after the read event
    // already fired — exactly the leak window we promise not to have.
    const isViewOnceConsumption = message.viewOnce && message.senderDevice.userId !== auth.userId;
    const updatedReceipt = await this.prisma.$transaction(async (tx) => {
      const receipt = await tx.messageReceipt.upsert({
        where: {
          messageId_userId: {
            messageId,
            userId: auth.userId,
          },
        },
        update: {
          deliveredAt: now,
          readAt: now,
        },
        create: {
          messageId,
          userId: auth.userId,
          deliveredAt: now,
          readAt: now,
        },
      });
      if (isViewOnceConsumption) {
        try {
          await tx.message.delete({ where: { id: messageId } });
        } catch {
          // Concurrent consumption already deleted the row — the broadcast
          // below still fires so every member drops it from their cache.
        }
      }
      return receipt;
    });

    if (!hadDelivered) {
      this.realtimeGateway.emitConversationMembers(
        message.conversation.members,
        'message.delivered',
        {
          messageId,
          userId: auth.userId,
          deliveredAt: updatedReceipt.deliveredAt?.toISOString() ?? now.toISOString(),
        },
      );
    }
    if (!hadRead) {
      this.realtimeGateway.emitConversationMembers(message.conversation.members, 'message.read', {
        messageId,
        userId: auth.userId,
        readAt: updatedReceipt.readAt?.toISOString() ?? now.toISOString(),
      });
    }

    await this.prisma.deviceConversationState.upsert({
      where: {
        deviceId_conversationId: {
          deviceId: auth.deviceId,
          conversationId: message.conversationId,
        },
      },
      update: {
        lastSyncedConversationOrder: message.conversationOrder,
        lastReadConversationOrder: message.conversationOrder,
      },
      create: {
        deviceId: auth.deviceId,
        conversationId: message.conversationId,
        lastSyncedConversationOrder: message.conversationOrder,
        lastReadConversationOrder: message.conversationOrder,
      },
    });
    await this.prisma.device.update({
      where: { id: auth.deviceId },
      data: { lastSyncAt: now },
    });

    if (isViewOnceConsumption) {
      this.realtimeGateway.emitConversationMembers(
        message.conversation.members,
        'message.consumed',
        {
          messageId,
          conversationId: message.conversationId,
          consumedAt: now.toISOString(),
        },
      );
    }

    return {
      messageId,
      readAt: updatedReceipt.readAt?.toISOString() ?? now.toISOString(),
    };
  }

  async deleteLocal(
    auth: { userId: string },
    messageId: string,
  ): Promise<DeleteLocalMessageResponse> {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      include: {
        conversation: { include: { members: true } },
      },
    });

    if (!message || !message.conversation.members.some((member) => member.userId === auth.userId)) {
      throw notFound('message_not_found', 'Message not found for actor');
    }

    return {
      messageId,
      acknowledged: true,
    };
  }

  private toMessageSummary(message: {
    id: string;
    clientMessageId: string;
    conversationId: string;
    senderDeviceId: string;
    conversationOrder: number;
    ciphertext: string;
    nonce: string;
    messageType: 'text' | 'image' | 'file' | 'system' | 'voice' | 'sticker' | 'reaction' | 'call';
    attachmentRef?: unknown;
    expiresAt: Date | null;
    viewOnce?: boolean;
    serverReceivedAt: Date;
    deletedAt: Date | null;
    editedAt?: Date | null;
    editCount?: number;
    replyToMessageId?: string | null;
    receipts?: Array<{ deliveredAt: Date | null; readAt: Date | null }>;
    reactions?: Array<{ userId: string; emoji: string }>;
  }): ConversationMessageSummary {
    const receipt = message.receipts?.[0];
    return {
      id: message.id,
      clientMessageId: message.clientMessageId,
      conversationId: message.conversationId,
      senderDeviceId: message.senderDeviceId,
      conversationOrder: message.conversationOrder,
      ciphertext: message.ciphertext,
      nonce: message.nonce,
      messageType: message.messageType,
      attachment:
        (message.attachmentRef as EncryptedAttachmentReference | null | undefined) ?? null,
      expiresAt: message.expiresAt?.toISOString() ?? null,
      viewOnce: message.viewOnce === true,
      serverReceivedAt: message.serverReceivedAt.toISOString(),
      deletedAt: message.deletedAt?.toISOString() ?? null,
      editedAt: message.editedAt?.toISOString() ?? null,
      editCount: message.editCount ?? 0,
      replyToMessageId: message.replyToMessageId ?? null,
      deliveredAt: receipt?.deliveredAt?.toISOString() ?? null,
      readAt: receipt?.readAt?.toISOString() ?? null,
      reactions: (message.reactions ?? []).map((reaction) => ({
        userId: reaction.userId,
        emoji: reaction.emoji,
      })),
    };
  }

  // Edit replaces the ciphertext in place. Only the original sender's
  // active device may rewrite. We bump editCount so the UI can show
  // "(수정됨)" without us storing prior revisions — one of the
  // no-recovery non-negotiables is "server keeps no plaintext history".
  async edit(
    auth: { userId: string; deviceId: string },
    messageId: string,
    dto: { ciphertext: string; nonce: string; version: string },
  ): Promise<{ message: ConversationMessageSummary }> {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      include: { conversation: { include: { members: true } } },
    });
    if (!message) {
      throw notFound('message_not_found', 'Message not found');
    }
    if (message.senderDeviceId !== auth.deviceId) {
      throw forbidden('message_not_owned', 'Only the original sender may edit');
    }
    if (message.deletedAt) {
      throw forbidden('message_deleted', 'Cannot edit a deleted message');
    }
    if (message.viewOnce) {
      throw forbidden('view_once_immutable', 'View-once messages cannot be edited');
    }

    const updated = await this.prisma.message.update({
      where: { id: messageId },
      data: {
        ciphertext: dto.ciphertext,
        nonce: dto.nonce,
        editedAt: new Date(),
        editCount: { increment: 1 },
      },
      include: { receipts: true, reactions: true },
    });

    const summary = this.toMessageSummary(updated);
    this.realtimeGateway.emitConversationMembers(
      message.conversation.members,
      'message.edited',
      summary,
    );
    return { message: summary };
  }

  // Soft delete. The row stays so reply chains still resolve, but the
  // ciphertext is replaced with a small tombstone so the server cannot
  // re-deliver the original body even by accident.
  async delete(
    auth: { userId: string; deviceId: string },
    messageId: string,
  ): Promise<{ messageId: string; deletedAt: string }> {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      include: { conversation: { include: { members: true } } },
    });
    if (!message) {
      throw notFound('message_not_found', 'Message not found');
    }
    if (message.senderDeviceId !== auth.deviceId) {
      throw forbidden('message_not_owned', 'Only the original sender may delete');
    }
    if (message.deletedAt) {
      // Idempotent — same response on re-issue.
      return {
        messageId: message.id,
        deletedAt: message.deletedAt.toISOString(),
      };
    }

    const deletedAt = new Date();
    await this.prisma.message.update({
      where: { id: messageId },
      data: {
        deletedAt,
        ciphertext: 'deleted',
        nonce: 'deleted',
        attachmentRef: Prisma.JsonNull,
      },
    });

    this.realtimeGateway.emitConversationMembers(message.conversation.members, 'message.deleted', {
      messageId,
      deletedAt: deletedAt.toISOString(),
    });

    return { messageId, deletedAt: deletedAt.toISOString() };
  }

  async addReaction(auth: { userId: string }, messageId: string, emoji: string) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      include: {
        conversation: { include: { members: true } },
      },
    });

    if (!message || !message.conversation.members.some((m) => m.userId === auth.userId)) {
      throw notFound('message_not_found', 'Message not found for actor');
    }

    const reaction = await this.prisma.reaction.upsert({
      where: {
        messageId_userId: {
          messageId,
          userId: auth.userId,
        },
      },
      update: { emoji },
      create: {
        messageId,
        userId: auth.userId,
        emoji,
      },
    });

    this.realtimeGateway.emitConversationMembers(message.conversation.members, 'message.reaction', {
      messageId,
      userId: auth.userId,
      emoji,
      action: 'add' as const,
    });

    return { reactionId: reaction.id, messageId, emoji };
  }

  async removeReaction(auth: { userId: string }, messageId: string) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      include: {
        conversation: { include: { members: true } },
      },
    });

    if (!message || !message.conversation.members.some((m) => m.userId === auth.userId)) {
      throw notFound('message_not_found', 'Message not found for actor');
    }

    await this.prisma.reaction.deleteMany({
      where: {
        messageId,
        userId: auth.userId,
      },
    });

    this.realtimeGateway.emitConversationMembers(message.conversation.members, 'message.reaction', {
      messageId,
      userId: auth.userId,
      emoji: '',
      action: 'remove' as const,
    });

    return { messageId, acknowledged: true };
  }

  private async dispatchPushFallbackIfNeeded(
    recipientUserId: string,
    summary: ConversationMessageSummary,
  ): Promise<void> {
    if (
      await this.safetyService.isConversationMutedForUser(recipientUserId, summary.conversationId)
    ) {
      // Muted: the message still persists and flows over the realtime
      // socket if the app is open, but we skip the wake to keep the phone
      // quiet.
      return;
    }

    const connectedDeviceIds = new Set(
      this.realtimeGateway.connectedDeviceIdsForUser(recipientUserId),
    );
    const recipientDevices = await this.prisma.device.findMany({
      where: {
        userId: recipientUserId,
        isActive: true,
        revokedAt: null,
        pushToken: {
          not: null,
        },
      },
      select: {
        id: true,
        pushToken: true,
      },
    });

    for (const device of recipientDevices) {
      if (!device.pushToken || connectedDeviceIds.has(device.id)) {
        continue;
      }

      await this.pushService.sendMessageHint(device.pushToken, {
        kind: 'wake',
      });
    }
  }
}
