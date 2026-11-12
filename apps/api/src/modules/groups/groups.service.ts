import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type {
  GroupKeyDistributeResponse,
  GroupKeyDistributionItem,
  GroupKeyDistributionsResponse,
  TransferGroupOwnershipResponse,
} from '@veil/contracts';
import { GROUP_MAX_MEMBERS } from '@veil/shared';

import {
  ConversationAccessService,
  type ConversationAccess,
} from '../../common/conversation-access/conversation-access.service';
import { removeConversationMember } from '../../common/conversation-access/conversation-departure';
import {
  historyVisibleSince,
  type ConversationAction,
} from '../../common/conversation-access/conversation-policy';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { apiError } from '../../common/errors/api-error';
import type { AuthContext } from '../../common/guards/authenticated-request';
import { PrismaService } from '../../common/prisma.service';
import {
  MESSAGE_SUMMARY_INCLUDE,
  notExpiredWhere,
  toMessageSummary,
} from '../messages/message.mapper';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { SafetyService } from '../safety/safety.service';
import { CreateGroupDto } from './dto/create-group.dto';
import { KeyDistributeDto } from './dto/key-distribute.dto';
import { ManageMemberDto } from './dto/manage-member.dto';
import { TransferOwnershipDto } from './dto/transfer-ownership.dto';
import { UpdateGroupDto } from './dto/update-group.dto';

// How long distributed chain-key blobs are buffered for offline recipients.
// Past the TTL a recipient recovers by asking senders to redistribute (the
// design's self-heal path), so the server never holds key material for long.
const KEY_DISTRIBUTION_TTL_SECONDS = 30 * 60;

// Stands in for the recipient device on legacy user-scoped blobs, which any
// of the recipient's devices may pick up.
const ANY_RECIPIENT_DEVICE = 'any-device';

interface KeyDistributionAddress {
  conversationId: string;
  epoch: number;
  recipientUserId: string;
  recipientDeviceId: string | null;
  senderUserId: string;
  senderDeviceId: string;
}

// One slot per (recipient device, sender device): two devices of the same
// sender each keep their own chain key, and a re-send from the same device
// for the same epoch overwrites its previous blob.
const keyDistributionKey = (address: KeyDistributionAddress): string =>
  [
    'group:keydist',
    address.conversationId,
    address.epoch,
    address.recipientUserId,
    address.recipientDeviceId ?? ANY_RECIPIENT_DEVICE,
    address.senderUserId,
    address.senderDeviceId,
  ].join(':');

