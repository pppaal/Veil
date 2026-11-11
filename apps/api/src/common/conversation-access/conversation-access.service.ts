import { Injectable } from '@nestjs/common';
import type { ConversationType, MemberRole } from '@veil/shared';
import { isUUID } from 'class-validator';

import { SafetyService } from '../../modules/safety/safety.service';
import { apiError } from '../errors/api-error';
import { PrismaService } from '../prisma.service';
import {
  PEER_REACHING_ACTIONS,
  isActionAllowed,
  type ConversationAction,
} from './conversation-policy';

export interface ConversationAccess {
  conversation: {
    id: string;
    type: ConversationType;
    disappearingTimerSeconds: number | null;
    groupUseSenderKeys: boolean;
    currentEpoch: number;
  };
  member: {
    userId: string;
    role: MemberRole;
    joinedAt: Date;
  };
}

/**
 * The one place that decides whether a user may act on a conversation.
 * Every conversation-scoped endpoint and realtime handler goes through
 * requireAccess (or requireMember + authorize when it must branch on the
 * conversation before the policy check), so membership, role and block
 * rules cannot drift between call sites.
 */
@Injectable()
export class ConversationAccessService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly safety: SafetyService,
  ) {}

  async requireAccess(
    userId: string,
    conversationId: string,
    action: ConversationAction,
  ): Promise<ConversationAccess> {
    const access = await this.requireMember(userId, conversationId);
    await this.authorize(access, action);
    return access;
  }

  /**
   * Loads the caller's membership together with the conversation in one
   * query. A missing conversation and a non-member get the same 403 so the
   * response never confirms that a conversation id exists.
   */
  async requireMember(userId: string, conversationId: string): Promise<ConversationAccess> {
    if (!isUUID(conversationId)) {
      throw apiError('validation_failed', 'conversationId must be a UUID');
    }

    const membership = await this.prisma.conversationMember.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
      select: {
        role: true,
        joinedAt: true,
        conversation: {
          select: {
            id: true,
            type: true,
            disappearingTimerSeconds: true,
            groupUseSenderKeys: true,
            currentEpoch: true,
          },
        },
      },
    });

    if (!membership) {
      throw apiError('conversation_membership_required');
    }

    return {
      conversation: membership.conversation,
      member: { userId, role: membership.role, joinedAt: membership.joinedAt },
    };
  }

  async authorize(access: ConversationAccess, action: ConversationAction): Promise<void> {
    const { conversation, member } = access;
    if (!isActionAllowed(conversation.type, member.role, action)) {
      throw apiError('conversation_role_required');
    }
    if (
      conversation.type === 'direct' &&
      PEER_REACHING_ACTIONS.has(action) &&
      (await this.isDirectPeerBlocked(conversation.id, member.userId))
    ) {
      throw apiError('peer_unreachable', 'Peer is unreachable');
    }
  }

  private async isDirectPeerBlocked(conversationId: string, userId: string): Promise<boolean> {
    const peer = await this.prisma.conversationMember.findFirst({
      where: { conversationId, userId: { not: userId } },
      select: { userId: true },
    });
    if (!peer) {
      return false;
    }
    return this.safety.isBlockedEitherWay(userId, peer.userId);
  }
}
