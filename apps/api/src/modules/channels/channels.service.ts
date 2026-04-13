import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';
import { forbidden, notFound } from '../../common/errors/api-error';
import type { AuthContext } from '../../common/guards/authenticated-request';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { CreateChannelDto } from './dto/create-channel.dto';
import { UpdateChannelDto } from './dto/update-channel.dto';

@Injectable()
export class ChannelsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async createChannel(auth: AuthContext, dto: CreateChannelDto) {
    const conversation = await this.prisma.$transaction(async (tx) => {
      const conv = await tx.conversation.create({
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
          members: { include: { user: { select: { id: true, handle: true, displayName: true } } } },
          channelMeta: true,
        },
      });

      return conv;
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
        displayName: m.user.displayName,
        role: m.role,
      })),
    };
  }

  async getChannel(auth: AuthContext, conversationId: string) {
    const conversation = await this.prisma.conversation.findUnique({
      where: { id: conversationId, type: 'channel' },
      include: {
        members: { include: { user: { select: { id: true, handle: true, displayName: true } } } },
        channelMeta: true,
        messages: {
          orderBy: { conversationOrder: 'desc' },
          take: 1,
          include: {
            senderDevice: { select: { userId: true } },
          },
        },
      },
    });

    if (!conversation) {
      throw notFound('handle_not_found', 'Channel not found');
    }

    const membership = conversation.members.find((m) => m.userId === auth.userId);

    if (!membership && !conversation.channelMeta!.isPublic) {
      throw forbidden('conversation_membership_required', 'You are not subscribed to this channel');
    }

    const lastMessage = conversation.messages[0] ?? null;

    return {
      id: conversation.id,
      type: conversation.type,
      name: conversation.channelMeta!.name,
      description: conversation.channelMeta!.description,
      isPublic: conversation.channelMeta!.isPublic,
      createdAt: conversation.createdAt.toISOString(),
      subscriberCount: conversation.members.length,
      isSubscribed: !!membership,
      members: conversation.members.map((m) => ({
        userId: m.userId,
        handle: m.user.handle,
        displayName: m.user.displayName,
        role: m.role,
      })),
      lastMessage: lastMessage
        ? {
            id: lastMessage.id,
            conversationId: lastMessage.conversationId,
            senderDeviceId: lastMessage.senderDeviceId,
            ciphertext: lastMessage.ciphertext,
            nonce: lastMessage.nonce,
            messageType: lastMessage.messageType,
            serverReceivedAt: lastMessage.serverReceivedAt.toISOString(),
          }
        : null,
    };
  }

  async updateChannel(auth: AuthContext, conversationId: string, dto: UpdateChannelDto) {
    await this.requireOwner(auth.userId, conversationId);

    const conversation = await this.prisma.conversation.findUnique({
      where: { id: conversationId, type: 'channel' },
      include: { channelMeta: true },
    });

    if (!conversation || !conversation.channelMeta) {
      throw notFound('handle_not_found', 'Channel not found');
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
    const conversation = await this.prisma.conversation.findUnique({
      where: { id: conversationId, type: 'channel' },
      include: { channelMeta: true },
    });

    if (!conversation) {
      throw notFound('handle_not_found', 'Channel not found');
    }

    if (!conversation.channelMeta!.isPublic) {
      throw forbidden('conversation_membership_required', 'Cannot subscribe to a private channel');
    }

    const existing = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId: auth.userId,
        },
      },
    });

    if (existing) {
      return { conversationId, subscribed: true };
    }

    await this.prisma.conversationMember.create({
      data: {
        conversationId,
        userId: auth.userId,
        role: 'subscriber',
      },
    });

    this.realtimeGateway.emitToUser(auth.userId, 'conversation.sync', {
      conversationId,
      reason: 'membership',
    });

    return { conversationId, subscribed: true };
  }

  async unsubscribe(auth: AuthContext, conversationId: string) {
    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId: auth.userId,
        },
      },
    });

    if (!membership) {
      throw notFound('handle_not_found', 'You are not subscribed to this channel');
    }

    if (membership.role === 'owner') {
      throw forbidden('conversation_membership_required', 'Owner cannot unsubscribe. Transfer ownership first.');
    }

    await this.prisma.conversationMember.delete({
      where: {
        conversationId_userId: {
          conversationId,
          userId: auth.userId,
        },
      },
    });

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId },
      select: { userId: true },
    });

    this.realtimeGateway.emitConversationMembers(
      [...members, { userId: auth.userId }],
      'conversation.sync',
      { conversationId, reason: 'membership' },
    );

    return { conversationId, subscribed: false };
  }

  private async requireOwner(userId: string, conversationId: string): Promise<void> {
    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId,
        },
      },
    });

    if (!membership) {
      throw forbidden('conversation_membership_required', 'You are not a member of this channel');
    }

    if (membership.role !== 'owner') {
      throw forbidden('conversation_membership_required', 'Owner role required');
    }
  }
}
