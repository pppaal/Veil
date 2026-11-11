import { Injectable } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import type {
  ConversationSummary,
  CreateDirectConversationResponse,
  ListMessagesResponse,
  SetDisappearingTimerResponse,
} from '@veil/contracts';
import { isUUID } from 'class-validator';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import {
  EMITS_RECEIPTS,
  historyVisibleSince,
  isActionAllowed,
} from '../../common/conversation-access/conversation-policy';
import { PaginationQueryDto } from '../../common/dto/pagination-query.dto';
import { apiError } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';
import {
  MESSAGE_SUMMARY_INCLUDE,
  notExpiredWhere,
  toMessageSummary,
  type MessageSummaryRow,
} from '../messages/message.mapper';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { SafetyService } from '../safety/safety.service';
import { CreateDirectConversationDto } from './dto/create-direct-conversation.dto';

// Everything toConversationSummary reads. The latest message is fetched for
// every conversation type; toConversationSummary hides it from a group
// member who joined after it was sent.
const conversationSummaryInclude = (now: Date) =>
  ({
    members: { include: { user: { select: { handle: true, displayName: true } } } },
    messages: {
      where: notExpiredWhere(now),
      orderBy: { conversationOrder: 'desc' },
      take: 1,
      include: MESSAGE_SUMMARY_INCLUDE,
    },
  }) satisfies Prisma.ConversationInclude;

type SummarizableConversation = Prisma.ConversationGetPayload<{
  include: ReturnType<typeof conversationSummaryInclude>;
}>;

