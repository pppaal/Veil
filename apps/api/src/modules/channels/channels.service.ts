import { Injectable } from '@nestjs/common';
import type { ChannelMemberSummary, ChannelSummaryResponse } from '@veil/contracts';
import { isUUID } from 'class-validator';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { isActionAllowed } from '../../common/conversation-access/conversation-policy';
import { apiError } from '../../common/errors/api-error';
import type { AuthContext } from '../../common/guards/authenticated-request';
import { PrismaService } from '../../common/prisma.service';
import {
  MESSAGE_SUMMARY_INCLUDE,
  notExpiredWhere,
  toMessageSummary,
} from '../messages/message.mapper';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { CreateChannelDto } from './dto/create-channel.dto';
import { UpdateChannelDto } from './dto/update-channel.dto';

const CHANNEL_STAFF_ROLES = ['owner', 'admin'] as const;

@Injectable()
export class ChannelsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly access: ConversationAccessService,
  ) {}

  async createChannel(auth: AuthContext, dto: CreateChannelDto) {
    const conversation = await this.prisma.conversation.create({
      data: {
        type: 'channel',
        members: {
          create: [{ userId: auth.userId, role: 'owner' }],
        },
        channelMeta: {
          create: {
            name: dto.name,
            description: dto.description ?? null,
            isPublic: dto.isPublic ?? true,
            createdByUserId: auth.userId,
          },
        },
      },
      include: {
        members: { include: { user: { select: { id: true, handle: true } } } },
        channelMeta: true,
      },
    });

    this.realtimeGateway.emitToUser(auth.userId, 'conversation.sync', {
      conversationId: conversation.id,
      reason: 'membership',
    });

    return {
      id: conversation.id,
      type: conversation.type,
      name: conversation.channelMeta!.name,
      description: conversation.channelMeta!.description,
      isPublic: conversation.channelMeta!.isPublic,
      createdAt: conversation.createdAt.toISOString(),
      members: conversation.members.map((m) => ({
        userId: m.userId,
        handle: m.user.handle,
        role: m.role,
      })),
    };
  }

  /**
   * Public channels are viewable by anyone, but subscribers stay invisible
   * to each other: everyone sees the subscriber count and who runs the
   * channel, only the owner and admins get the member list, and only members
   * get the latest post. A private channel answers non-members exactly like
   * a missing one.
   */
  async getChannel(auth: AuthContext, conversationId: string): Promise<ChannelSummaryResponse> {
    const channel = isUUID(conversationId)
      ? await this.prisma.conversation.findUnique({
          where: { id: conversationId, type: 'channel' },
          select: {
            channelMeta: { select: { name: true, description: true, isPublic: true } },
            _count: { select: { members: true } },
            members: {
              where: {
                OR: [{ role: { in: [...CHANNEL_STAFF_ROLES] } }, { userId: auth.userId }],
              },
              select: { userId: true, role: true, user: { select: { handle: true } } },
            },
          },
        })
      : null;
    const viewer = channel?.members.find((member) => member.userId === auth.userId);
    if (!channel?.channelMeta || (!viewer && !channel.channelMeta.isPublic)) {
      throw apiError('channel_not_found', 'Channel not found');
    }

    const summary: ChannelSummaryResponse = {
      id: conversationId,
      name: channel.channelMeta.name,
      description: channel.channelMeta.description,
      isPublic: channel.channelMeta.isPublic,
      subscriberCount: channel._count.members,
      admins: channel.members
        .filter((member) => member.role === 'owner' || member.role === 'admin')
        .map((member) => ({ userId: member.userId, handle: member.user.handle })),
      viewerRole: viewer?.role ?? null,
    };
    if (!viewer) {
      return summary;
    }

    if (isActionAllowed('channel', viewer.role, 'readMembers')) {
      summary.members = await this.listMembers(conversationId);
    }
    const latest = await this.prisma.message.findFirst({
      where: { conversationId, ...notExpiredWhere(new Date()) },
      orderBy: { conversationOrder: 'desc' },
      include: MESSAGE_SUMMARY_INCLUDE,
    });
    summary.lastMessage = latest ? toMessageSummary(latest, { viewerUserId: auth.userId }) : null;
    return summary;
  }

  async updateChannel(auth: AuthContext, conversationId: string, dto: UpdateChannelDto) {
    const access = await this.access.requireAccess(auth.userId, conversationId, 'manageMembers');
    if (access.conversation.type !== 'channel') {
      throw apiError('channel_not_found', 'Channel not found');
    }

    const updated = await this.prisma.channelMeta.update({
      where: { conversationId },
      data: {
        ...(dto.name !== undefined && { name: dto.name }),
        ...(dto.description !== undefined && { description: dto.description }),
        ...(dto.isPublic !== undefined && { isPublic: dto.isPublic }),
      },
    });

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId },
      select: { userId: true },
    });

    this.realtimeGateway.emitConversationMembers(members, 'conversation.sync', {
      conversationId,
      reason: 'refresh',
    });

    return {
      conversationId,
      name: updated.name,
      description: updated.description,
      isPublic: updated.isPublic,
    };
  }

  async subscribe(auth: AuthContext, conversationId: string) {
    const channel = isUUID(conversationId)
      ? await this.prisma.conversation.findUnique({
          where: { id: conversationId, type: 'channel' },
          select: { channelMeta: { select: { isPublic: true } } },
        })
      : null;
    // Private channels are invite-only and indistinguishable from missing.
    if (!channel?.channelMeta?.isPublic) {
      throw apiError('channel_not_found', 'Channel not found');
    }

    const existing = await this.prisma.conversationMember.findUnique({
      where: { conversationId_userId: { conversationId, userId: auth.userId } },
      select: { id: true },
    });
    if (!existing) {
      await this.prisma.conversationMember.create({
        data: { conversationId, userId: auth.userId, role: 'subscriber' },
      });
      this.realtimeGateway.emitToUser(auth.userId, 'conversation.sync', {
        conversationId,
        reason: 'membership',
      });
    }

    return { conversationId, subscribed: true };
  }

  async unsubscribe(auth: AuthContext, conversationId: string) {
    const access = await this.access.requireMember(auth.userId, conversationId);
    if (access.conversation.type !== 'channel') {
      throw apiError('channel_not_found', 'Channel not found');
    }
    if (access.member.role === 'owner') {
      throw apiError('owner_immutable', 'Owner cannot unsubscribe. Transfer ownership first.');
    }

    await this.prisma.conversationMember.delete({
      where: { conversationId_userId: { conversationId, userId: auth.userId } },
    });

    // Only the leaver and the people who can see the member list hear about
    // it; other subscribers must not observe membership churn.
    const staff = await this.prisma.conversationMember.findMany({
      where: { conversationId, role: { in: [...CHANNEL_STAFF_ROLES] } },
      select: { userId: true },
    });
    this.realtimeGateway.emitConversationMembers(
      [...staff, { userId: auth.userId }],
      'conversation.sync',
      { conversationId, reason: 'membership' },
    );

    return { conversationId, subscribed: false };
  }

  private async listMembers(conversationId: string): Promise<ChannelMemberSummary[]> {
    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId },
      select: { userId: true, role: true, user: { select: { handle: true } } },
    });
    return members.map((member) => ({
      userId: member.userId,
      handle: member.user.handle,
      role: member.role,
    }));
  }
}
