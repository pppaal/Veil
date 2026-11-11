import { Injectable } from '@nestjs/common';
import type { CallStatus } from '@prisma/client';
import { isUUID } from 'class-validator';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { apiError } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { InitiateCallDto } from './dto/initiate-call.dto';

type CallTransition = 'accept' | 'decline' | 'end';

// The only legal call state changes. declined, missed and ended are
// terminal: re-ending a finished call must not recompute its duration.
const CALL_TRANSITIONS: Readonly<
  Record<CallTransition, { from: readonly CallStatus[]; to: CallStatus }>
> = {
  accept: { from: ['ringing'], to: 'active' },
  decline: { from: ['ringing'], to: 'declined' },
  end: { from: ['ringing', 'active'], to: 'ended' },
};

@Injectable()
export class CallsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly access: ConversationAccessService,
  ) {}

  async initiateCall(auth: { userId: string; deviceId: string }, dto: InitiateCallDto) {
    const access = await this.access.requireMember(auth.userId, dto.conversationId);
    // Calls are 1:1 only; group and channel calls would ring every member.
    if (access.conversation.type !== 'direct') {
      throw apiError('call_not_allowed', 'Calls are only available in direct conversations');
    }
    await this.access.authorize(access, 'call');

    const callRecord = await this.prisma.callRecord.create({
      data: {
        conversationId: dto.conversationId,
        initiatorDeviceId: auth.deviceId,
        callType: dto.callType,
        status: 'ringing',
        startedAt: new Date(),
      },
    });

    const initiator = await this.prisma.user.findUnique({
      where: { id: auth.userId },
      select: { handle: true },
    });

    this.realtimeGateway.emitConversationMembers(
      await this.members(dto.conversationId, { excludeUserId: auth.userId }),
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

  async acceptCall(auth: { userId: string }, callId: string) {
    const call = await this.findCall(callId);
    // Accepting reaches the peer, so it is subject to the full call policy
    // (including blocks); declining and hanging up only need membership.
    await this.access.requireAccess(auth.userId, call.conversationId, 'call');
    if (call.initiatorDevice.userId === auth.userId) {
      throw apiError('call_initiator_forbidden', 'Call initiator cannot accept the call');
    }

    const status = await this.transition(call, 'accept');
    this.realtimeGateway.emitConversationMembers(
      await this.members(call.conversationId),
      'call.accepted',
      { callId: call.id, conversationId: call.conversationId },
    );
    return { callId: call.id, status };
  }

  async declineCall(auth: { userId: string }, callId: string) {
    const call = await this.findCall(callId);
    await this.access.requireMember(auth.userId, call.conversationId);

    const status = await this.transition(call, 'decline', { endedAt: new Date() });
    this.realtimeGateway.emitConversationMembers(
      await this.members(call.conversationId),
      'call.declined',
      { callId: call.id, conversationId: call.conversationId },
    );
    return { callId: call.id, status };
  }

  async endCall(auth: { userId: string }, callId: string) {
    const call = await this.findCall(callId);
    await this.access.requireMember(auth.userId, call.conversationId);

    const endedAt = new Date();
    const duration = Math.floor((endedAt.getTime() - call.startedAt.getTime()) / 1000);
    const status = await this.transition(call, 'end', { endedAt, duration });
    this.realtimeGateway.emitConversationMembers(
      await this.members(call.conversationId),
      'call.ended',
      { callId: call.id, conversationId: call.conversationId, duration },
    );
    return { callId: call.id, status, duration };
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
          select: {
            type: true,
            groupMeta: { select: { name: true } },
            channelMeta: { select: { name: true } },
            // Only a direct conversation has a person on the other end; at
            // most one other member is loaded so a large group or channel
            // costs nothing and never names an arbitrary member.
            members: {
              where: { userId: { not: auth.userId } },
              take: 1,
              select: { user: { select: { handle: true, displayName: true } } },
            },
          },
        },
        initiatorDevice: { select: { userId: true } },
      },
    });

    return calls.map((call) => {
      const { type, groupMeta, channelMeta, members } = call.conversation;
      const peer = type === 'direct' ? members[0]?.user : undefined;
      const counterparty =
        groupMeta?.name ?? channelMeta?.name ?? peer?.displayName ?? peer?.handle ?? 'Unknown';
      const counterpartyHandle = peer?.handle ?? null;

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

  private async findCall(callId: string) {
    const call = isUUID(callId)
      ? await this.prisma.callRecord.findUnique({
          where: { id: callId },
          select: {
            id: true,
            conversationId: true,
            status: true,
            startedAt: true,
            initiatorDevice: { select: { userId: true } },
          },
        })
      : null;
    if (!call) {
      throw apiError('call_not_found', 'Call record not found');
    }
    return call;
  }

  // Compare-and-set on the current status, so two racing requests (both
  // parties hanging up at once) cannot both apply a transition.
  private async transition(
    call: { id: string; status: CallStatus },
    transition: CallTransition,
    data: { endedAt?: Date; duration?: number } = {},
  ): Promise<CallStatus> {
    const rule = CALL_TRANSITIONS[transition];
    const { count } = rule.from.includes(call.status)
      ? await this.prisma.callRecord.updateMany({
          where: { id: call.id, status: { in: [...rule.from] } },
          data: { status: rule.to, ...data },
        })
      : { count: 0 };
    if (count === 0) {
      throw apiError('call_invalid_state', `Cannot ${transition} a call that is ${call.status}`);
    }
    return rule.to;
  }

  private members(
    conversationId: string,
    { excludeUserId }: { excludeUserId?: string } = {},
  ): Promise<Array<{ userId: string }>> {
    return this.prisma.conversationMember.findMany({
      where: { conversationId, ...(excludeUserId ? { userId: { not: excludeUserId } } : {}) },
      select: { userId: true },
    });
  }
}