@Injectable()
export class ConversationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly safetyService: SafetyService,
    private readonly access: ConversationAccessService,
  ) {}

  async createDirect(
    currentUserId: string,
    dto: CreateDirectConversationDto,
  ): Promise<CreateDirectConversationResponse> {
    const peer = await this.prisma.user.findUnique({
      where: { handle: dto.peerHandle.toLowerCase() },
      select: { id: true },
    });

    // Either-direction block answers exactly like an unknown handle, so the
    // blocked user can't tell "doesn't exist" from "you've been blocked".
    if (!peer || (await this.safetyService.isBlockedEitherWay(currentUserId, peer.id))) {
      throw apiError('handle_not_found', 'Peer handle not found');
    }
    if (peer.id === currentUserId) {
      throw apiError('cannot_add_self', 'Direct conversation requires a second user');
    }

    const now = new Date();
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
        include: conversationSummaryInclude(now),
      });

      const found = existing.find((conversation) => {
        const memberIds = conversation.members.map((member) => member.userId);
        return (
          memberIds.length === 2 && memberIds.includes(peer.id) && memberIds.includes(currentUserId)
        );
      });

      if (found) {
        return { conversation: this.toConversationSummary(found, currentUserId) };
      }
    }

    // Deterministic dedupe key — sorted member uuids joined by '|'. Two
    // concurrent createDirect calls between the same pair both try to
    // write this same string; the unique index in 0009 lets the database
    // pick a winner and we just look up the existing row on P2002.
    const directKey = [currentUserId, peer.id].sort().join('|');

    let created: SummarizableConversation;
    try {
      created = await this.prisma.conversation.create({
        data: {
          type: 'direct',
          directKey,
          members: {
            create: [{ userId: currentUserId }, { userId: peer.id }],
          },
        },
        include: conversationSummaryInclude(now),
      });
    } catch (error) {
      if ((error as { code?: unknown } | null)?.code === 'P2002') {
        const existing = await this.prisma.conversation.findUnique({
          where: { directKey },
          include: conversationSummaryInclude(now),
        });
        if (existing) {
          return { conversation: this.toConversationSummary(existing, currentUserId) };
        }
      }
      throw error;
    }

    // Wake up the peer's conversation list so they see the new DM without
    // waiting for a polling tick.
    this.realtimeGateway.emitConversationMembers(created.members, 'conversation.sync', {
      conversationId: created.id,
      reason: 'membership',
    });

    return { conversation: this.toConversationSummary(created, currentUserId) };
  }

  async setDisappearingTimer(
    currentUserId: string,
    conversationId: string,
    seconds: number | null,
  ): Promise<SetDisappearingTimerResponse> {
    await this.access.requireAccess(currentUserId, conversationId, 'setTimer');

    const updated = await this.prisma.conversation.update({
      where: { id: conversationId },
      data: { disappearingTimerSeconds: seconds },
      include: conversationSummaryInclude(new Date()),
    });

    this.realtimeGateway.emitConversationMembers(updated.members, 'conversation.timer.changed', {
      conversationId,
      disappearingTimerSeconds: seconds,
    });

    return { conversation: this.toConversationSummary(updated, currentUserId) };
  }

  async listForUser(userId: string): Promise<ConversationSummary[]> {
    const memberships = await this.prisma.conversationMember.findMany({
      where: { userId },
      select: { conversation: { include: conversationSummaryInclude(new Date()) } },
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
    const { conversation, member } = await this.access.requireAccess(
      auth.userId,
      conversationId,
      'readHistory',
    );
    const requestedLimit = Number(query.limit ?? 50);
    const limit = Number.isFinite(requestedLimit) ? Math.min(100, Math.max(1, requestedLimit)) : 50;

    const cursorMessage =
      query.cursor && isUUID(query.cursor)
        ? await this.prisma.message.findUnique({
            where: { id: query.cursor },
            select: { conversationId: true, conversationOrder: true },
          })
        : null;
    if (query.cursor && cursorMessage?.conversationId !== conversationId) {
      throw apiError('message_not_found', 'Pagination cursor not found');
    }

    const visibleSince = historyVisibleSince(conversation.type, member.joinedAt);
    const messages = await this.prisma.message.findMany({
      where: {
        conversationId,
        ...notExpiredWhere(new Date()),
        ...(visibleSince ? { serverReceivedAt: { gte: visibleSince } } : {}),
        ...(cursorMessage ? { conversationOrder: { lt: cursorMessage.conversationOrder } } : {}),
      },
      orderBy: { conversationOrder: 'desc' },
      take: limit,
      include: MESSAGE_SUMMARY_INCLUDE,
    });

    if (EMITS_RECEIPTS[conversation.type]) {
      await this.markDeliveredForViewer(messages, auth.userId);
    }

    const highestConversationOrder =
      messages.length > 0
        ? Math.max(...messages.map((message) => message.conversationOrder))
        : (cursorMessage?.conversationOrder ?? null);

    await this.updateDeviceConversationState({
      deviceId: auth.deviceId,
      conversationId,
      lastSyncedConversationOrder: highestConversationOrder,
    });

    return {
      items: messages
        .map((message) => toMessageSummary(message, { viewerUserId: auth.userId }))
        .reverse(),
      nextCursor: messages.length === limit ? (messages.at(-1)?.id ?? null) : null,
    };
  }

  // Marks the fetched page delivered for the viewer. Only messages the viewer
  // may list reach here, so pre-join group history is never acknowledged.
  // Each delivered receipt goes to the sender and the viewer's own devices.
  private async markDeliveredForViewer(
    messages: MessageSummaryRow[],
    viewerUserId: string,
  ): Promise<void> {
    const deliveredAt = new Date();

    for (const message of messages) {
      const senderUserId = message.senderDevice.userId;
      const existingReceipt = message.receipts.find((receipt) => receipt.userId === viewerUserId);
      if (senderUserId === viewerUserId || existingReceipt?.deliveredAt) {
        continue;
      }

      await this.prisma.messageReceipt.upsert({
        where: { messageId_userId: { messageId: message.id, userId: viewerUserId } },
        update: { deliveredAt },
        create: { messageId: message.id, userId: viewerUserId, deliveredAt },
      });

      if (existingReceipt) {
        existingReceipt.deliveredAt = deliveredAt;
      } else {
        message.receipts.push({ userId: viewerUserId, deliveredAt, readAt: null });
      }

      this.realtimeGateway.emitConversationMembers(
        [{ userId: senderUserId }, { userId: viewerUserId }],
        'message.delivered',
        { messageId: message.id, userId: viewerUserId, deliveredAt: deliveredAt.toISOString() },
      );
    }
  }

  private toConversationSummary(
    conversation: SummarizableConversation,
    viewerUserId: string,
  ): ConversationSummary {
    const viewer = conversation.members.find((member) => member.userId === viewerUserId);
    // Without readMembers (channel subscribers) the viewer only learns who
    // runs the conversation, never who else is in it.
    const canSeeMembers = viewer
      ? isActionAllowed(conversation.type, viewer.role, 'readMembers')
      : false;
    const members = canSeeMembers
      ? conversation.members
      : conversation.members.filter(
          (member) =>
            member.userId === viewerUserId || member.role === 'owner' || member.role === 'admin',
        );

    const latest = conversation.messages[0];
    const visibleSince = viewer ? historyVisibleSince(conversation.type, viewer.joinedAt) : null;
    const lastMessage =
      latest && (!visibleSince || latest.serverReceivedAt >= visibleSince)
        ? toMessageSummary(latest, { viewerUserId })
        : null;

    return {
      id: conversation.id,
      type: conversation.type,
      createdAt: conversation.createdAt.toISOString(),
      disappearingTimerSeconds: conversation.disappearingTimerSeconds,
      // Sender Keys metadata is only meaningful for groups; direct chats
      // and channels never carry it so legacy clients see no new fields.
      ...(conversation.type === 'group'
        ? {
            useSenderKeys: conversation.groupUseSenderKeys,
            currentEpoch: conversation.currentEpoch,
          }
        : {}),
      members: members.map((member) => ({
        userId: member.userId,
        handle: member.user.handle,
        displayName: member.user.displayName,
      })),
      lastMessage,
    };
  }

  private async updateDeviceConversationState(args: {
    deviceId: string;
    conversationId: string;
    lastSyncedConversationOrder: number | null;
  }): Promise<void> {
    const current = await this.prisma.deviceConversationState.findUnique({
      where: {
        deviceId_conversationId: {
          deviceId: args.deviceId,
          conversationId: args.conversationId,
        },
      },
    });

    const lastSyncedConversationOrder =
      args.lastSyncedConversationOrder ?? current?.lastSyncedConversationOrder ?? null;
    const lastReadConversationOrder = current?.lastReadConversationOrder ?? null;

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
