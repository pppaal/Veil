import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';
import { forbidden, notFound } from '../../common/errors/api-error';
import type { AuthContext } from '../../common/guards/authenticated-request';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { CreateGroupDto } from './dto/create-group.dto';
import { UpdateGroupDto } from './dto/update-group.dto';
import { ManageMemberDto } from './dto/manage-member.dto';

@Injectable()
export class GroupsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async createGroup(auth: AuthContext, dto: CreateGroupDto) {
    const memberUserIds: string[] = [];

    if (dto.memberHandles && dto.memberHandles.length > 0) {
      const users = await this.prisma.user.findMany({
        where: { handle: { in: dto.memberHandles.map((h) => h.toLowerCase()) } },
        select: { id: true },
      });
      for (const user of users) {
        if (user.id !== auth.userId) {
          memberUserIds.push(user.id);
        }
      }
    }

    const conversation = await this.prisma.$transaction(async (tx) => {
      const conv = await tx.conversation.create({
        data: {
          type: 'group',
          members: {
            create: [
              { userId: auth.userId, role: 'owner' },
              ...memberUserIds.map((userId) => ({ userId, role: 'member' as const })),
            ],
          },
          groupMeta: {
            create: {
              name: dto.name,
              description: dto.description ?? null,
              isPublic: dto.isPublic ?? false,
              createdByUserId: auth.userId,
            },
          },
        },
        include: {
          members: { include: { user: { select: { id: true, handle: true, displayName: true } } } },
          groupMeta: true,
        },
      });

      return conv;
    });

    const members = conversation.members.map((m) => ({ userId: m.userId }));
    this.realtimeGateway.emitConversationMembers(members, 'conversation.sync', {
      conversationId: conversation.id,
      reason: 'membership',
    });

    return {
      id: conversation.id,
      type: conversation.type,
      name: conversation.groupMeta!.name,
      description: conversation.groupMeta!.description,
      isPublic: conversation.groupMeta!.isPublic,
      createdAt: conversation.createdAt.toISOString(),
      members: conversation.members.map((m) => ({
        userId: m.userId,
        handle: m.user.handle,
        displayName: m.user.displayName,
        role: m.role,
      })),
    };
  }

  async getGroup(auth: AuthContext, conversationId: string) {
    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId: auth.userId,
        },
      },
    });

    if (!membership) {
      throw forbidden('conversation_membership_required', 'You are not a member of this group');
    }

    const conversation = await this.prisma.conversation.findUnique({
      where: { id: conversationId, type: 'group' },
      include: {
        members: { include: { user: { select: { id: true, handle: true, displayName: true } } } },
        groupMeta: true,
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
      throw notFound('handle_not_found', 'Group not found');
    }

    const lastMessage = conversation.messages[0] ?? null;

    return {
      id: conversation.id,
      type: conversation.type,
      name: conversation.groupMeta!.name,
      description: conversation.groupMeta!.description,
      isPublic: conversation.groupMeta!.isPublic,
      createdAt: conversation.createdAt.toISOString(),
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

  async updateGroup(auth: AuthContext, conversationId: string, dto: UpdateGroupDto) {
    await this.requireAdminOrOwner(auth.userId, conversationId);

    const conversation = await this.prisma.conversation.findUnique({
      where: { id: conversationId, type: 'group' },
      include: { groupMeta: true },
    });

    if (!conversation || !conversation.groupMeta) {
      throw notFound('handle_not_found', 'Group not found');
    }

    const updated = await this.prisma.groupMeta.update({
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
      reason: 'membership',
    });

    return {
      conversationId,
      name: updated.name,
      description: updated.description,
      isPublic: updated.isPublic,
    };
  }

  async addMember(auth: AuthContext, conversationId: string, dto: ManageMemberDto) {
    await this.requireAdminOrOwner(auth.userId, conversationId);

    const conversation = await this.prisma.conversation.findUnique({
      where: { id: conversationId, type: 'group' },
    });

    if (!conversation) {
      throw notFound('handle_not_found', 'Group not found');
    }

    const user = await this.prisma.user.findUnique({
      where: { handle: dto.handle.toLowerCase() },
      select: { id: true, handle: true, displayName: true },
    });

    if (!user) {
      throw notFound('handle_not_found', 'User not found');
    }

    const existingMember = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId: user.id,
        },
      },
    });

    if (existingMember) {
      return { conversationId, userId: user.id, handle: user.handle, role: existingMember.role };
    }

    const role = dto.role ?? 'member';

    await this.prisma.conversationMember.create({
      data: {
        conversationId,
        userId: user.id,
        role,
      },
    });

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId },
      select: { userId: true },
    });

    this.realtimeGateway.emitConversationMembers(members, 'conversation.sync', {
      conversationId,
      reason: 'membership',
    });

    return { conversationId, userId: user.id, handle: user.handle, role };
  }

  async removeMember(auth: AuthContext, conversationId: string, handle: string) {
    await this.requireAdminOrOwner(auth.userId, conversationId);

    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true },
    });

    if (!user) {
      throw notFound('handle_not_found', 'User not found');
    }

    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId: user.id,
        },
      },
    });

    if (!membership) {
      throw notFound('handle_not_found', 'User is not a member of this group');
    }

    if (membership.role === 'owner') {
      throw forbidden('conversation_membership_required', 'Cannot remove the group owner');
    }

    await this.prisma.conversationMember.delete({
      where: {
        conversationId_userId: {
          conversationId,
          userId: user.id,
        },
      },
    });

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId },
      select: { userId: true },
    });

    this.realtimeGateway.emitConversationMembers(
      [...members, { userId: user.id }],
      'conversation.sync',
      { conversationId, reason: 'membership' },
    );

    return { conversationId, removedUserId: user.id };
  }

  async leaveGroup(auth: AuthContext, conversationId: string) {
    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId: auth.userId,
        },
      },
    });

    if (!membership) {
      throw notFound('handle_not_found', 'You are not a member of this group');
    }

    if (membership.role === 'owner') {
      throw forbidden('conversation_membership_required', 'Owner cannot leave. Transfer ownership first.');
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

    return { conversationId, left: true };
  }

  private async requireAdminOrOwner(userId: string, conversationId: string): Promise<void> {
    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: {
          conversationId,
          userId,
        },
      },
    });

    if (!membership) {
      throw forbidden('conversation_membership_required', 'You are not a member of this group');
    }

    if (membership.role !== 'owner' && membership.role !== 'admin') {
      throw forbidden('conversation_membership_required', 'Admin or owner role required');
    }
  }
}
