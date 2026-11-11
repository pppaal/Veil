import { Inject, Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma, type CallStatus } from '@prisma/client';

import { AppConfigService } from '../../common/config/app-config.service';
import { AppLoggerService } from '../../common/logger/app-logger.service';
import { PrismaService } from '../../common/prisma.service';
import {
  ATTACHMENT_STORAGE_GATEWAY,
  type AttachmentStorageGateway,
} from '../attachments/attachment-storage.gateway';

// The privacy policy promises ciphertext is purged after at most 30 days,
// delivered or not, whatever the disappearing timer says.
export const MESSAGE_MAX_AGE_DAYS = 30;

const DAY_MS = 24 * 60 * 60 * 1000;
const SWEEP_INTERVAL_MS = 10 * 60 * 1000;
const BOOT_SWEEP_DELAY_MS = 7_000;

// Bounded batches keep each transaction short and the primary responsive;
// whatever is left over is picked up on the next tick.
const BATCH_SIZE = 1000;
const MAX_BATCHES_PER_SWEEP = 20;
// Attachment batches call object storage inside the transaction, which can
// outlast Prisma's 5 s default sized for request paths.
const BATCH_TRANSACTION_TIMEOUT_MS = 60_000;

const RINGING_TIMEOUT_MS = 90 * 1000;
const ACTIVE_CALL_MAX_MS = 12 * 60 * 60 * 1000;
const READ_RECEIPT_MAX_AGE_DAYS = 7;
const UNREAD_RECEIPT_MAX_AGE_DAYS = 30;
const ABUSE_REPORT_MAX_AGE_DAYS = 90;
const ORPHAN_ATTACHMENT_GRACE_MS = DAY_MS;

// Only finished calls are ever deleted; ringing and active ones are first
// closed by the stale-call sweeps.
const TERMINAL_CALL_STATUSES: CallStatus[] = ['ended', 'missed', 'declined'];

// An attachment nothing visible points at any more: no message, or only
// delete-for-everyone tombstones that no longer show it.
const UNREFERENCED_ATTACHMENT: Prisma.AttachmentWhereInput = {
  messages: { none: { deletedAt: null } },
};

type Tx = Prisma.TransactionClient;

interface BatchOutcome {
  affected: number;
  blobsDeleted?: number;
  full: boolean;
}

interface Sweep {
  /** Key of the sweep's count in the summary log. */
  name: string;
  batch: (tx: Tx) => Promise<BatchOutcome>;
}

const EMPTY_BATCH: BatchOutcome = { affected: 0, full: false };

const daysBefore = (now: Date, days: number): Date => new Date(now.getTime() - days * DAY_MS);

/**
 * The single owner of every server-side retention sweep. Each batch runs in
 * its own transaction behind a transaction-scoped advisory lock, so only one
 * API instance sweeps at a time and the lock is released with the
 * transaction even behind a connection pooler. Logs carry counts only, never
 * ids, so the sweep does not record the metadata it deletes.
 */
