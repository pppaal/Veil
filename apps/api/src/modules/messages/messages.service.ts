import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type {
  DeleteLocalMessageResponse,
  MarkMessageReadResponse,
  SendMessageResponse,
} from '@veil/contracts';
import type { EncryptedAttachmentReference } from '@veil/shared';

import { PrismaService } from '../../common/prisma.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { SendMessageDto } from './dto/send-message.dto';

@Injectable()
export class MessagesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async send(
    auth: { userId: string; deviceId: string },
    dto: SendMessageDto,
  ): Promise<SendMessageResponse> {
    if (dto.envelope.senderDeviceId !== auth.deviceId || dto.conversationId !== dto.envelope.conversationId) {
      throw new ForbiddenException('Envelope sender context mismatch');
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
      throw new ForbiddenException('Conversation membership required');
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
        throw new NotFoundException('Attachment not found for sender device');
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
      throw new ForbiddenException('Envelope recipient does not match direct conversation peer');
    }

    const created = await this.prisma.message.create({
      data: {
        conversationId: dto.conversationId,
        senderDeviceId: auth.deviceId,
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
              deliveredAt: new Date(),
            })),
        },
      },
    });

    const summary = {
      id: created.id,
      conversationId: created.conversationId,
      senderDeviceId: created.senderDeviceId,
      ciphertext: created.ciphertext,
      nonce: created.nonce,
      messageType: created.messageType,
      attachment: (created.attachmentRef as EncryptedAttachmentReference | null | undefined) ?? null,
      expiresAt: created.expiresAt?.toISOString() ?? null,
      serverReceivedAt: created.serverReceivedAt.toISOString(),
      deletedAt: created.deletedAt?.toISOString() ?? null,
    };

    for (const member of members) {
      if (member.userId !== auth.userId) {
        this.realtimeGateway.emitToUser(member.userId, 'message.new', summary);
      }
      this.realtimeGateway.emitToUser(member.userId, 'conversation.sync', {
        conversationId: dto.conversationId,
        reason: 'message',
      });
    }

    return { message: summary };
  }

  async markRead(
    auth: { userId: string },
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
      throw new NotFoundException('Message not found for actor');
    }

    const now = new Date();
    await this.prisma.messageReceipt.upsert({
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

    this.realtimeGateway.emitConversationMembers(message.conversation.members, 'message.read', {
      messageId,
      userId: auth.userId,
      readAt: now.toISOString(),
    });

    return {
      messageId,
      readAt: now.toISOString(),
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
      throw new NotFoundException('Message not found for actor');
    }

    return {
      messageId,
      acknowledged: true,
    };
  }
}
