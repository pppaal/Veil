import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type {
  AddReactionResponse,
  DeleteLocalMessageResponse,
  DeleteMessageResponse,
  EditMessageResponse,
  MarkMessageReadResponse,
  RemoveReactionResponse,
  SendMessageResponse,
} from '@veil/contracts';
import { isUUID } from 'class-validator';

import { AppConfigService } from '../../common/config/app-config.service';
import {
  ConversationAccessService,
  type ConversationAccess,
} from '../../common/conversation-access/conversation-access.service';
import {
  EMITS_RECEIPTS,
  historyVisibleSince,
  type ConversationAction,
} from '../../common/conversation-access/conversation-policy';
import { apiError } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';
import { MetricsService } from '../metrics/metrics.service';
import { PushService } from '../push/push.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { SafetyService } from '../safety/safety.service';
import { EditMessageDto, SendMessageDto } from './dto/send-message.dto';
import {
  MESSAGE_SUMMARY_INCLUDE,
  notExpiredWhere,
  toMessageSummary,
  type MessageSummaryRow,
} from './message.mapper';
import { assertEnvelopeAccepted, resolveExpiresAt } from './message-send-policy';

// How long the sender may re-encrypt a message after the relay accepted it.
const EDIT_WINDOW_MS = 24 * 60 * 60 * 1000;

// What the message-level actions need to authorize against a stored message.
const MESSAGE_ACCESS_SELECT = {
  id: true,
  conversationId: true,
  conversationOrder: true,
  senderDeviceId: true,
  envelopeVersion: true,
  viewOnce: true,
  deletedAt: true,
  expiresAt: true,
  serverReceivedAt: true,
  senderDevice: { select: { userId: true } },
} satisfies Prisma.MessageSelect;

type AccessedMessage = Prisma.MessageGetPayload<{ select: typeof MESSAGE_ACCESS_SELECT }>;

type Actor = { userId: string; deviceId: string };

