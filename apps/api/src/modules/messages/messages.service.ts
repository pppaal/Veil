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
  forbidden,
  notFound,
  serviceUnavailable,
} from '../../common/errors/api-error';
import { PushService } from '../push/push.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
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
  ) {}

  async send(
    auth: { userId: string; deviceId: string },
    dto: SendMessageDto,
  ): Promise<SendMessageResponse> {
    if (dto.envelope.senderDeviceId !== auth.deviceId || dto.conversationId !== dto.envelope.conversationId) {
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

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId: dto.conversationId },
      select: { userId: true },
    });

    const recipientUserIds = members
      .map((member) => member.userId)
      .filter((userId) => userId !== auth.userId);

    if (
      recipientUserIds.length !== 1 ||
      dto.envelope.recipientUserId !== recipientUserIds[0]
    ) {
      throw forbidden('direct_peer_mismatch', 'Envelope recipient does not match direct conversation peer');
    }

    const existing = await this.findExistingMessage(auth.deviceId, dto.clientMessageId);
    if (existing) {
      return {
        message: this.toMessageSummary(existing),
        idempotent: true,
      };
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

    throw serviceUnavailable(
      'internal_error',
      'Message relay is temporarily unavailable',
    );
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

    const updatedReceipt = await this.prisma.messageReceipt.upsert({
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

    if (!hadDelivered) {
      this.realtimeGateway.emitConversationMembers(message.conversation.members, 'message.delivered', {
        messageId,
        userId: auth.userId,
        deliveredAt: updatedReceipt.deliveredAt?.toISOString() ?? now.toISOString(),
      });
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
    serverReceivedAt: Date;
    deletedAt: Date | null;
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
      attachment: (message.attachmentRef as EncryptedAttachmentReference | null | undefined) ?? null,
      expiresAt: message.expiresAt?.toISOString() ?? null,
      serverReceivedAt: message.serverReceivedAt.toISOString(),
      deletedAt: message.deletedAt?.toISOString() ?? null,
      deliveredAt: receipt?.deliveredAt?.toISOString() ?? null,
      readAt: receipt?.readAt?.toISOString() ?? null,
      reactions: (message.reactions ?? []).map((reaction) => ({
        userId: reaction.userId,
        emoji: reaction.emoji,
      })),
    };
  }

  async addReaction(
    auth: { userId: string },
    messageId: string,
    emoji: string,
  ) {
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

  async removeReaction(
    auth: { userId: string },
    messageId: string,
  ) {
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
    const connectedDeviceIds = new Set(this.realtimeGateway.connectedDeviceIdsForUser(recipientUserId));
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
        kind: 'message.new',
        messageId: summary.id,
        conversationId: summary.conversationId,
        senderDeviceId: summary.senderDeviceId,
        serverReceivedAt: summary.serverReceivedAt,
      });
    }
  }
}