@Injectable()
export class GroupsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly ephemeralStore: EphemeralStoreService,
    private readonly access: ConversationAccessService,
    private readonly safety: SafetyService,
  ) {}

  async createGroup(auth: AuthContext, dto: CreateGroupDto) {
    const memberUserIds = await this.resolveFoundingMembers(auth.userId, dto.memberHandles ?? []);

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
          members: { include: { user: { select: { id: true, handle: true } } } },
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
        role: m.role,
      })),
    };
  }

  async getGroup(auth: AuthContext, conversationId: string) {
    const { member } = await this.requireGroupAccess(auth.userId, conversationId, 'readMembers');
    const visibleSince = historyVisibleSince('group', member.joinedAt);

    const conversation = await this.prisma.conversation.findUnique({
      where: { id: conversationId },
      include: {
        members: { include: { user: { select: { id: true, handle: true } } } },
        groupMeta: true,
        messages: {
          where: {
            ...notExpiredWhere(new Date()),
            ...(visibleSince ? { serverReceivedAt: { gte: visibleSince } } : {}),
          },
          orderBy: { conversationOrder: 'desc' },
          take: 1,
          include: MESSAGE_SUMMARY_INCLUDE,
        },
      },
    });

    if (!conversation?.groupMeta) {
      throw apiError('group_not_found', 'Group not found');
    }

    const latest = conversation.messages[0];
    return {
      id: conversation.id,
      type: conversation.type,
      name: conversation.groupMeta.name,
      description: conversation.groupMeta.description,
      isPublic: conversation.groupMeta.isPublic,
      useSenderKeys: conversation.groupUseSenderKeys,
      epoch: conversation.currentEpoch,
      createdAt: conversation.createdAt.toISOString(),
      members: conversation.members.map((m) => ({
        userId: m.userId,
        handle: m.user.handle,
        role: m.role,
      })),
      lastMessage: latest ? toMessageSummary(latest, { viewerUserId: auth.userId }) : null,
    };
  }

  async updateGroup(auth: AuthContext, conversationId: string, dto: UpdateGroupDto) {
    const { conversation } = await this.requireGroupAccess(
      auth.userId,
      conversationId,
      'manageMembers',
    );
    // Turning Sender Keys off would let members fall back to the pairwise
    // envelope after others stopped expecting it — a silent downgrade.
    if (dto.useSenderKeys === false && conversation.groupUseSenderKeys) {
      throw apiError('sender_keys_irreversible', 'Sender Keys cannot be disabled once enabled');
    }

    const updated = await this.prisma.groupMeta.update({
      where: { conversationId },
      data: {
        ...(dto.name !== undefined && { name: dto.name }),
        ...(dto.description !== undefined && { description: dto.description }),
        ...(dto.isPublic !== undefined && { isPublic: dto.isPublic }),
      },
    });

    // The Sender-Keys flag lives on the conversation, not the group meta, and
    // only ever moves false -> true.
    if (dto.useSenderKeys === true && !conversation.groupUseSenderKeys) {
      await this.prisma.conversation.update({
        where: { id: conversationId },
        data: { groupUseSenderKeys: true },
      });
    }

    this.realtimeGateway.emitConversationMembers(
      await this.members(conversationId),
      'conversation.sync',
      { conversationId, reason: 'membership' },
    );

    return {
      conversationId,
      name: updated.name,
      description: updated.description,
      isPublic: updated.isPublic,
      useSenderKeys: conversation.groupUseSenderKeys || dto.useSenderKeys === true,
    };
  }

  async addMember(auth: AuthContext, conversationId: string, dto: ManageMemberDto) {
    await this.requireGroupAccess(auth.userId, conversationId, 'manageMembers');

    const user = await this.prisma.user.findUnique({
      where: { handle: dto.handle.toLowerCase() },
      select: { id: true, handle: true },
    });
    // A block either way answers exactly like an unknown handle, so the
    // actor cannot probe who blocked them.
    if (!user || (await this.safety.isBlockedEitherWay(auth.userId, user.id))) {
      throw apiError('handle_not_found', 'User not found');
    }

    const existingMember = await this.prisma.conversationMember.findUnique({
      where: { conversationId_userId: { conversationId, userId: user.id } },
      select: { role: true },
    });
    if (existingMember) {
      return { conversationId, userId: user.id, handle: user.handle, role: existingMember.role };
    }

    const groupMeta = await this.prisma.groupMeta.findUnique({
      where: { conversationId },
      select: { memberLimit: true },
    });
    const memberLimit = Math.min(groupMeta?.memberLimit ?? GROUP_MAX_MEMBERS, GROUP_MAX_MEMBERS);
    const role = dto.role ?? 'member';

    const epoch = await this.prisma.$transaction(async (tx) => {
      // The epoch bump takes the conversation row lock first, so concurrent
      // adds count members one at a time and cannot overshoot the cap.
      const bumped = await this.bumpEpochForChange(tx, conversationId, {
        userId: user.id,
        reason: 'join',
      });
      const memberCount = await tx.conversationMember.count({ where: { conversationId } });
      if (memberCount >= memberLimit) {
        throw apiError('group_member_limit', `Groups are limited to ${memberLimit} members`);
      }
      await tx.conversationMember.create({ data: { conversationId, userId: user.id, role } });
      return bumped;
    });

    const members = await this.members(conversationId);
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
    await this.requireGroupAccess(auth.userId, conversationId, 'manageMembers');

    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true },
    });
    if (!user) {
      throw apiError('handle_not_found', 'User not found');
    }

    const membership = await this.prisma.conversationMember.findUnique({
      where: { conversationId_userId: { conversationId, userId: user.id } },
      select: { role: true },
    });
    if (!membership) {
      throw apiError('handle_not_found', 'User is not a member of this group');
    }
    if (membership.role === 'owner') {
      throw apiError('owner_immutable', 'Cannot remove the group owner');
    }

    await this.removeFromGroup(conversationId, user.id);
    return { conversationId, removedUserId: user.id };
  }

  async leaveGroup(auth: AuthContext, conversationId: string) {
    const access = await this.access.requireMember(auth.userId, conversationId);
    if (access.conversation.type !== 'group') {
      throw apiError('group_not_found', 'Group not found');
    }
    // A group always has exactly one owner, so the owner hands the role over
    // before leaving.
    if (access.member.role === 'owner') {
      throw apiError('owner_immutable', 'Transfer ownership before leaving the group');
    }

    await this.removeFromGroup(conversationId, auth.userId);
    return { conversationId, left: true };
  }

  async transferOwnership(
    auth: AuthContext,
    conversationId: string,
    dto: TransferOwnershipDto,
  ): Promise<TransferGroupOwnershipResponse> {
    const { member } = await this.requireGroupAccess(auth.userId, conversationId, 'manageMembers');
    if (member.role !== 'owner') {
      throw apiError('conversation_role_required', 'Only the owner can transfer ownership');
    }
    if (dto.userId === auth.userId) {
      throw apiError('validation_failed', 'Ownership must go to another member');
    }

    const target = await this.prisma.conversationMember.findUnique({
      where: { conversationId_userId: { conversationId, userId: dto.userId } },
      select: { role: true },
    });
    if (!target) {
      throw apiError('conversation_membership_required', 'The new owner must be a current member');
    }

    // The two members swap roles, so the group keeps exactly one owner.
    // group_metas.created_by_user_id follows the role: account deletion
    // deletes the groups it names, so it must name the current owner, never a
    // former one who may since have left.
    await this.prisma.$transaction(async (tx) => {
      await tx.conversationMember.update({
        where: { conversationId_userId: { conversationId, userId: dto.userId } },
        data: { role: 'owner' },
      });
      await tx.conversationMember.update({
        where: { conversationId_userId: { conversationId, userId: auth.userId } },
        data: { role: target.role },
      });
      await tx.groupMeta.update({
        where: { conversationId },
        data: { createdByUserId: dto.userId },
      });
    });

    this.realtimeGateway.emitConversationMembers(
      await this.members(conversationId),
      'conversation.sync',
      { conversationId, reason: 'membership' },
    );

    return { conversationId, ownerUserId: dto.userId, previousOwnerUserId: auth.userId };
  }

  /**
   * Accept a batch of sender-key chain-key distributions from one member
   * device and relay them to the addressed members. Every blob is opaque: it
   * was encrypted under the sender↔recipient 1:1 ratchet before it reached
   * us, so the server buffers and forwards ciphertext it cannot read.
   *
   * Guards: the caller may send in the group, the group has Sender Keys
   * enabled, the stamped epoch is current, every recipient is a current
   * member other than the sender, and an addressed recipient device is one
   * of that recipient's active devices. Validation is all-or-nothing. Blobs
   * are buffered for KEY_DISTRIBUTION_TTL_SECONDS (offline pickup via
   * getKeyDistributions) and fanned out live as group.key.distribution.
   */
  async distributeKeys(
    auth: AuthContext,
    conversationId: string,
    dto: KeyDistributeDto,
  ): Promise<GroupKeyDistributeResponse> {
    const { conversation } = await this.requireSenderKeysGroup(auth.userId, conversationId);

    if (dto.epoch !== conversation.currentEpoch) {
      throw apiError(
        'group_epoch_stale',
        `Epoch ${dto.epoch} is not the conversation's current epoch`,
      );
    }

    const memberIds = new Set((await this.members(conversationId)).map((m) => m.userId));
    for (const distribution of dto.distributions) {
      if (distribution.recipientUserId === auth.userId) {
        throw apiError('key_distribution_invalid', 'Cannot distribute a chain key to yourself');
      }
      if (!memberIds.has(distribution.recipientUserId)) {
        throw apiError(
          'key_distribution_invalid',
          'Every recipient must be a current group member',
        );
      }
    }
    await this.assertRecipientDevices(dto);

    const createdAt = new Date().toISOString();
    for (const distribution of dto.distributions) {
      const recipientDeviceId = distribution.recipientDeviceId ?? null;
      const stored: GroupKeyDistributionItem = {
        fromUserId: auth.userId,
        fromDeviceId: auth.deviceId,
        recipientDeviceId,
        encryptedChainKey: distribution.encryptedChainKey,
        nonce: distribution.nonce,
        version: distribution.version,
        createdAt,
      };
      await this.ephemeralStore.setJson(
        keyDistributionKey({
          conversationId,
          epoch: dto.epoch,
          recipientUserId: distribution.recipientUserId,
          recipientDeviceId,
          senderUserId: auth.userId,
          senderDeviceId: auth.deviceId,
        }),
        stored,
        KEY_DISTRIBUTION_TTL_SECONDS,
      );

      const event = {
        conversationId,
        epoch: dto.epoch,
        fromUserId: auth.userId,
        fromDeviceId: auth.deviceId,
        encryptedChainKey: distribution.encryptedChainKey,
        nonce: distribution.nonce,
        version: distribution.version,
      };
      if (recipientDeviceId) {
        this.realtimeGateway.emitToDevice(recipientDeviceId, 'group.key.distribution', event);
      } else {
        this.realtimeGateway.emitToUser(
          distribution.recipientUserId,
          'group.key.distribution',
          event,
        );
      }
    }

    return {
      conversationId,
      epoch: dto.epoch,
      accepted: dto.distributions.length,
      expiresInSeconds: KEY_DISTRIBUTION_TTL_SECONDS,
    };
  }

  /**
   * Offline-pickup path: every still-buffered chain-key blob for the group's
   * current epoch that is addressed to the calling device, plus the legacy
   * user-scoped blobs addressed to the caller. Only blobs from the senders'
   * currently active devices are returned. Non-consuming — a flaky client can
   * safely re-fetch until the TTL expires; each blob is ciphertext only the
   * caller can open.
   */
  async getKeyDistributions(
    auth: AuthContext,
    conversationId: string,
  ): Promise<GroupKeyDistributionsResponse> {
    const { conversation } = await this.requireSenderKeysGroup(auth.userId, conversationId);
    const epoch = conversation.currentEpoch;

    const otherMemberIds = (await this.members(conversationId))
      .map((member) => member.userId)
      .filter((userId) => userId !== auth.userId);
    const senderDevices = await this.prisma.device.findMany({
      where: { userId: { in: otherMemberIds }, isActive: true, revokedAt: null },
      select: { id: true, userId: true },
    });

    const distributions: GroupKeyDistributionItem[] = [];
    for (const senderDevice of senderDevices) {
      for (const recipientDeviceId of [auth.deviceId, null]) {
        const stored = await this.ephemeralStore.getJson<GroupKeyDistributionItem>(
          keyDistributionKey({
            conversationId,
            epoch,
            recipientUserId: auth.userId,
            recipientDeviceId,
            senderUserId: senderDevice.userId,
            senderDeviceId: senderDevice.id,
          }),
        );
        if (stored) {
          distributions.push(stored);
        }
      }
    }

    return { conversationId, epoch, distributions };
  }

  private async requireGroupAccess(
    userId: string,
    conversationId: string,
    action: ConversationAction,
  ): Promise<ConversationAccess> {
    const access = await this.access.requireAccess(userId, conversationId, action);
    if (access.conversation.type !== 'group') {
      throw apiError('group_not_found', 'Group not found');
    }
    return access;
  }

  private async requireSenderKeysGroup(
    userId: string,
    conversationId: string,
  ): Promise<ConversationAccess> {
    const access = await this.requireGroupAccess(userId, conversationId, 'send');
    if (!access.conversation.groupUseSenderKeys) {
      throw apiError('group_sender_keys_disabled', 'Sender Keys are not enabled for this group');
    }
    return access;
  }

  // Founding members the creator may add. A block either way silently drops
  // the handle, so creating a group reveals nothing about who blocked whom.
  private async resolveFoundingMembers(
    creatorUserId: string,
    handles: string[],
  ): Promise<string[]> {
    if (handles.length === 0) {
      return [];
    }
    const users = await this.prisma.user.findMany({
      where: { handle: { in: handles.map((handle) => handle.toLowerCase()) } },
      select: { id: true },
    });

    const memberUserIds: string[] = [];
    for (const user of users) {
      if (
        user.id !== creatorUserId &&
        !(await this.safety.isBlockedEitherWay(creatorUserId, user.id))
      ) {
        memberUserIds.push(user.id);
      }
    }
    return memberUserIds;
  }

  private async assertRecipientDevices(dto: KeyDistributeDto): Promise<void> {
    const addressedDeviceIds = dto.distributions.flatMap((distribution) =>
      distribution.recipientDeviceId ? [distribution.recipientDeviceId] : [],
    );
    if (addressedDeviceIds.length === 0) {
      return;
    }

    const devices = await this.prisma.device.findMany({
      where: { id: { in: addressedDeviceIds }, isActive: true, revokedAt: null },
      select: { id: true, userId: true },
    });
    const ownerByDeviceId = new Map(devices.map((device) => [device.id, device.userId]));
    for (const distribution of dto.distributions) {
      if (
        distribution.recipientDeviceId &&
        ownerByDeviceId.get(distribution.recipientDeviceId) !== distribution.recipientUserId
      ) {
        throw apiError(
          'key_distribution_invalid',
          'recipientDeviceId must be an active device of the recipient',
        );
      }
    }
  }

  private async removeFromGroup(conversationId: string, userId: string): Promise<void> {
    const epoch = await this.prisma.$transaction(async (tx) => {
      await removeConversationMember(tx, conversationId, userId);
      return this.bumpEpochForChange(tx, conversationId, { userId, reason: 'leave' });
    });

    const members = await this.members(conversationId);
    this.realtimeGateway.emitConversationMembers([...members, { userId }], 'conversation.sync', {
      conversationId,
      reason: 'membership',
    });
    // Only remaining members get the new epoch — the departed user must not
    // learn (or act on) the post-departure generation.
    this.realtimeGateway.emitConversationMembers(members, 'group.epoch.bumped', {
      conversationId,
      epoch,
      reason: 'leave',
      userId,
    });
  }

  /**
   * Bump a group's membership epoch and update the member's epoch row,
   * atomically within the caller's transaction. Returns the new epoch.
   *
   * - join: record joinedEpoch = new epoch (a re-join starts a fresh row).
   * - leave: delete the member's row. Nothing reads when someone left, and
   *   keeping it would list every former member of the group.
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
        update: { joinedEpoch: epoch },
        create: {
          conversationId,
          userId: change.userId,
          joinedEpoch: epoch,
        },
      });
    } else {
      // deleteMany: a member with no row (a group created before epochs) is a
      // no-op rather than an error.
      await tx.groupMemberEpoch.deleteMany({
        where: { conversationId, userId: change.userId },
      });
    }

    return epoch;
  }

  private members(conversationId: string): Promise<Array<{ userId: string }>> {
    return this.prisma.conversationMember.findMany({
      where: { conversationId },
      select: { userId: true },
    });
  }
}
