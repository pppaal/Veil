import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type {
  GroupKeyDistributeResponse,
  GroupKeyDistributionItem,
  GroupKeyDistributionsResponse,
} from '@veil/contracts';

import { PrismaService } from '../../common/prisma.service';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { badRequest, forbidden, notFound } from '../../common/errors/api-error';
import type { AuthContext } from '../../common/guards/authenticated-request';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { CreateGroupDto } from './dto/create-group.dto';
import { UpdateGroupDto } from './dto/update-group.dto';
import { ManageMemberDto } from './dto/manage-member.dto';
import { KeyDistributeDto } from './dto/key-distribute.dto';

// How long distributed chain-key blobs are buffered for offline recipients.
// Past the TTL a recipient recovers by asking senders to redistribute (the
// design's self-heal path), so the server never holds key material for long.
const KEY_DISTRIBUTION_TTL_SECONDS = 30 * 60;

const keyDistributionKey = (
  conversationId: string,
  epoch: number,
  recipientUserId: string,
  senderUserId: string,
): string => `group:keydist:${conversationId}:${epoch}:${recipientUserId}:${senderUserId}`;

interface StoredKeyDistribution {
  fromUserId: string;
  fromDeviceId: string;
  encryptedChainKey: string;
  nonce: string;
  version: string;
  createdAt: string;
}

