import { Inject, Injectable } from '@nestjs/common';
import type { Prisma } from '@prisma/client';

import { AppLoggerService } from '../../common/logger/app-logger.service';
import { PrismaService } from '../../common/prisma.service';
import {
  ATTACHMENT_STORAGE_GATEWAY,
  type AttachmentStorageGateway,
} from '../attachments/attachment-storage.gateway';
import { RetiredHandlesService } from '../handles/retired-handles.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';

// Right-to-erasure cascade for a full account wipe. Order matters — several
// FKs in schema.prisma are `onDelete: Restrict` (Message.senderDevice,
// Attachment.uploaderDevice, CallRecord.initiatorDevice,
// DeviceTransferSession.oldDevice, GroupMeta.createdBy, ChannelMeta.createdBy),
// so we must remove those rows before deleting the devices or the user they
// point at. Product intent: when a user deletes their account, their outbound
// messages and any conversations they created go too — this is a
// privacy-first messenger and sender→user linkage is still identifying
// metadata even when content is E2E encrypted.
//
// Earlier implementation wrapped the entire cascade in a single transaction.
// For an account with hundreds of thousands of messages that produced lock
// storms and could blow past statement_timeout. We now revoke auth in a small
// initial transaction, run the bulky deletes outside any transaction (so
// Postgres can release locks between batches and so a partial failure can be
// resumed), and only put the small final user/device cleanup back inside a
// transaction. That final transaction also quarantines the handle, so it is
// never free for someone else to register in between.
//
// Failures are logged with the step, the error class and the Prisma code,
// never the user id or the error message (Prisma messages can quote query
// arguments): a log line must not outlive the account it is about. The
// rethrown error reaches ApiExceptionFilter, which logs it against the request,
// and operators find unfinished deletions by users.status = 'revoked'.
@Injectable()
export class AccountService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
    @Inject(ATTACHMENT_STORAGE_GATEWAY)
    private readonly storageGateway: AttachmentStorageGateway,
    private readonly retiredHandles: RetiredHandlesService,
    private readonly logger: AppLoggerService,
  ) {}

  async deleteAccount(userId: string): Promise<{ deleted: true }> {
    // Phase 1 (small tx): immediately revoke auth so any in-flight tokens
    // can't be reused and no new sessions can come in mid-cascade.
    const { handle } = await this.prisma.$transaction(async (tx) => {
      const revoked = await tx.user.update({
        where: { id: userId },
        data: { status: 'revoked', activeDeviceId: null },
        select: { handle: true },
      });
      await tx.device.updateMany({
        where: { userId },
        data: { isActive: false },
      });
      return revoked;
    });

    // Cut any live realtime channels now — the handshake check refuses new
    // connections for a non-active user, but an already-open socket would
    // otherwise linger until its own disconnect.
    this.realtimeGateway.disconnectUser(userId);

    const deviceIds = (
      await this.prisma.device.findMany({ where: { userId }, select: { id: true } })
    ).map((d) => d.id);

    const ownedGroupConvIds = (
      await this.prisma.groupMeta.findMany({
        where: { createdByUserId: userId },
        select: { conversationId: true },
      })
    ).map((m) => m.conversationId);
    const ownedChannelConvIds = (
      await this.prisma.channelMeta.findMany({
        where: { createdByUserId: userId },
        select: { conversationId: true },
      })
    ).map((m) => m.conversationId);
    const ownedConversationIds = [...ownedGroupConvIds, ...ownedChannelConvIds];

    // Blobs first: once the attachment rows are gone nothing points at the
    // ciphertext any more, and it would stay in object storage forever.
    await this.deleteUploadedBlobs(deviceIds);

    // Phase 2 (no enclosing tx): each deleteMany is its own statement.
    // Each step is *idempotent* — running them twice is a no-op — so
    // partial failure is recoverable: the user is already locked out by
    // Phase 1, and a later retry of deleteAccount picks up wherever this
    // run stopped. Errors are collected per chunk so a single transient
    // failure doesn't mask the rest.
    const phase2Errors: Array<{ label: string; error: unknown }> = [];
    const tryStep = async (label: string, fn: () => Promise<{ count: number }>) => {
      try {
        await fn();
      } catch (error) {
        this.logger.warn('account.delete.step_failed', {
          step: label,
          error: describeFailure(error),
        });
        phase2Errors.push({ label, error });
      }
    };

    for (const deviceId of deviceIds) {
      await tryStep('messages', () =>
        this.prisma.message.deleteMany({ where: { senderDeviceId: deviceId } }),
      );
      await tryStep('attachments', () =>
        this.prisma.attachment.deleteMany({ where: { uploaderDeviceId: deviceId } }),
      );
      await tryStep('callRecords', () =>
        this.prisma.callRecord.deleteMany({ where: { initiatorDeviceId: deviceId } }),
      );
    }

    await tryStep('messageReceipts', () =>
      this.prisma.messageReceipt.deleteMany({ where: { userId } }),
    );
    await tryStep('storyViews', () =>
      this.prisma.storyView.deleteMany({ where: { viewerUserId: userId } }),
    );
    await tryStep('stories', () => this.prisma.story.deleteMany({ where: { userId } }));
    await tryStep('userContacts', () =>
      this.prisma.userContact.deleteMany({
        where: { OR: [{ userId }, { contactUserId: userId }] },
      }),
    );
    // Direct memberships stay until Phase 3, which needs them to find the
    // user's direct conversations (see releaseDirectConversations).
    await tryStep('conversationMembers', () =>
      this.prisma.conversationMember.deleteMany({
        where: { userId, conversation: { type: { not: 'direct' } } },
      }),
    );

    if (ownedConversationIds.length > 0) {
      // Cascade-delete is bounded by the number of group/channel
      // conversations the user owns — typically small.
      await tryStep('ownedConversations', () =>
        this.prisma.conversation.deleteMany({
          where: { id: { in: ownedConversationIds } },
        }),
      );
    }

    if (phase2Errors.length > 0) {
      // The user is already locked out by Phase 1, but we couldn't fully
      // purge their data. Surface this loudly so an operator can retry —
      // every step is idempotent so re-running deleteAccount picks up
      // exactly where this attempt stopped.
      const [first] = phase2Errors;
      this.logger.error('account.delete.incomplete', {
        failedSteps: phase2Errors.map((failure) => failure.label),
        firstFailure: { step: first.label, error: describeFailure(first.error) },
      });
      throw first.error;
    }

    // Phase 3 (small tx): finish the metadata + the user/device rows
    // themselves. By now everything restricting them is gone. The handle is
    // quarantined in the same transaction that frees it.
    await this.prisma.$transaction(async (tx) => {
      if (deviceIds.length > 0) {
        await tx.deviceTransferSession.deleteMany({
          where: {
            OR: [{ userId }, { oldDeviceId: { in: deviceIds } }],
          },
        });
      } else {
        await tx.deviceTransferSession.deleteMany({ where: { userId } });
      }
      await this.releaseDirectConversations(tx, userId);
      await tx.user.update({
        where: { id: userId },
        data: { activeDeviceId: null },
      });
      await tx.device.deleteMany({ where: { userId } });
      await this.retiredHandles.retire(tx, handle);
      await tx.user.delete({ where: { id: userId } });
    });

    return { deleted: true };
  }

  // A direct conversation's dedupe key is its two members' ids
  // (ConversationsService.createDirect), and nothing cascades it from the user
  // row, so it would name the deleted account next to the peer forever. No one
  // can open a direct conversation with a deleted account again, so the key
  // has nothing left to dedupe: it is cleared, and a conversation this leaves
  // with no members at all is deleted. Runs in Phase 3 so a retry after a
  // partial failure still finds the conversations through the memberships.
  // The keys are searched as well, so a retry also releases a key whose
  // membership is already gone (a deletion that failed under a release whose
  // Phase 2 deleted direct memberships too). An id holds no '|', so `<id>|`
  // at the start or `|<id>` at the end names this account and no other. No
  // index serves the `|<id>` suffix, so this scans conversations once per
  // account deletion.
  private async releaseDirectConversations(
    tx: Prisma.TransactionClient,
    userId: string,
  ): Promise<void> {
    const viaMembership = await tx.conversationMember.findMany({
      where: { userId, conversation: { type: 'direct' } },
      select: { conversationId: true },
    });
    const viaKey = await tx.conversation.findMany({
      where: {
        type: 'direct',
        OR: [
          { directKey: { startsWith: `${userId}|` } },
          { directKey: { endsWith: `|${userId}` } },
        ],
      },
      select: { id: true },
    });
    const conversationIds = [
      ...new Set([
        ...viaMembership.map((membership) => membership.conversationId),
        ...viaKey.map((conversation) => conversation.id),
      ]),
    ];
    if (conversationIds.length === 0) {
      return;
    }
    await tx.conversation.updateMany({
      where: { id: { in: conversationIds } },
      data: { directKey: null },
    });
    await tx.conversationMember.deleteMany({
      where: { userId, conversationId: { in: conversationIds } },
    });
    await tx.conversation.deleteMany({
      where: { id: { in: conversationIds }, members: { none: {} } },
    });
  }

  // Best effort: a blob that fails to delete must not block the erasure of
  // everything else, so failures are counted rather than thrown.
  private async deleteUploadedBlobs(deviceIds: string[]): Promise<void> {
    if (deviceIds.length === 0) {
      return;
    }
    const attachments = await this.prisma.attachment.findMany({
      where: { uploaderDeviceId: { in: deviceIds } },
      select: { storageKey: true },
    });

    let failed = 0;
    for (const { storageKey } of attachments) {
      try {
        await this.storageGateway.deleteObject(storageKey);
      } catch {
        failed += 1;
      }
    }
    if (attachments.length > 0) {
      this.logger.info('account.delete.blobs', {
        deleted: attachments.length - failed,
        total: attachments.length,
      });
    }
  }
}

// What a log line may say about a failure: its class and, for Prisma errors,
// the error code, in the shape ApiExceptionFilter logs them.
const describeFailure = (error: unknown): { name: string; code: unknown } =>
  error instanceof Error
    ? { name: error.name, code: (error as { code?: unknown }).code ?? null }
    : { name: 'unknown', code: null };