@Injectable()
export class MessagesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pushService: PushService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly safetyService: SafetyService,
    private readonly metrics: MetricsService,
    private readonly access: ConversationAccessService,
    private readonly config: AppConfigService,
  ) {}

  async send(auth: Actor, dto: SendMessageDto): Promise<SendMessageResponse> {
    if (
      dto.envelope.senderDeviceId !== auth.deviceId ||
      dto.conversationId !== dto.envelope.conversationId
    ) {
      throw apiError('envelope_context_mismatch', 'Envelope sender context mismatch');
    }

    const { conversation } = await this.access.requireAccess(
      auth.userId,
      dto.conversationId,
      'send',
    );
    assertEnvelopeAccepted(conversation, dto.envelope, this.config.isProduction);

    const memberUserIds = await this.memberUserIds(dto.conversationId);
    const recipientUserIds = memberUserIds.filter((userId) => userId !== auth.userId);

    if (
      conversation.type === 'direct' &&
      (recipientUserIds.length !== 1 || dto.envelope.recipientUserId !== recipientUserIds[0])
    ) {
      throw apiError(
        'direct_peer_mismatch',
        'Envelope recipient does not match direct conversation peer',
      );
    }

    const existing = await this.findExistingMessage(auth.deviceId, dto.clientMessageId);
    if (existing) {
      return {
        message: toMessageSummary(existing, { viewerUserId: auth.userId }),
        idempotent: true,
      };
    }

    // Group Sender Keys epoch gate. Runs after the idempotency short-circuit
    // so a retry of an already-accepted message still succeeds after an epoch
    // bump; a genuinely new send must carry the current membership generation
    // so the sender refetches and re-encrypts when a member left.
    if (conversation.type === 'group' && conversation.groupUseSenderKeys) {
      if (dto.groupEpoch === undefined) {
        throw apiError('group_epoch_required', 'Group epoch required for this conversation');
      }
      if (dto.groupEpoch !== conversation.currentEpoch) {
        throw apiError(
          'group_epoch_stale',
          'Group membership has changed; refetch the current epoch and resend',
        );
      }
    }

    const now = new Date();
    const expiresAt = resolveExpiresAt(
      dto.envelope.expiresAt,
      conversation.disappearingTimerSeconds,
      now,
    );
    await this.assertReplyTarget(dto.conversationId, dto.replyToMessageId, now);
    const attachmentId = await this.resolveAttachmentId(auth.userId, dto.envelope.attachment);

    const created = await this.persistMessage(auth, dto, {
      expiresAt,
      attachmentId,
      receiptUserIds: EMITS_RECEIPTS[conversation.type] ? recipientUserIds : [],
    });

    if (!created.idempotent) {
      // Throughput signal only, labelled by message type — no conversation or
      // device identity. Guarded so telemetry can't fail an accepted message.
      try {
        this.metrics.messagesSentTotal.inc({ message_type: created.message.messageType });
      } catch {
        // best-effort telemetry
      }
    }

    await this.recordDeviceProgress(auth.deviceId, dto.conversationId, {
      lastSyncedConversationOrder: created.message.conversationOrder,
    });

    const broadcastSummary = toMessageSummary(created.message, { broadcast: true });
    for (const recipientUserId of recipientUserIds) {
      this.realtimeGateway.emitToUser(recipientUserId, 'message.new', broadcastSummary);
      await this.dispatchPushFallbackIfNeeded(recipientUserId, dto.conversationId);
    }
    this.realtimeGateway.emitConversationMembers(
      memberUserIds.map((userId) => ({ userId })),
      'conversation.sync',
      { conversationId: dto.conversationId, reason: 'message' },
    );

    return {
      message: toMessageSummary(created.message, { viewerUserId: auth.userId }),
      idempotent: created.idempotent,
    };
  }

  async markRead(auth: Actor, messageId: string): Promise<MarkMessageReadResponse> {
    const { message, access } = await this.requireMessageAccess(auth.userId, messageId, 'markRead');
    const senderUserId = message.senderDevice.userId;
    const ownMessage = senderUserId === auth.userId;
    // Reading your own message reports nothing to anyone, and a channel has
    // no receipts at all.
    const recordsReceipt = EMITS_RECEIPTS[access.conversation.type] && !ownMessage;
    const consumesViewOnce = message.viewOnce && !ownMessage;
    const now = new Date();

    const previous = recordsReceipt
      ? await this.prisma.messageReceipt.findUnique({
          where: { messageId_userId: { messageId, userId: auth.userId } },
        })
      : null;

    // The receipt and (for view-once) the row delete commit together, so a
    // crash between them cannot leave view-once ciphertext on disk after the
    // read was recorded.
    const readAt = await this.prisma.$transaction(async (tx) => {
      const receipt = recordsReceipt
        ? await tx.messageReceipt.upsert({
            where: { messageId_userId: { messageId, userId: auth.userId } },
            update: { deliveredAt: previous?.deliveredAt ?? now, readAt: previous?.readAt ?? now },
            create: { messageId, userId: auth.userId, deliveredAt: now, readAt: now },
          })
        : null;
      if (consumesViewOnce) {
        try {
          await tx.message.delete({ where: { id: messageId } });
        } catch {
          // A concurrent read already consumed it; the consumed broadcast
          // below still fires so every member drops it from their cache.
        }
      }
      return receipt?.readAt ?? now;
    });

    if (recordsReceipt) {
      // Receipts go to the sender and the reader's own devices only; other
      // group members never learn who read what.
      const audience = [{ userId: senderUserId }, { userId: auth.userId }];
      if (!previous?.deliveredAt) {
        this.realtimeGateway.emitConversationMembers(audience, 'message.delivered', {
          messageId,
          userId: auth.userId,
          deliveredAt: now.toISOString(),
        });
      }
      if (!previous?.readAt) {
        this.realtimeGateway.emitConversationMembers(audience, 'message.read', {
          messageId,
          userId: auth.userId,
          readAt: readAt.toISOString(),
        });
      }
    }

    await this.recordDeviceProgress(auth.deviceId, message.conversationId, {
      lastSyncedConversationOrder: message.conversationOrder,
      lastReadConversationOrder: message.conversationOrder,
    });

    if (consumesViewOnce) {
      this.realtimeGateway.emitConversationMembers(
        await this.members(message.conversationId),
        'message.consumed',
        { messageId, conversationId: message.conversationId, consumedAt: now.toISOString() },
      );
    }

    return { messageId, readAt: readAt.toISOString() };
  }

  async deleteLocal(
    auth: { userId: string },
    messageId: string,
  ): Promise<DeleteLocalMessageResponse> {
    await this.requireMessageAccess(auth.userId, messageId, 'readHistory');
    return { messageId, acknowledged: true };
  }

  // Edit replaces the ciphertext in place. Only the original sending device
  // may rewrite, within the edit window and under the same envelope version
  // (an edit must not switch decryptors). editCount lets the UI show
  // "(수정됨)" without the server keeping prior revisions.
  async edit(auth: Actor, messageId: string, dto: EditMessageDto): Promise<EditMessageResponse> {
    const { message } = await this.requireMessageAccess(auth.userId, messageId, 'edit');
    if (message.senderDeviceId !== auth.deviceId) {
      throw apiError('message_not_owned', 'Only the original sender may edit');
    }
    if (message.deletedAt) {
      throw apiError('message_deleted', 'Cannot edit a deleted message');
    }
    if (message.viewOnce) {
      throw apiError('view_once_immutable', 'View-once messages cannot be edited');
    }
    const now = new Date();
    if (now.getTime() - message.serverReceivedAt.getTime() > EDIT_WINDOW_MS) {
      throw apiError('edit_window_expired', 'Messages can only be edited for 24 hours');
    }
    if (dto.version !== message.envelopeVersion) {
      throw apiError(
        'envelope_version_mismatch',
        'An edit must keep the original envelope version',
      );
    }

    const updated = await this.prisma.message.update({
      where: { id: messageId },
      data: {
        ciphertext: dto.ciphertext,
        nonce: dto.nonce,
        editedAt: now,
        editCount: { increment: 1 },
      },
      include: MESSAGE_SUMMARY_INCLUDE,
    });

    this.realtimeGateway.emitConversationMembers(
      await this.members(message.conversationId),
      'message.edited',
      toMessageSummary(updated, { broadcast: true }),
    );
    return { message: toMessageSummary(updated, { viewerUserId: auth.userId }) };
  }

  // Soft delete. The row stays so reply chains still resolve, but the
  // ciphertext is replaced with a tombstone so the server cannot re-deliver
  // the original body even by accident.
  async delete(auth: Actor, messageId: string): Promise<DeleteMessageResponse> {
    const { message } = await this.requireMessageAccess(auth.userId, messageId, 'delete');
    if (message.senderDeviceId !== auth.deviceId) {
      throw apiError('message_not_owned', 'Only the original sender may delete');
    }
    if (message.deletedAt) {
      return { messageId, deletedAt: message.deletedAt.toISOString() };
    }

    const deletedAt = new Date();
    await this.prisma.message.update({
      where: { id: messageId },
      data: {
        deletedAt,
        ciphertext: 'deleted',
        nonce: 'deleted',
        attachmentRef: Prisma.JsonNull,
      },
    });

    this.realtimeGateway.emitConversationMembers(
      await this.members(message.conversationId),
      'message.deleted',
      { messageId, deletedAt: deletedAt.toISOString() },
    );
    return { messageId, deletedAt: deletedAt.toISOString() };
  }

  async addReaction(
    auth: { userId: string },
    messageId: string,
    emoji: string,
  ): Promise<AddReactionResponse> {
    const { message } = await this.requireMessageAccess(auth.userId, messageId, 'react');

    const reaction = await this.prisma.reaction.upsert({
      where: { messageId_userId: { messageId, userId: auth.userId } },
      update: { emoji },
      create: { messageId, userId: auth.userId, emoji },
    });

    this.realtimeGateway.emitConversationMembers(
      await this.members(message.conversationId),
      'message.reaction',
      { messageId, userId: auth.userId, emoji, action: 'add' },
    );
    return { reactionId: reaction.id, messageId, emoji };
  }

  async removeReaction(
    auth: { userId: string },
    messageId: string,
  ): Promise<RemoveReactionResponse> {
    const { message } = await this.requireMessageAccess(auth.userId, messageId, 'react');

    await this.prisma.reaction.deleteMany({ where: { messageId, userId: auth.userId } });

    this.realtimeGateway.emitConversationMembers(
      await this.members(message.conversationId),
      'message.reaction',
      { messageId, userId: auth.userId, emoji: '', action: 'remove' },
    );
    return { messageId, acknowledged: true };
  }

  /**
   * Authorizes a message-level action. Beyond the conversation policy, a
   * message the actor could not list (expired, or sent to a group before
   * they joined) is reported as not found, exactly as history hides it.
   */
  private async requireMessageAccess(
    userId: string,
    messageId: string,
    action: ConversationAction,
  ): Promise<{ message: AccessedMessage; access: ConversationAccess }> {
    if (!isUUID(messageId)) {
      throw apiError('validation_failed', 'messageId must be a UUID');
    }
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      select: MESSAGE_ACCESS_SELECT,
    });
    if (!message) {
      throw apiError('message_not_found');
    }

    const access = await this.access.requireAccess(userId, message.conversationId, action);
    const visibleSince = historyVisibleSince(access.conversation.type, access.member.joinedAt);
    const expired = message.expiresAt !== null && message.expiresAt.getTime() <= Date.now();
    if (expired || (visibleSince && message.serverReceivedAt < visibleSince)) {
      throw apiError('message_not_found');
    }
    return { message, access };
  }

  private async assertReplyTarget(
    conversationId: string,
    replyToMessageId: string | null | undefined,
    now: Date,
  ): Promise<void> {
    if (!replyToMessageId) {
      return;
    }
    const target = isUUID(replyToMessageId)
      ? await this.prisma.message.findFirst({
          where: { id: replyToMessageId, conversationId, deletedAt: null, ...notExpiredWhere(now) },
          select: { id: true },
        })
      : null;
    if (!target) {
      throw apiError(
        'reply_target_invalid',
        'A reply must reference a live message in the same conversation',
      );
    }
  }

  // The attachment must be a finished upload from one of the sender's own
  // devices. Ownership is checked before upload state so a probe cannot learn
  // anything about another user's uploads.
  private async resolveAttachmentId(
    senderUserId: string,
    attachment: { attachmentId: string } | null | undefined,
  ): Promise<string | null> {
    if (!attachment) {
      return null;
    }
    const record = await this.prisma.attachment.findUnique({
      where: { id: attachment.attachmentId },
      select: { uploadStatus: true, uploaderDevice: { select: { userId: true } } },
    });
    if (!record) {
      throw apiError('attachment_not_found');
    }
    if (record.uploaderDevice.userId !== senderUserId) {
      throw apiError('attachment_forbidden', 'Attachment belongs to another user');
    }
    if (record.uploadStatus !== 'uploaded') {
      throw apiError('attachment_upload_invalid', 'Attachment upload is not complete');
    }
    return attachment.attachmentId;
  }

  /**
   * Allocates the next conversationOrder from conversations.last_order and
   * inserts the message in one default-isolation transaction. The increment
   * holds the conversation row lock until commit, so concurrent sends get
   * distinct, gap-free orders without SERIALIZABLE retries; a rolled-back
   * send also rolls back its increment.
   */
  private async persistMessage(
    auth: Actor,
    dto: SendMessageDto,
    resolved: { expiresAt: Date | null; attachmentId: string | null; receiptUserIds: string[] },
  ): Promise<{ message: MessageSummaryRow; idempotent: boolean }> {
    try {
      const message = await this.prisma.$transaction(async (tx) => {
        const { lastOrder } = await tx.conversation.update({
          where: { id: dto.conversationId },
          data: { lastOrder: { increment: 1 } },
          select: { lastOrder: true },
        });
        return tx.message.create({
          data: {
            conversationId: dto.conversationId,
            senderDeviceId: auth.deviceId,
            clientMessageId: dto.clientMessageId,
            conversationOrder: lastOrder,
            envelopeVersion: dto.envelope.version,
            ciphertext: dto.envelope.ciphertext,
            nonce: dto.envelope.nonce,
            messageType: dto.envelope.messageType,
            attachmentId: resolved.attachmentId,
            attachmentRef: resolved.attachmentId
              ? { attachmentId: resolved.attachmentId }
              : Prisma.JsonNull,
            expiresAt: resolved.expiresAt,
            viewOnce: dto.envelope.viewOnce === true,
            replyToMessageId: dto.replyToMessageId ?? null,
            receipts: { create: resolved.receiptUserIds.map((userId) => ({ userId })) },
          },
          include: MESSAGE_SUMMARY_INCLUDE,
        });
      });
      return { message, idempotent: false };
    } catch (error) {
      // A concurrent retry of the same (device, clientMessageId) won the
      // insert; hand back the stored message instead of an error.
      if ((error as { code?: unknown } | null)?.code === 'P2002') {
        const existing = await this.findExistingMessage(auth.deviceId, dto.clientMessageId);
        if (existing) {
          return { message: existing, idempotent: true };
        }
      }
      throw error;
    }
  }

  private findExistingMessage(
    senderDeviceId: string,
    clientMessageId: string,
  ): Promise<MessageSummaryRow | null> {
    return this.prisma.message.findFirst({
      where: { senderDeviceId, clientMessageId },
      include: MESSAGE_SUMMARY_INCLUDE,
    });
  }

  private async memberUserIds(conversationId: string): Promise<string[]> {
    return (await this.members(conversationId)).map((member) => member.userId);
  }

  private members(conversationId: string): Promise<Array<{ userId: string }>> {
    return this.prisma.conversationMember.findMany({
      where: { conversationId },
      select: { userId: true },
    });
  }

  private async recordDeviceProgress(
    deviceId: string,
    conversationId: string,
    progress: { lastSyncedConversationOrder: number; lastReadConversationOrder?: number },
  ): Promise<void> {
    await this.prisma.deviceConversationState.upsert({
      where: { deviceId_conversationId: { deviceId, conversationId } },
      update: progress,
      create: { deviceId, conversationId, ...progress },
    });
    await this.prisma.device.update({
      where: { id: deviceId },
      data: { lastSyncAt: new Date() },
    });
  }

  private async dispatchPushFallbackIfNeeded(
    recipientUserId: string,
    conversationId: string,
  ): Promise<void> {
    if (await this.safetyService.isConversationMutedForUser(recipientUserId, conversationId)) {
      // Muted: the message still persists and flows over the realtime
      // socket if the app is open, but we skip the wake to keep the phone
      // quiet.
      return;
    }

    const connectedDeviceIds = new Set(
      this.realtimeGateway.connectedDeviceIdsForUser(recipientUserId),
    );
    const recipientDevices = await this.prisma.device.findMany({
      where: {
        userId: recipientUserId,
        isActive: true,
        revokedAt: null,
        pushToken: { not: null },
      },
      select: { id: true, pushToken: true },
    });

    for (const device of recipientDevices) {
      if (!device.pushToken || connectedDeviceIds.has(device.id)) {
        continue;
      }
      await this.pushService.sendMessageHint(device.pushToken, { kind: 'wake' });
    }
  }
}
