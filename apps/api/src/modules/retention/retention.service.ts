import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';

import { AppConfigService } from '../../common/config/app-config.service';
import { AppLoggerService } from '../../common/logger/app-logger.service';
import { PrismaService } from '../../common/prisma.service';

// Server-side metadata retention sweep.
//
// VEIL's threat model promises the server keeps as little as possible. Message
// bodies are ciphertext and the disappearing-message sweep already hard-deletes
// expired messages, but some operational metadata otherwise lives forever.
// This service bounds it. The first slice: terminal call records (who called
// whom, when, how long) — pure history the server has no reason to keep past a
// retention window. Clients keep their own call log locally.
//
// Deliberately NOT swept here (each needs its own careful, delivery-aware
// change): the absolute message-age cap (offline-device delivery window) and
// read-receipt pruning (read-state UX). Tracked as follow-ups.
@Injectable()
export class RetentionService implements OnModuleInit, OnModuleDestroy {
  // Same cadence as the disappearing-message sweep — frequent enough to keep
  // the window tight, sparse enough to not saturate the primary with deletes.
  private static readonly SWEEP_INTERVAL_MS = 10 * 60 * 1000;

  // Only records in a finished state are eligible. An in-flight call
  // (ringing/active) must never be deleted out from under the participants.
  private static readonly TERMINAL_CALL_STATUSES = ['ended', 'missed', 'declined'] as const;

  private timer: NodeJS.Timeout | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: AppConfigService,
    private readonly logger: AppLoggerService,
  ) {}

  onModuleInit(): void {
    // One catch-up sweep shortly after boot, then the periodic cadence.
    // unref() so neither timer keeps the event loop alive during shutdown.
    setTimeout(() => void this.sweep(), 7_000).unref();
    this.timer = setInterval(() => void this.sweep(), RetentionService.SWEEP_INTERVAL_MS);
    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  async sweep(): Promise<void> {
    await this.pruneTerminalCallRecords();
  }

  private async pruneTerminalCallRecords(): Promise<void> {
    const days = this.config.callRecordRetentionDays;
    if (days <= 0) {
      return; // Retention disabled — keep indefinitely.
    }

    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    try {
      const { count } = await this.prisma.callRecord.deleteMany({
        where: {
          startedAt: { lt: cutoff },
          status: { in: [...RetentionService.TERMINAL_CALL_STATUSES] },
        },
      });
      if (count > 0) {
        // Count only — no conversation/device ids, to avoid logging the very
        // metadata we are deleting.
        this.logger.info('retention.call_records_pruned', { count, retentionDays: days });
      }
    } catch (error) {
      // Best-effort: the next interval retries. Never throw from a timer.
      this.logger.warn('retention.call_records_sweep_failed', {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
}
