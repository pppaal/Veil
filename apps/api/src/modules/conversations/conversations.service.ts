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
import { CreateDirectConversationDto } from './dto/create-direct-conversation.dto';

@Injectable()
export class ConversationsService {
  constructor(private readonly prisma: PrismaService) {}

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
          messages: {
            orderBy: { serverReceivedAt: 'desc' },
            take: 1,
          },
        },
      });

      const found = existing.find((conversation) => {
        const memberIds = conversation.members.map((member) => member.userId);
        return memberIds.length === 2 && memberIds.includes(peer.id) && memberIds.includes(currentUserId);
      });

      if (found) {
        return { conversation: this.toConversationSummary(found) };
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
        messages: {
          orderBy: { serverReceivedAt: 'desc' },
          take: 1,
        },
      },
    });

    return {
      conversation: this.toConversationSummary(created),
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
            messages: {
              orderBy: { serverReceivedAt: 'desc' },
              take: 1,
            },
          },
        },
      },
      orderBy: {
        conversation: { createdAt: 'desc' },
      },
    });

    return memberships.map((membership) => this.toConversationSummary(membership.conversation));
  }

  async listMessagesForUser(
    userId: string,
    conversationId: string,
    query: PaginationQueryDto,
  ): Promise<ListMessagesResponse> {
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

    const messages = await this.prisma.message.findMany({
      where: { conversationId },
      orderBy: { serverReceivedAt: 'desc' },
      take: query.limit,
      ...(query.cursor
        ? {
            cursor: { id: query.cursor },
            skip: 1,
          }
        : {}),
    });

    const items = messages.map((message) => this.toMessageSummary(message)).reverse();
    return {
      items,
      nextCursor: messages.length === query.limit ? messages.at(-1)?.id ?? null : null,
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
      messages: Array<{
        id: string;
        conversationId: string;
        senderDeviceId: string;
        ciphertext: string;
        nonce: string;
        messageType: 'text' | 'image' | 'file' | 'system';
        serverReceivedAt: Date;
        deletedAt: Date | null;
        expiresAt: Date | null;
        attachmentId: string | null;
        attachmentRef: unknown;
      }>;
  }): ConversationSummary {
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
        ? {
            id: conversation.messages[0].id,
            conversationId: conversation.messages[0].conversationId,
            senderDeviceId: conversation.messages[0].senderDeviceId,
            ciphertext: conversation.messages[0].ciphertext,
            nonce: conversation.messages[0].nonce,
            messageType: conversation.messages[0].messageType,
            attachment:
              (conversation.messages[0].attachmentRef as
                | EncryptedAttachmentReference
                | null
                | undefined) ?? null,
            expiresAt: conversation.messages[0].expiresAt?.toISOString() ?? null,
            serverReceivedAt: conversation.messages[0].serverReceivedAt.toISOString(),
            deletedAt: conversation.messages[0].deletedAt?.toISOString() ?? null,
          }
        : null,
    };
  }

  private toMessageSummary(message: {
    id: string;
    conversationId: string;
    senderDeviceId: string;
    ciphertext: string;
    nonce: string;
    messageType: 'text' | 'image' | 'file' | 'system';
    serverReceivedAt: Date;
    deletedAt: Date | null;
    expiresAt: Date | null;
    attachmentRef?: unknown;
  }): ConversationMessageSummary {
    return {
      id: message.id,
      conversationId: message.conversationId,
      senderDeviceId: message.senderDeviceId,
      ciphertext: message.ciphertext,
      nonce: message.nonce,
      messageType: message.messageType,
      attachment: (message.attachmentRef as EncryptedAttachmentReference | null | undefined) ?? null,
      expiresAt: message.expiresAt?.toISOString() ?? null,
      serverReceivedAt: message.serverReceivedAt.toISOString(),
      deletedAt: message.deletedAt?.toISOString() ?? null,
    };
  }
}
