import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';
import { forbidden, notFound } from '../../common/errors/api-error';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { InitiateCallDto } from './dto/initiate-call.dto';

@Injectable()
export class CallsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async initiateCall(
    auth: { userId: string; deviceId: string },
    dto: InitiateCallDto,
  ) {
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

    const callRecord = await this.prisma.callRecord.create({
      data: {
        conversationId: dto.conversationId,
        initiatorDeviceId: auth.deviceId,
        callType: dto.callType,
        status: 'ringing',
        startedAt: new Date(),
      },
    });

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId: dto.conversationId },
      select: { userId: true },
    });

    const initiator = await this.prisma.user.findUnique({
      where: { id: auth.userId },
      select: { handle: true },
    });

    this.realtimeGateway.emitConversationMembers(
      members.filter((m) => m.userId !== auth.userId),
      'call.incoming',
      {
        callId: callRecord.id,
        conversationId: dto.conversationId,
        callType: dto.callType,
        initiatorHandle: initiator?.handle ?? '',
      },
    );

    return { callId: callRecord.id, status: callRecord.status };
  }

  async endCall(
    auth: { userId: string },
    callId: string,
  ) {
    const callRecord = await this.prisma.callRecord.findUnique({
      where: { id: callId },
      include: {
        conversation: { include: { members: true } },
      },
    });

    if (!callRecord) {
      throw notFound('message_not_found', 'Call record not found');
    }

    if (!callRecord.conversation.members.some((m) => m.userId === auth.userId)) {
      throw forbidden('conversation_membership_required', 'Conversation membership required');
    }

    const now = new Date();
    const duration = Math.floor((now.getTime() - callRecord.startedAt.getTime()) / 1000);

    const updated = await this.prisma.callRecord.update({
      where: { id: callId },
      data: {
        status: 'ended',
        endedAt: now,
        duration,
      },
    });

    this.realtimeGateway.emitConversationMembers(
      callRecord.conversation.members,
      'call.ended',
      {
        callId: updated.id,
        conversationId: updated.conversationId,
        duration,
      },
    );

    return { callId: updated.id, status: updated.status, duration };
  }

  async listCalls(auth: { userId: string }) {
    const userConversations = await this.prisma.conversationMember.findMany({
      where: { userId: auth.userId },
      select: { conversationId: true },
    });

    const conversationIds = userConversations.map((c) => c.conversationId);

    const calls = await this.prisma.callRecord.findMany({
      where: { conversationId: { in: conversationIds } },
      orderBy: { startedAt: 'desc' },
      take: 50,
      include: {
        conversation: {
          include: {
            members: {
              include: {
                user: { select: { id: true, handle: true, displayName: true } },
              },
            },
            groupMeta: { select: { name: true } },
          },
        },
        initiatorDevice: { select: { userId: true } },
      },
    });

    return calls.map((call) => {
      const otherMember = call.conversation.members.find(
        (m) => m.userId !== auth.userId,
      );
      const counterparty = call.conversation.groupMeta?.name
        ?? otherMember?.user.displayName
        ?? otherMember?.user.handle
        ?? 'Unknown';
      const counterpartyHandle = otherMember?.user.handle ?? null;

      return {
        id: call.id,
        conversationId: call.conversationId,
        callType: call.callType,
        status: call.status,
        startedAt: call.startedAt.toISOString(),
        endedAt: call.endedAt?.toISOString() ?? null,
        duration: call.duration,
        initiatedByMe: call.initiatorDevice?.userId === auth.userId,
        counterparty,
        counterpartyHandle,
      };
    });
  }
}
