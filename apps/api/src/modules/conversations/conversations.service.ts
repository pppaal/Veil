import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type {
  ConversationMessageSummary,
  ConversationSummary,
  CreateDirectConversationResponse,
  ListMessagesResponse,
} from '@veil/contracts';
import type { EncryptedAttachmentReference } from '@veil/shared';

import { PrismaService } from '../../common/prisma.service';
import { PaginationQueryDto } from '../../common/dto/pagination-query.dto';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { CreateDirectConversationDto } from './dto/create-direct-conversation.dto';

type HydratedReceipt = {
  userId: string;
  deliveredAt: Date | null;
  readAt: Date | null;
};

type HydratedMessage = {
  id: string;
  clientMessageId: string;
  conversationId: string;
  senderDeviceId: string;
  conversationOrder: number;
  ciphertext: string;
  nonce: string;
  messageType: 'text' | 'image' | 'file' | 'system';
  serverReceivedAt: Date;
  deletedAt: Date | null;
  expiresAt: Date | null;
  attachmentRef?: unknown;
  senderDevice: { userId: string };
  receipts: HydratedReceipt[];
};

@Injectable()
export class ConversationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async createDirect(
    currentUserId: string,
    dto: CreateDirectConversationDto,
  ): Promise<CreateDirectConversationResponse> {
    const peer = await this.prisma.user.findUnique({
      where: { handle: dto.peerHandle.toLowerCase() },
      select: { id: true, handle: true, displayName: true },
    });

    if (!peer) {
      throw new NotFoundException('Peer handle not found');
    }

    if (peer.id === currentUserId) {
      throw new ForbiddenException('Direct conversation requires a second user');
    }

    const currentMemberships = await this.prisma.conversationMember.findMany({
      where: { userId: currentUserId },
      select: { conversationId: true },
    });

    if (currentMemberships.length > 0) {
      const existing = await this.prisma.conversation.findMany({
        where: {
          id: { in: currentMemberships.map((membership) => membership.conversationId) },
          type: 'direct',
        },
        include: {
          members: {
            include: {
              user: true,
            },
          },
          messages: this.latestMessageInclude(),
        },
      });

      const found = existing.find((conversation) => {
        const memberIds = conversation.members.map((member) => member.userId);
        return memberIds.length === 2 && memberIds.includes(peer.id) && memberIds.includes(currentUserId);
      });

      if (found) {
        return { conversation: this.toConversationSummary(found, currentUserId) };
      }
    }

    const created = await this.prisma.conversation.create({
      data: {
        type: 'direct',
        members: {
          create: [{ userId: currentUserId }, { userId: peer.id }],
        },
      },
      include: {
        members: {
          include: { user: true },
        },
        messages: this.latestMessageInclude(),
      },
    });

    return {
      conversation: this.toConversationSummary(created, currentUserId),
    };
  }

  async listForUser(userId: string): Promise<ConversationSummary[]> {
    const memberships = await this.prisma.conversationMember.findMany({
      where: { userId },
      include: {
        conversation: {
          include: {
            members: {
              include: { user: true },
            },
            messages: this.latestMessageInclude(),
          },
        },
      },
    });

    return memberships
      .map((membership) => this.toConversationSummary(membership.conversation, userId))
      .sort((a, b) => {
        const aTime = a.lastMessage?.serverReceivedAt ?? a.createdAt;
        const bTime = b.lastMessage?.serverReceivedAt ?? b.createdAt;
        return bTime.localeCompare(aTime);
      });
  }

  async listMessagesForUser(
    userId: string,
    conversationId: string,
    query: PaginationQueryDto,
  ): Promise<ListMessagesResponse> {
    const limit = Number(query.limit ?? 50);
    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId,
        },
      },
      select: { id: true },
    });

    if (!membership) {
      throw new ForbiddenException('Conversation membership required');
    }

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId },
      select: { userId: true },
    });

    const messages = (await this.prisma.message.findMany({
      where: { conversationId },
      orderBy: { conversationOrder: 'desc' },
      take: limit,
      ...(query.cursor
        ? {
            cursor: { id: query.cursor },
            skip: 1,
          }
        : {}),
      include: {
        senderDevice: {
          select: { userId: true },
        },
        receipts: true,
      },
    })) as HydratedMessage[];

    await this.markDeliveredForViewer(messages, members, userId);

    return {
      items: messages.map((message) => this.toMessageSummary(message, userId)).reverse(),
      nextCursor: messages.length === limit ? messages.at(-1)?.id ?? null : null,
    };
  }

  private async markDeliveredForViewer(
    messages: HydratedMessage[],
    members: Array<{ userId: string }>,
    userId: string,
  ): Promise<void> {
    const deliveredAt = new Date();

    for (const message of messages) {
      const existingReceipt = message.receipts.find((receipt) => receipt.userId === userId) ?? null;
      if (message.senderDevice.userId === userId || existingReceipt?.deliveredAt) {
        continue;
      }

      await this.prisma.messageReceipt.upsert({
        where: {
          messageId_userId: {
            messageId: message.id,
            userId,
          },
        },
        update: {
          deliveredAt,
        },
        create: {
          messageId: message.id,
          userId,
          deliveredAt,
        },
      });

      if (existingReceipt) {
        existingReceipt.deliveredAt = deliveredAt;
      } else {
        message.receipts.push({
          userId,
          deliveredAt,
          readAt: null,
        });
      }

      this.realtimeGateway.emitConversationMembers(members, 'message.delivered', {
        messageId: message.id,
        userId,
        deliveredAt: deliveredAt.toISOString(),
      });
    }
  }

  private latestMessageInclude() {
    return {
      orderBy: { conversationOrder: 'desc' as const },
      take: 1,
      include: {
        senderDevice: {
          select: { userId: true },
        },
        receipts: true,
      },
    };
  }

  private toConversationSummary(conversation: {
    id: string;
    type: 'direct';
    createdAt: Date;
    members: Array<{
      userId: string;
      user: { handle: string; displayName: string | null };
    }>;
    messages: HydratedMessage[];
  }, viewerUserId: string): ConversationSummary {
    return {
      id: conversation.id,
      type: conversation.type,
      createdAt: conversation.createdAt.toISOString(),
      members: conversation.members.map((member) => ({
        userId: member.userId,
        handle: member.user.handle,
        displayName: member.user.displayName,
      })),
      lastMessage: conversation.messages[0]
        ? this.toMessageSummary(conversation.messages[0], viewerUserId)
        : null,
    };
  }

  private toMessageSummary(message: HydratedMessage, viewerUserId: string): ConversationMessageSummary {
    const receipt = this.resolveReceiptForViewer(message, viewerUserId);
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
    };
  }

  private resolveReceiptForViewer(message: HydratedMessage, viewerUserId: string): HydratedReceipt | null {
    if (message.senderDevice.userId === viewerUserId) {
      return message.receipts.find((receipt) => receipt.userId !== viewerUserId) ?? null;
    }

    return message.receipts.find((receipt) => receipt.userId === viewerUserId) ?? null;
  }
}