@Injectable()
export class RetentionService implements OnModuleInit, OnModuleDestroy {
  private timer: NodeJS.Timeout | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: AppConfigService,
    private readonly logger: AppLoggerService,
    @Inject(ATTACHMENT_STORAGE_GATEWAY)
    private readonly storageGateway: AttachmentStorageGateway,
  ) {}

  onModuleInit(): void {
    // One catch-up sweep shortly after boot, then the periodic cadence.
    // unref() so neither timer keeps the event loop alive during shutdown.
    setTimeout(() => void this.sweep(), BOOT_SWEEP_DELAY_MS).unref();
    this.timer = setInterval(() => void this.sweep(), SWEEP_INTERVAL_MS);
    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  /** One tick. Never throws: a failed sweep is logged and retried next tick. */
  async sweep(): Promise<void> {
    const counts: Record<string, number> = { attachmentBlobs: 0 };
    for (const sweep of this.sweeps(new Date())) {
      try {
        const result = await this.runSweep(sweep);
        counts[sweep.name] = result.affected;
        counts.attachmentBlobs += result.blobsDeleted;
        if (result.lockHeld) {
          // Another instance is sweeping; it will finish the work.
          this.logger.info('retention.lock_held');
          break;
        }
      } catch (error) {
        this.logger.warn('retention.sweep_failed', { sweep: sweep.name, error: errorKind(error) });
      }
    }

    if (Object.values(counts).some((count) => count > 0)) {
      this.logger.info('retention.swept', counts);
    }
  }

  private async runSweep(
    sweep: Sweep,
  ): Promise<{ affected: number; blobsDeleted: number; lockHeld: boolean }> {
    let affected = 0;
    let blobsDeleted = 0;
    for (let batch = 0; batch < MAX_BATCHES_PER_SWEEP; batch += 1) {
      const outcome = await this.prisma.$transaction(
        async (tx) => ((await this.tryRetentionLock(tx)) ? sweep.batch(tx) : null),
        { timeout: BATCH_TRANSACTION_TIMEOUT_MS },
      );
      if (!outcome) {
        return { affected, blobsDeleted, lockHeld: true };
      }
      affected += outcome.affected;
      blobsDeleted += outcome.blobsDeleted ?? 0;
      // Stop on a short batch, or when a full batch changed nothing (rows whose
      // blob delete keeps failing) so the sweep does not spin on them.
      if (!outcome.full || outcome.affected === 0) {
        break;
      }
    }
    return { affected, blobsDeleted, lockHeld: false };
  }

  private async tryRetentionLock(tx: Tx): Promise<boolean> {
    const [row] = await tx.$queryRaw<Array<{ acquired: boolean }>>`
      SELECT pg_try_advisory_xact_lock(hashtext('veil-retention')) AS acquired
    `;
    return row?.acquired === true;
  }

  private sweeps(now: Date): Sweep[] {
    const sweeps: Sweep[] = [
      {
        name: 'expiredMessages',
        batch: (tx) => this.deleteMessages(tx, { expiresAt: { lte: now } }),
      },
      {
        name: 'agedMessages',
        batch: (tx) =>
          this.deleteMessages(tx, {
            serverReceivedAt: { lt: daysBefore(now, MESSAGE_MAX_AGE_DAYS) },
          }),
      },
      { name: 'expiredStories', batch: (tx) => this.deleteExpiredStories(tx, now) },
      {
        name: 'missedCalls',
        batch: (tx) =>
          this.closeStaleCalls(tx, now, {
            from: 'ringing',
            to: 'missed',
            startedBefore: new Date(now.getTime() - RINGING_TIMEOUT_MS),
          }),
      },
      {
        name: 'endedCalls',
        batch: (tx) =>
          this.closeStaleCalls(tx, now, {
            from: 'active',
            to: 'ended',
            startedBefore: new Date(now.getTime() - ACTIVE_CALL_MAX_MS),
          }),
      },
    ];

    if (this.config.callRecordRetentionDays > 0) {
      const cutoff = daysBefore(now, this.config.callRecordRetentionDays);
      sweeps.push({ name: 'callRecords', batch: (tx) => this.deleteTerminalCalls(tx, cutoff) });
    }

    sweeps.push(
      { name: 'receipts', batch: (tx) => this.deleteStaleReceipts(tx, now) },
      { name: 'abuseReports', batch: (tx) => this.deleteOldAbuseReports(tx, now) },
      { name: 'orphanAttachments', batch: (tx) => this.deleteOrphanAttachments(tx, now) },
    );

    if (this.config.prekeyConsumedRetentionDays > 0) {
      const cutoff = daysBefore(now, this.config.prekeyConsumedRetentionDays);
      sweeps.push({
        name: 'consumedPrekeys',
        batch: (tx) => this.deleteConsumedPrekeys(tx, cutoff),
      });
    }

    sweeps.push({ name: 'secretBlobs', batch: (tx) => this.deleteExpiredSecretBlobs(tx, now) });
    return sweeps;
  }

  // @retention-sweep Message
  // Expired and over-age messages. Their attachments go in the same batch once
  // nothing visible references them, so blobs never outlive their messages.
  private async deleteMessages(tx: Tx, where: Prisma.MessageWhereInput): Promise<BatchOutcome> {
    const messages = await tx.message.findMany({
      where,
      select: { id: true, attachmentId: true },
      take: BATCH_SIZE,
    });
    if (messages.length === 0) {
      return EMPTY_BATCH;
    }

    await tx.message.deleteMany({ where: { id: { in: messages.map((message) => message.id) } } });

    const attachmentIds = [
      ...new Set(
        messages
          .map((message) => message.attachmentId)
          .filter((attachmentId): attachmentId is string => attachmentId !== null),
      ),
    ];
    const blobsDeleted =
      attachmentIds.length === 0
        ? 0
        : await this.deleteAttachments(
            tx,
            await tx.attachment.findMany({
              where: { id: { in: attachmentIds }, ...UNREFERENCED_ATTACHMENT },
              select: { id: true, storageKey: true },
            }),
          );

    return { affected: messages.length, blobsDeleted, full: messages.length === BATCH_SIZE };
  }

  // @retention-sweep Story
  // @retention-sweep StoryView
  // Stories live 24 hours; their who-viewed-whom rows go with them.
  private async deleteExpiredStories(tx: Tx, now: Date): Promise<BatchOutcome> {
    const stories = await tx.story.findMany({
      where: { expiresAt: { lte: now } },
      select: { id: true },
      take: BATCH_SIZE,
    });
    if (stories.length === 0) {
      return EMPTY_BATCH;
    }

    const storyIds = stories.map((story) => story.id);
    await tx.storyView.deleteMany({ where: { storyId: { in: storyIds } } });
    const { count } = await tx.story.deleteMany({ where: { id: { in: storyIds } } });
    return { affected: count, full: stories.length === BATCH_SIZE };
  }

  // @retention-sweep CallRecord
  // A crash or dropped connection leaves calls ringing or active forever;
  // closing them makes them terminal and therefore prunable.
  private async closeStaleCalls(
    tx: Tx,
    now: Date,
    transition: { from: CallStatus; to: CallStatus; startedBefore: Date },
  ): Promise<BatchOutcome> {
    const calls = await tx.callRecord.findMany({
      where: { status: transition.from, startedAt: { lt: transition.startedBefore } },
      select: { id: true },
      take: BATCH_SIZE,
    });
    if (calls.length === 0) {
      return EMPTY_BATCH;
    }

    const { count } = await tx.callRecord.updateMany({
      where: { id: { in: calls.map((call) => call.id) }, status: transition.from },
      data: { status: transition.to, endedAt: now },
    });
    return { affected: count, full: calls.length === BATCH_SIZE };
  }

  // @retention-sweep CallRecord
  // Who called whom is history the server has no reason to keep; clients keep
  // their own call log.
  private async deleteTerminalCalls(tx: Tx, cutoff: Date): Promise<BatchOutcome> {
    const calls = await tx.callRecord.findMany({
      where: { startedAt: { lt: cutoff }, status: { in: TERMINAL_CALL_STATUSES } },
      select: { id: true },
      take: BATCH_SIZE,
    });
    if (calls.length === 0) {
      return EMPTY_BATCH;
    }

    const { count } = await tx.callRecord.deleteMany({
      where: { id: { in: calls.map((call) => call.id) } },
    });
    return { affected: count, full: calls.length === BATCH_SIZE };
  }

  // @retention-sweep MessageReceipt
  // Per-recipient delivered/read timestamps are an activity timeline. Read
  // receipts have done their job after a week; unread ones are kept as long as
  // the message itself could still be delivered.
  private async deleteStaleReceipts(tx: Tx, now: Date): Promise<BatchOutcome> {
    const receipts = await tx.messageReceipt.findMany({
      where: {
        OR: [
          { readAt: { lt: daysBefore(now, READ_RECEIPT_MAX_AGE_DAYS) } },
          { readAt: null, deliveredAt: { lt: daysBefore(now, UNREAD_RECEIPT_MAX_AGE_DAYS) } },
        ],
      },
      select: { id: true },
      take: BATCH_SIZE,
    });
    if (receipts.length === 0) {
      return EMPTY_BATCH;
    }

    const { count } = await tx.messageReceipt.deleteMany({
      where: { id: { in: receipts.map((receipt) => receipt.id) } },
    });
    return { affected: count, full: receipts.length === BATCH_SIZE };
  }

  // @retention-sweep AbuseReport
  private async deleteOldAbuseReports(tx: Tx, now: Date): Promise<BatchOutcome> {
    const reports = await tx.abuseReport.findMany({
      where: { createdAt: { lt: daysBefore(now, ABUSE_REPORT_MAX_AGE_DAYS) } },
      select: { id: true },
      take: BATCH_SIZE,
    });
    if (reports.length === 0) {
      return EMPTY_BATCH;
    }

    const { count } = await tx.abuseReport.deleteMany({
      where: { id: { in: reports.map((report) => report.id) } },
    });
    return { affected: count, full: reports.length === BATCH_SIZE };
  }

  // @retention-sweep Attachment
  // Abandoned uploads (pending or failed) and blobs no visible message
  // references, after a grace period that covers a slow upload-then-send.
  private async deleteOrphanAttachments(tx: Tx, now: Date): Promise<BatchOutcome> {
    const orphans = await tx.attachment.findMany({
      where: {
        createdAt: { lt: new Date(now.getTime() - ORPHAN_ATTACHMENT_GRACE_MS) },
        ...UNREFERENCED_ATTACHMENT,
      },
      select: { id: true, storageKey: true },
      take: BATCH_SIZE,
    });
    if (orphans.length === 0) {
      return EMPTY_BATCH;
    }

    const deleted = await this.deleteAttachments(tx, orphans);
    return { affected: deleted, blobsDeleted: deleted, full: orphans.length === BATCH_SIZE };
  }

  // @retention-sweep OneTimePrekey
  // Consumed prekeys are kept briefly so a keyId is never reused mid-flight;
  // unconsumed pool entries are never touched here.
  private async deleteConsumedPrekeys(tx: Tx, cutoff: Date): Promise<BatchOutcome> {
    const prekeys = await tx.oneTimePrekey.findMany({
      where: { consumedAt: { not: null, lt: cutoff } },
      select: { id: true },
      take: BATCH_SIZE,
    });
    if (prekeys.length === 0) {
      return EMPTY_BATCH;
    }

    const { count } = await tx.oneTimePrekey.deleteMany({
      where: { id: { in: prekeys.map((prekey) => prekey.id) } },
    });
    return { affected: count, full: prekeys.length === BATCH_SIZE };
  }

  // @retention-sweep SecretBlob
  // One-time links burn on read; this clears the ones nobody ever opened.
  private async deleteExpiredSecretBlobs(tx: Tx, now: Date): Promise<BatchOutcome> {
    const blobs = await tx.secretBlob.findMany({
      where: { expiresAt: { lt: now } },
      select: { id: true },
      take: BATCH_SIZE,
    });
    if (blobs.length === 0) {
      return EMPTY_BATCH;
    }

    const { count } = await tx.secretBlob.deleteMany({
      where: { id: { in: blobs.map((blob) => blob.id) } },
    });
    return { affected: count, full: blobs.length === BATCH_SIZE };
  }

  /**
   * Deletes each blob, then the rows whose blob is gone. A row whose blob
   * delete failed is kept, so the orphan sweep retries it instead of leaving
   * ciphertext in storage with nothing pointing at it.
   */
  private async deleteAttachments(
    tx: Tx,
    attachments: Array<{ id: string; storageKey: string }>,
  ): Promise<number> {
    const released: string[] = [];
    for (const attachment of attachments) {
      try {
        await this.storageGateway.deleteObject(attachment.storageKey);
        released.push(attachment.id);
      } catch {
        // Retried by the orphan sweep on a later tick.
      }
    }
    if (released.length === 0) {
      return 0;
    }

    const { count } = await tx.attachment.deleteMany({
      where: { id: { in: released }, ...UNREFERENCED_ATTACHMENT },
    });
    return count;
  }
}

// Logged instead of the message, which can quote query arguments.
function errorKind(error: unknown): string {
  if (error instanceof Prisma.PrismaClientKnownRequestError) {
    return error.code;
  }
  return error instanceof Error ? error.name : 'unknown';
}