@Injectable()
export class GroupsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly ephemeralStore: EphemeralStoreService,
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
          groupUseSenderKeys: dto.useSenderKeys ?? false,
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

      // Seed the epoch-0 membership window for every founding member so the
      // group has a complete member-epoch ledger from creation. No epoch bump
      // or realtime event here — the group is brand new and nobody is
      // listening yet.
      await tx.groupMemberEpoch.createMany({
        data: conv.members.map((m) => ({
          conversationId: conv.id,
          userId: m.userId,
          joinedEpoch: 0,
          leftEpoch: null,
        })),
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
      useSenderKeys: conversation.groupUseSenderKeys,
      epoch: conversation.currentEpoch,
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
      useSenderKeys: conversation.groupUseSenderKeys,
      epoch: conversation.currentEpoch,
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

    // The Sender-Keys flag lives on the conversation, not the group meta.
    // Only touch it when the caller asked to, so a metadata-only edit doesn't
    // silently reset it.
    let useSenderKeys = conversation.groupUseSenderKeys;
    if (dto.useSenderKeys !== undefined) {
      const updatedConversation = await this.prisma.conversation.update({
        where: { id: conversationId },
        data: { groupUseSenderKeys: dto.useSenderKeys },
        select: { groupUseSenderKeys: true },
      });
      useSenderKeys = updatedConversation.groupUseSenderKeys;
    }

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
      useSenderKeys,
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

    const epoch = await this.prisma.$transaction(async (tx) => {
      await tx.conversationMember.create({
        data: {
          conversationId,
          userId: user.id,
          role,
        },
      });
      return this.bumpEpochForChange(tx, conversationId, {
        userId: user.id,
        reason: 'join',
      });
    });

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId },
      select: { userId: true },
    });

    this.realtimeGateway.emitConversationMembers(members, 'conversation.sync', {
      conversationId,
      reason: 'membership',
    });
    this.realtimeGateway.emitConversationMembers(members, 'group.epoch.bumped', {
      conversationId,
      epoch,
      reason: 'join',
      userId: user.id,
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

    const epoch = await this.prisma.$transaction(async (tx) => {
      await tx.conversationMember.delete({
        where: {
          conversationId_userId: {
            conversationId,
            userId: user.id,
          },
        },
      });
      return this.bumpEpochForChange(tx, conversationId, {
        userId: user.id,
        reason: 'leave',
      });
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
    // Only remaining members get the new epoch — the removed user must not
    // learn (or act on) the post-departure generation.
    this.realtimeGateway.emitConversationMembers(members, 'group.epoch.bumped', {
      conversationId,
      epoch,
      reason: 'leave',
      userId: user.id,
    });

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
      throw forbidden(
        'conversation_membership_required',
        'Owner cannot leave. Transfer ownership first.',
      );
    }

    const epoch = await this.prisma.$transaction(async (tx) => {
      await tx.conversationMember.delete({
        where: {
          conversationId_userId: {
            conversationId,
            userId: auth.userId,
          },
        },
      });
      return this.bumpEpochForChange(tx, conversationId, {
        userId: auth.userId,
        reason: 'leave',
      });
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
    this.realtimeGateway.emitConversationMembers(members, 'group.epoch.bumped', {
      conversationId,
      epoch,
      reason: 'leave',
      userId: auth.userId,
    });

    return { conversationId, left: true };
  }

  /**
   * Accept a batch of sender-key chain-key distributions from one member and
   * relay them to the addressed members. Every blob is opaque: it was
   * encrypted under the sender↔recipient 1:1 ratchet before it reached us,
   * so the server buffers and forwards ciphertext it cannot read.
   *
   * Guards: caller must be a current member, the conversation must be a
   * group with Sender Keys enabled, the stamped epoch must be current, and
   * every recipient must be a current member other than the sender. Blobs are
   * buffered for KEY_DISTRIBUTION_TTL_SECONDS (offline pickup via
   * getKeyDistributions) and fanned out live as group.key.distribution.
   * A re-send for the same (epoch, recipient) overwrites — redistribution is
   * idempotent within an epoch.
   */
  async distributeKeys(
    auth: AuthContext,
    conversationId: string,
    dto: KeyDistributeDto,
  ): Promise<GroupKeyDistributeResponse> {
    const conversation = await this.requireSenderKeysGroup(conversationId, auth.userId);

    if (dto.epoch !== conversation.currentEpoch) {
      throw badRequest(
        'group_epoch_stale',
        `Epoch ${dto.epoch} is not the conversation's current epoch`,
      );
    }

    const memberIds = new Set(conversation.members.map((member) => member.userId));
    for (const distribution of dto.distributions) {
      if (distribution.recipientUserId === auth.userId) {
        throw badRequest('key_distribution_invalid', 'Cannot distribute a chain key to yourself');
      }
      if (!memberIds.has(distribution.recipientUserId)) {
        throw badRequest(
          'key_distribution_invalid',
          'Every recipient must be a current group member',
        );
      }
    }

    const createdAt = new Date().toISOString();
    for (const distribution of dto.distributions) {
      const stored: StoredKeyDistribution = {
        fromUserId: auth.userId,
        fromDeviceId: auth.deviceId,
        encryptedChainKey: distribution.encryptedChainKey,
        nonce: distribution.nonce,
        version: distribution.version,
        createdAt,
      };
      await this.ephemeralStore.setJson(
        keyDistributionKey(conversationId, dto.epoch, distribution.recipientUserId, auth.userId),
        stored,
        KEY_DISTRIBUTION_TTL_SECONDS,
      );
      this.realtimeGateway.emitToUser(distribution.recipientUserId, 'group.key.distribution', {
        conversationId,
        epoch: dto.epoch,
        fromUserId: auth.userId,
        fromDeviceId: auth.deviceId,
        encryptedChainKey: distribution.encryptedChainKey,
        nonce: distribution.nonce,
        version: distribution.version,
      });
    }

    return {
      conversationId,
      epoch: dto.epoch,
      accepted: dto.distributions.length,
      expiresInSeconds: KEY_DISTRIBUTION_TTL_SECONDS,
    };
  }

  /**
   * Offline-pickup path: return every still-buffered chain-key blob addressed
   * to the caller for the group's current epoch. Non-consuming — a flaky
   * client can safely re-fetch until the TTL expires; there is nothing to
   * protect server-side since each blob is ciphertext only the caller can
   * open.
   */
  async getKeyDistributions(
    auth: AuthContext,
    conversationId: string,
  ): Promise<GroupKeyDistributionsResponse> {
    const conversation = await this.requireSenderKeysGroup(conversationId, auth.userId);
    const epoch = conversation.currentEpoch;

    const distributions: GroupKeyDistributionItem[] = [];
    for (const member of conversation.members) {
      if (member.userId === auth.userId) {
        continue;
      }
      const stored = await this.ephemeralStore.getJson<StoredKeyDistribution>(
        keyDistributionKey(conversationId, epoch, auth.userId, member.userId),
      );
      if (stored) {
        distributions.push(stored);
      }
    }

    return { conversationId, epoch, distributions };
  }

  private async requireSenderKeysGroup(
    conversationId: string,
    userId: string,
  ): Promise<{ currentEpoch: number; members: Array<{ userId: string }> }> {
    const conversation = await this.prisma.conversation.findUnique({
      where: { id: conversationId, type: 'group' },
      select: {
        currentEpoch: true,
        groupUseSenderKeys: true,
        members: { select: { userId: true } },
      },
    });

    if (!conversation) {
      throw notFound('handle_not_found', 'Group not found');
    }
    if (!conversation.members.some((member) => member.userId === userId)) {
      throw forbidden('conversation_membership_required', 'You are not a member of this group');
    }
    if (!conversation.groupUseSenderKeys) {
      throw badRequest('group_sender_keys_disabled', 'Sender Keys are not enabled for this group');
    }

    return conversation;
  }

  /**
   * Bump a group's membership epoch and update the member's epoch window,
   * atomically within the caller's transaction. Returns the new epoch.
   *
   * - join: stamp joinedEpoch = new epoch and clear any prior leftEpoch
   *   (covers re-joins) so the member may decrypt from this generation on.
   * - leave: stamp leftEpoch = new epoch on the member's open window so the
   *   server can refuse post-departure delivery and clients can refuse to
   *   decrypt newer ciphertext.
   *
   * Phase AB.1: bookkeeping + realtime signalling only. The actual Sender-Key
   * redistribution that consumes these epochs is design-only pending external
   * crypto review (docs/group-sender-keys-design.md).
   */
  private async bumpEpochForChange(
    tx: Prisma.TransactionClient,
    conversationId: string,
    change: { userId: string; reason: 'join' | 'leave' },
  ): Promise<number> {
    const conversation = await tx.conversation.update({
      where: { id: conversationId },
      data: { currentEpoch: { increment: 1 } },
      select: { currentEpoch: true },
    });
    const epoch = conversation.currentEpoch;

    if (change.reason === 'join') {
      await tx.groupMemberEpoch.upsert({
        where: {
          conversationId_userId: { conversationId, userId: change.userId },
        },
        update: { joinedEpoch: epoch, leftEpoch: null },
        create: {
          conversationId,
          userId: change.userId,
          joinedEpoch: epoch,
          leftEpoch: null,
        },
      });
    } else {
      // Only close the still-open window; a member with no open window (never
      // joined, or already left) is a no-op rather than an error.
      await tx.groupMemberEpoch.updateMany({
        where: { conversationId, userId: change.userId, leftEpoch: null },
        data: { leftEpoch: epoch },
      });
    }

    return epoch;
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
