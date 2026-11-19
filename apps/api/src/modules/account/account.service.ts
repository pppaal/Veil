import { Inject, Injectable } from '@nestjs/common';
import type { Prisma } from '@prisma/client';

import { AppLoggerService } from '../../common/logger/app-logger.service';
import { describeFailure } from '../../common/logger/describe-failure';
import { PrismaService } from '../../common/prisma.service';
import {
  ATTACHMENT_STORAGE_GATEWAY,
  type AttachmentStorageGateway,
} from '../attachments/attachment-storage.gateway';
import { AuthService } from '../auth/auth.service';
import { RetiredHandlesService } from '../handles/retired-handles.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';

// A deletion still 'revoked' this long after its last attempt began has
// stopped (a failed step, a restart, a crash), and resumeUnfinishedDeletions
// finishes it. Long enough not to race a deletion still running in a request.
export const UNFINISHED_DELETION_GRACE_MS = 60 * 60 * 1000;
const RESUME_BATCH_SIZE = 20;

// Right-to-erasure cascade for a full account wipe. Order matters — several
// FKs in schema.prisma are `onDelete: Restrict` (Message.senderDevice,
// Attachment.uploaderDevice, CallRecord.initiatorDevice,
// DeviceTransferSession.oldDevice, GroupMeta.createdBy, ChannelMeta.createdBy),
// so we must remove those rows before deleting the devices or the user they
// point at. Product intent: when a user deletes their account, their outbound
// messages and the groups and channels they currently own go too — this is a
// privacy-first messenger and sender→user linkage is still identifying
// metadata even when content is E2E encrypted. GroupMeta.createdByUserId
// names a group's current owner (ownership transfer moves it), so a group
// the user handed over survives them.
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
// rethrown error reaches ApiExceptionFilter, which logs it against the request.
// The user cannot retry: Phase 1 has already revoked every token and device.
// So the server finishes unfinished deletions itself: users.status =
// 'revoked' means a deletion in progress, and AccountDeletionResumer calls
// resumeUnfinishedDeletions, which re-runs deleteAccount for any such account
// whose last attempt began more than an hour ago.
@Injectable()
export class AccountService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
    @Inject(ATTACHMENT_STORAGE_GATEWAY)
    private readonly storageGateway: AttachmentStorageGateway,
    private readonly retiredHandles: RetiredHandlesService,
    private readonly logger: AppLoggerService,
    private readonly authService: AuthService,
  ) {}

  async deleteAccount(userId: string): Promise<{ deleted: true }> {
    // Phase 1 (small tx): immediately revoke auth so any in-flight tokens
    // can't be reused and no new sessions can come in mid-cascade.
    // updatedAt marks when this attempt began; resumeUnfinishedDeletions
    // leaves the account alone for an hour after it.
    const { handle } = await this.prisma.$transaction(async (tx) => {
      const revoked = await tx.user.update({
        where: { id: userId },
        data: { status: 'revoked', activeDeviceId: null, updatedAt: new Date() },
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
    // Phase 1, and resumeUnfinishedDeletions later re-runs deleteAccount,
    // which picks up wherever this run stopped. Errors are collected per
    // chunk so a single transient failure doesn't mask the rest.
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
      // The device's sessions in the ephemeral store (refresh families,
      // their tokens, the family index, login challenges) name the user and
      // the device. Phase 1 has revoked the device, so no refresh can write
      // them again.
      await tryStep('refreshSessions', async () => {
        await this.authService.forgetDevice(deviceId);
        return { count: 0 };
      });
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
      // purge their data. Surface this loudly; resumeUnfinishedDeletions
      // retries, and every step is idempotent so re-running deleteAccount
      // picks up exactly where this attempt stopped.
      const [first] = phase2Errors;
      this.logger.error('account.delete.incomplete', {
        failedSteps: phase2Errors.map((failure) => failure.label),
        firstFailure: { step: first.label, error: describeFailure(first.error) },
      });
      throw first.error;
    }

    // Phase 3 (small tx): finish the metadata + the user/device rows
    // themselves. By now everything restricting them is gone. The handle is
    // quarantined in the same transaction that frees it. Direct conversations
    // are released after the user row is deleted (see
    // releaseDirectConversations); their memberships are read before, since
    // deleting the user row cascades them.
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
      const directMemberships = await tx.conversationMember.findMany({
        where: { userId, conversation: { type: 'direct' } },
        select: { conversationId: true },
      });
      // Two runs can reach this point for one account: a deletion still
      // running an hour after Phase 1 is resumed in parallel. The run that
      // gets here second finds no user row left (on Postgres this update waits
      // for the other run's transaction, then matches nothing). The other run
      // has done everything below, so this one is done too, and must not
      // answer an error for a deletion that completed.
      const remaining = await tx.user.updateMany({
        where: { id: userId },
        data: { activeDeviceId: null },
      });
      if (remaining.count === 0) {
        return;
      }
      await tx.device.deleteMany({ where: { userId } });
      await this.retiredHandles.retire(tx, handle);
      await tx.user.delete({ where: { id: userId } });
      await this.releaseDirectConversations(
        tx,
        userId,
        directMemberships.map((membership) => membership.conversationId),
      );
    });

    return { deleted: true };
  }

  /**
   * Finishes deletions that stopped part-way: accounts still 'revoked' more
   * than UNFINISHED_DELETION_GRACE_MS after their last attempt began. Each is
   * claimed by moving its updatedAt forward first, so two API instances never
   * resume the same account at once and a deletion that keeps failing is
   * retried at most once per grace period. Never throws; logs counts and
   * error classes only, never a user id.
   */
  async resumeUnfinishedDeletions(
    now = new Date(),
  ): Promise<{ completed: number; failed: number }> {
    const cutoff = new Date(now.getTime() - UNFINISHED_DELETION_GRACE_MS);
    const outcome = { completed: 0, failed: 0 };
    let candidates: Array<{ id: string }>;
    try {
      candidates = await this.prisma.user.findMany({
        where: { status: 'revoked', updatedAt: { lt: cutoff } },
        select: { id: true },
        orderBy: { updatedAt: 'asc' },
        take: RESUME_BATCH_SIZE,
      });
    } catch (error) {
      this.logger.warn('account.delete.resume_failed', { error: describeFailure(error) });
      return outcome;
    }

    for (const { id } of candidates) {
      try {
        const claimed = await this.prisma.user.updateMany({
          where: { id, status: 'revoked', updatedAt: { lt: cutoff } },
          data: { updatedAt: now },
        });
        if (claimed.count === 0) {
          continue;
        }
        await this.deleteAccount(id);
        outcome.completed += 1;
      } catch (error) {
        outcome.failed += 1;
        this.logger.warn('account.delete.resume_failed', { error: describeFailure(error) });
      }
    }
    if (outcome.completed > 0 || outcome.failed > 0) {
      this.logger.info('account.delete.resumed', outcome);
    }
    return outcome;
  }

  // A direct conversation's dedupe key is its two members' ids
  // (ConversationsService.createDirect), and nothing cascades it from the user
  // row, so it would name the deleted account next to the peer forever. No one
  // can open a direct conversation with a deleted account again, so the key
  // has nothing left to dedupe: it is cleared, and a conversation this leaves
  // with no members at all is deleted.
  //
  // The conversations come from the user's direct memberships, read before
  // the user row was deleted, and from a search of the keys themselves. The
  // key search catches a key whose membership is already gone (a deletion
  // that failed under a release whose Phase 2 deleted direct memberships too).
  // It runs after the user row is deleted so that it also catches a direct
  // conversation opened concurrently by a createDirect that read the account
  // as active before Phase 1: the foreign-key check of that conversation's
  // membership insert holds a lock on the user row until it commits, so the
  // delete waits for it, and the search that follows (a new snapshot under
  // READ COMMITTED) sees it. A membership insert that comes after the delete
  // fails its foreign-key check instead, so no later conversation can name
  // the account. An id holds no '|', so `<id>|` at the start or `|<id>` at the
  // end names this account and no other. No index serves the `|<id>` suffix,
  // so this scans conversations once per account deletion.
  private async releaseDirectConversations(
    tx: Prisma.TransactionClient,
    userId: string,
    viaMembership: string[],
  ): Promise<void> {
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
      ...new Set([...viaMembership, ...viaKey.map((conversation) => conversation.id)]),
    ];
    if (conversationIds.length === 0) {
      return;
    }
    await tx.conversation.updateMany({
      where: { id: { in: conversationIds } },
      data: { directKey: null },
    });
    // Deleting the user row has already cascaded these on Postgres.
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
