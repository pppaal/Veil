import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type {
  DeleteLocalMessageResponse,
  DeleteMessageResponse,
  EditMessageResponse,
  MarkMessageReadResponse,
  SendMessageResponse,
} from '@veil/contracts';
import type { ConversationType } from '@veil/shared';
import { isUUID } from 'class-validator';

import { AppConfigService } from '../../common/config/app-config.service';
import {
  ConversationAccessService,
  type ConversationAccess,
} from '../../common/conversation-access/conversation-access.service';
import {
  EMITS_RECEIPTS,
  historyVisibleSince,
  messageAudienceJoinedBy,
  type ConversationAction,
} from '../../common/conversation-access/conversation-policy';
import { recordDeviceSynced } from '../../common/device-activity';
import { apiError } from '../../common/errors/api-error';
import { AppLoggerService } from '../../common/logger/app-logger.service';
import { describeFailure } from '../../common/logger/describe-failure';
import { PrismaService } from '../../common/prisma.service';
import { MetricsService } from '../metrics/metrics.service';
import { wakesRecipient } from '../push/push-policy';
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

// What send() resolved for a new row beyond the client's envelope.
type NewMessageFields = {
  expiresAt: Date | null;
  attachmentId: string | null;
  receiptUserIds: string[];
};

// Recipients whose push wakes are dispatched at the same time.
const PUSH_WAKE_CONCURRENCY = 8;

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
    private readonly logger: AppLoggerService,
  ) {}

  async send(auth: Actor, dto: SendMessageDto): Promise<SendMessageResponse> {
    if (
      dto.envelope.senderDeviceId !== auth.deviceId ||
      dto.conversationId !== dto.envelope.conversationId
    ) {
      throw apiError('envelope_context_mismatch', 'Envelope sender context mismatch');
    }

    const access = await this.access.requireMember(auth.userId, dto.conversationId);

    // A retry of a message the relay already stored gets that message back
    // before any rule a new send must meet: since it was accepted, the group
    // may have switched to Sender Keys or the peer may have blocked, and the
    // sender must not be told that a delivered message failed.
    const existing = await this.findExistingMessage(auth.deviceId, dto.clientMessageId);
    if (existing) {
      return {
        message: toMessageSummary(existing, { viewerUserId: auth.userId }),
        idempotent: true,
      };
    }

    await this.access.authorize(access, 'send');
    const { conversation } = access;
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
    }
    this.realtimeGateway.emitConversationMembers(
      memberUserIds.map((userId) => ({ userId })),
      'conversation.sync',
      { conversationId: dto.conversationId, reason: 'message' },
    );
    // Push is a fallback and must never hold up the relay: every realtime
    // event is out first, and the wakes run after the response, so a slow or
    // hung push provider delays neither the sender's answer nor any member.
    if (wakesRecipient(dto.envelope.messageType)) {
      void this.dispatchPushFallbacks(recipientUserIds, dto.conversationId);
    }

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
      // group members never learn who read what, and a blocked direct peer
      // does not learn that the reader is still reading.
      const audience = (await this.access.isPeerReachable(access))
        ? [{ userId: senderUserId }, { userId: auth.userId }]
        : [{ userId: auth.userId }];
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
        await this.messageAudience(access.conversation.type, message),
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
    const { message, access } = await this.requireMessageAccess(auth.userId, messageId, 'edit');
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
      await this.messageAudience(access.conversation.type, message),
      'message.edited',
      toMessageSummary(updated, { broadcast: true }),
    );
    return { message: toMessageSummary(updated, { viewerUserId: auth.userId }) };
  }

  // Soft delete. The row stays so reply chains still resolve, but the
  // ciphertext is replaced with a tombstone so the server cannot re-deliver
  // the original body even by accident.
  async delete(auth: Actor, messageId: string): Promise<DeleteMessageResponse> {
    const { message, access } = await this.requireMessageAccess(auth.userId, messageId, 'delete');
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
      await this.messageAudience(access.conversation.type, message),
      'message.deleted',
      { messageId, deletedAt: deletedAt.toISOString() },
    );
    return { messageId, deletedAt: deletedAt.toISOString() };
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

  private async persistMessage(
    auth: Actor,
    dto: SendMessageDto,
    resolved: NewMessageFields,
  ): Promise<{ message: MessageSummaryRow; idempotent: boolean }> {
    try {
      return { message: await this.insertWithNextOrder(auth, dto, resolved), idempotent: false };
    } catch (error) {
      if ((error as { code?: unknown } | null)?.code !== 'P2002') {
        throw error;
      }
      // A concurrent retry of the same (device, clientMessageId) won the
      // insert; hand back the stored message instead of an error.
      const existing = await this.findExistingMessage(auth.deviceId, dto.clientMessageId);
      if (existing) {
        return { message: existing, idempotent: true };
      }
      // The only other unique key is (conversation_id, conversation_order),
      // so the counter is behind a row written without it.
      await this.resyncOrderCounter(dto.conversationId);
      return { message: await this.insertWithNextOrder(auth, dto, resolved), idempotent: false };
    }
  }

  /**
   * Allocates the next conversationOrder from conversations.last_order and
   * inserts the message in one default-isolation transaction. The increment
   * holds the conversation row lock until commit, so concurrent sends get
   * distinct, gap-free orders without SERIALIZABLE retries; a rolled-back
   * send also rolls back its increment.
   */
  private insertWithNextOrder(
    auth: Actor,
    dto: SendMessageDto,
    resolved: NewMessageFields,
  ): Promise<MessageSummaryRow> {
    return this.prisma.$transaction(async (tx) => {
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
  }

  /**
   * Raises the counter to the highest stored order. An instance still
   * running the pre-0017 MAX()+1 allocator during a rolling deploy inserts
   * without bumping last_order; every later send would then collide and roll
   * its own increment back, wedging the conversation for good.
   */
  private async resyncOrderCounter(conversationId: string): Promise<void> {
    const newest = await this.prisma.message.findFirst({
      where: { conversationId },
      orderBy: { conversationOrder: 'desc' },
      select: { conversationOrder: true },
    });
    if (newest) {
      await this.prisma.conversation.updateMany({
        where: { id: conversationId, lastOrder: { lt: newest.conversationOrder } },
        data: { lastOrder: newest.conversationOrder },
      });
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

  /**
   * The members who receive events about a stored message: those who can
   * list it. A group member added after the message reached the relay gets
   * none of its edits, deletions or consumption, exactly as history hides the
   * message itself.
   */
  private messageAudience(
    type: ConversationType,
    message: Pick<AccessedMessage, 'conversationId' | 'serverReceivedAt'>,
  ): Promise<Array<{ userId: string }>> {
    const joinedBy = messageAudienceJoinedBy(type, message.serverReceivedAt);
    return this.prisma.conversationMember.findMany({
      where: {
        conversationId: message.conversationId,
        ...(joinedBy ? { joinedAt: { lte: joinedBy } } : {}),
      },
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
    await recordDeviceSynced(this.prisma, deviceId);
  }

  // Never rejects: it runs detached from the request. A few recipients at a
  // time, so a large group neither waits on one slow wake after another nor
  // takes every database connection at once.
  private async dispatchPushFallbacks(
    recipientUserIds: readonly string[],
    conversationId: string,
  ): Promise<void> {
    const queue = [...recipientUserIds];
    const worker = async () => {
      for (let next = queue.shift(); next !== undefined; next = queue.shift()) {
        try {
          await this.dispatchPushFallbackIfNeeded(next, conversationId);
        } catch (error) {
          this.logger.warn('push.wake_dispatch_failed', { error: describeFailure(error) });
        }
      }
    };
    await Promise.all(
      Array.from({ length: Math.min(PUSH_WAKE_CONCURRENCY, queue.length) }, worker),
    );
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

    // PushService.sendMessageHint never rejects (it logs and counts
    // failures); the devices are woken in parallel.
    await Promise.all(
      recipientDevices
        .filter((device) => device.pushToken && !connectedDeviceIds.has(device.id))
        .map((device) => this.pushService.sendMessageHint(device.pushToken!, { kind: 'wake' })),
    );
  }
}
