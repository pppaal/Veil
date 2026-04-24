import {
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import type {
  ConversationMessageSummary,
  ConversationSummary,
  CreateDirectConversationResponse,
  ListMessagesResponse,
  SetDisappearingTimerResponse,
} from '@veil/contracts';
import type { EncryptedAttachmentReference } from '@veil/shared';

import { PrismaService } from '../../common/prisma.service';
import { PaginationQueryDto } from '../../common/dto/pagination-query.dto';
import {
  ATTACHMENT_STORAGE_GATEWAY,
  type AttachmentStorageGateway,
} from '../attachments/attachment-storage.gateway';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { SafetyService } from '../safety/safety.service';
import { CreateDirectConversationDto } from './dto/create-direct-conversation.dto';

type HydratedReceipt = {
  userId: string;
  deliveredAt: Date | null;
  readAt: Date | null;
};

type HydratedReaction = {
  userId: string;
  emoji: string;
};

type HydratedMessage = {
  id: string;
  clientMessageId: string;
  conversationId: string;
  senderDeviceId: string;
  conversationOrder: number;
  ciphertext: string;
  nonce: string;
  messageType: 'text' | 'image' | 'file' | 'system' | 'voice' | 'sticker' | 'reaction' | 'call';
  serverReceivedAt: Date;
  deletedAt: Date | null;
  expiresAt: Date | null;
  attachmentRef?: unknown;
  senderDevice: { userId: string };
  receipts: HydratedReceipt[];
  reactions: HydratedReaction[];
};

@Injectable()
export class ConversationsService implements OnModuleInit, OnModuleDestroy {
  // Sweep interval for hard-deleting globally expired messages. Each
  // conversation read already prunes lazily via notExpiredFilter(), but idle
  // conversations never get a read and would otherwise retain rows past
  // their expiresAt. 10 minutes keeps the retention window tight without
  // saturating the primary with deletes on a messenger-scale workload.
  private static readonly GLOBAL_PRUNE_INTERVAL_MS = 10 * 60 * 1000;

  private globalPruneTimer: NodeJS.Timeout | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
    @Inject(ATTACHMENT_STORAGE_GATEWAY)
    private readonly attachmentStorageGateway: AttachmentStorageGateway,
    private readonly safetyService: SafetyService,
  ) {}

  onModuleInit(): void {
    // Run one sweep shortly after boot so a freshly-started process catches
    // up on whatever expired while it was down, then keep the periodic
    // cadence. unref() so the timer never keeps the event loop alive during
    // graceful shutdown.
    setTimeout(() => void this.pruneAllExpiredMessages(), 5_000).unref();
    this.globalPruneTimer = setInterval(
      () => void this.pruneAllExpiredMessages(),
      ConversationsService.GLOBAL_PRUNE_INTERVAL_MS,
    );
    this.globalPruneTimer.unref();
  }

  onModuleDestroy(): void {
    if (this.globalPruneTimer) {
      clearInterval(this.globalPruneTimer);
      this.globalPruneTimer = null;
    }
  }

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

    // Either-direction block. Returning NotFound keeps the block state
    // opaque to the blocked user — they can't distinguish between
    // "handle doesn't exist" and "you've been blocked".
    if (await this.safetyService.isBlockedEitherWay(currentUserId, peer.id)) {
      throw new NotFoundException('Peer handle not found');
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

  async setDisappearingTimer(
    currentUserId: string,
    conversationId: string,
    seconds: number | null,
  ): Promise<SetDisappearingTimerResponse> {
    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId: currentUserId,
        },
      },
      select: { id: true },
    });

    if (!membership) {
      throw new ForbiddenException('Conversation membership required');
    }

    const updated = await this.prisma.conversation.update({
      where: { id: conversationId },
      data: { disappearingTimerSeconds: seconds },
      include: {
        members: {
          include: { user: true },
        },
        messages: this.latestMessageInclude(),
      },
    });

    this.realtimeGateway.emitConversationMembers(
      updated.members.map((member) => ({ userId: member.userId })),
      'conversation.timer.changed',
      {
        conversationId,
        disappearingTimerSeconds: seconds,
      },
    );

    return { conversation: this.toConversationSummary(updated, currentUserId) };
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
    auth: { userId: string; deviceId: string },
    conversationId: string,
    query: PaginationQueryDto,
  ): Promise<ListMessagesResponse> {
    const requestedLimit = Number(query.limit ?? 50);
    const limit = Number.isFinite(requestedLimit)
      ? Math.min(100, Math.max(1, requestedLimit))
      : 50;
    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId: auth.userId,
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

    const cursorMessage = query.cursor
      ? await this.prisma.message.findUnique({
          where: { id: query.cursor },
          select: {
            id: true,
            conversationId: true,
            conversationOrder: true,
          },
        })
      : null;

    if (query.cursor && (!cursorMessage || cursorMessage.conversationId !== conversationId)) {
      throw new NotFoundException('Pagination cursor not found');
    }

    void this.pruneExpiredMessages(conversationId);

    const messages = (await this.prisma.message.findMany({
      where: {
        conversationId,
        ...this.notExpiredFilter(),
        ...(cursorMessage
          ? {
              conversationOrder: {
                lt: cursorMessage.conversationOrder,
              },
            }
          : {}),
      },
      orderBy: { conversationOrder: 'desc' },
      take: limit,
      include: {
        senderDevice: {
          select: { userId: true },
        },
        receipts: true,
        reactions: {
          select: { userId: true, emoji: true },
        },
      },
    })) as HydratedMessage[];

    await this.markDeliveredForViewer(messages, members, auth.userId);

    const highestConversationOrder =
      messages.length > 0
        ? Math.max(...messages.map((message) => message.conversationOrder))
        : cursorMessage?.conversationOrder ?? null;

    await this.updateDeviceConversationState({
      deviceId: auth.deviceId,
      conversationId,
      lastSyncedConversationOrder: highestConversationOrder,
    });

    return {
      items: messages.map((message) => this.toMessageSummary(message, auth.userId)).reverse(),
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
      where: this.notExpiredFilter(),
      orderBy: { conversationOrder: 'desc' as const },
      take: 1,
      include: {
        senderDevice: {
          select: { userId: true },
        },
        receipts: true,
        reactions: {
          select: { userId: true, emoji: true },
        },
      },
    };
  }

  private notExpiredFilter() {
    return {
      OR: [
        { expiresAt: null },
        { expiresAt: { gt: new Date() } },
      ],
    };
  }

  private async pruneAllExpiredMessages(): Promise<void> {
    try {
      const now = new Date();
      const expired = await this.prisma.message.findMany({
        where: { expiresAt: { lte: now } },
        select: { id: true, attachmentId: true },
      });

      if (expired.length === 0) {
        return;
      }

      const candidateAttachmentIds = Array.from(
        new Set(
          expired
            .map((message) => message.attachmentId)
            .filter((value): value is string => Boolean(value)),
        ),
      );

      await this.prisma.message.deleteMany({
        where: { id: { in: expired.map((message) => message.id) } },
      });

      for (const attachmentId of candidateAttachmentIds) {
        await this.tryDeleteOrphanedAttachment(attachmentId);
      }
    } catch {
      // Best-effort sweep: next interval will retry.
    }
  }

  private async pruneExpiredMessages(conversationId: string): Promise<void> {
    try {
      const now = new Date();
      const expired = await this.prisma.message.findMany({
        where: {
          conversationId,
          expiresAt: { lte: now },
        },
        select: { id: true, attachmentId: true },
      });

      if (expired.length === 0) {
        return;
      }

      const candidateAttachmentIds = Array.from(
        new Set(
          expired
            .map((message) => message.attachmentId)
            .filter((value): value is string => Boolean(value)),
        ),
      );

      await this.prisma.message.deleteMany({
        where: { id: { in: expired.map((message) => message.id) } },
      });

      for (const attachmentId of candidateAttachmentIds) {
        await this.tryDeleteOrphanedAttachment(attachmentId);
      }
    } catch {
      // Best-effort pruning: ignore failures so reads stay responsive.
    }
  }

  private async tryDeleteOrphanedAttachment(attachmentId: string): Promise<void> {
    try {
      const stillReferenced = await this.prisma.message.findFirst({
        where: { attachmentId },
        select: { id: true },
      });
      if (stillReferenced) {
        return;
      }

      const attachment = await this.prisma.attachment.findUnique({
        where: { id: attachmentId },
        select: { id: true, storageKey: true },
      });
      if (!attachment) {
        return;
      }

      try {
        await this.attachmentStorageGateway.deleteObject(attachment.storageKey);
      } catch {
        // Storage delete is best-effort; DB cleanup still proceeds so the row
        // does not live forever as a dangling pointer to a missing blob.
      }

      await this.prisma.attachment.delete({ where: { id: attachment.id } });
    } catch {
      // Best-effort: never let attachment cleanup failures surface to readers.
    }
  }

  private toConversationSummary(conversation: {
    id: string;
    type: 'direct' | 'group' | 'channel';
    createdAt: Date;
    disappearingTimerSeconds: number | null;
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
      disappearingTimerSeconds: conversation.disappearingTimerSeconds,
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
      reactions: message.reactions.map((reaction) => ({
        userId: reaction.userId,
        emoji: reaction.emoji,
      })),
    };
  }

  private resolveReceiptForViewer(message: HydratedMessage, viewerUserId: string): HydratedReceipt | null {
    if (message.senderDevice.userId === viewerUserId) {
      return message.receipts.find((receipt) => receipt.userId !== viewerUserId) ?? null;
    }

    return message.receipts.find((receipt) => receipt.userId === viewerUserId) ?? null;
  }

  private async updateDeviceConversationState(args: {
    deviceId: string;
    conversationId: string;
    lastSyncedConversationOrder?: number | null;
    lastReadConversationOrder?: number | null;
  }): Promise<void> {
    const current = await this.prisma.deviceConversationState.findUnique({
      where: {
        deviceId_conversationId: {
          deviceId: args.deviceId,
          conversationId: args.conversationId,
        },
      },
    });

    const lastSyncedConversationOrder = args.lastSyncedConversationOrder ?? current?.lastSyncedConversationOrder ?? null;
    const lastReadConversationOrder = args.lastReadConversationOrder ?? current?.lastReadConversationOrder ?? null;

    await this.prisma.deviceConversationState.upsert({
      where: {
        deviceId_conversationId: {
          deviceId: args.deviceId,
          conversationId: args.conversationId,
        },
      },
      update: {
        lastSyncedConversationOrder,
        lastReadConversationOrder,
      },
      create: {
        deviceId: args.deviceId,
        conversationId: args.conversationId,
        lastSyncedConversationOrder,
        lastReadConversationOrder,
      },
    });

    await this.prisma.device.update({
      where: { id: args.deviceId },
      data: { lastSyncAt: new Date() },
    });
  }
}
