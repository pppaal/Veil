import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';

import { AccountService } from './account.service';

const RESUME_INTERVAL_MS = 15 * 60 * 1000;
const BOOT_RESUME_DELAY_MS = 60_000;

/**
 * Runs AccountService.resumeUnfinishedDeletions on a timer, so an account
 * deletion that stopped part-way (a failed step, a restart) is finished by
 * the server: the user cannot retry, because the deletion's first step
 * revoked every token and device they had.
 */
@Injectable()
export class AccountDeletionResumer implements OnModuleInit, OnModuleDestroy {
  private timer: NodeJS.Timeout | null = null;
  private running = false;

  constructor(private readonly accounts: AccountService) {}

  onModuleInit(): void {
    // unref() so neither timer keeps the event loop alive during shutdown.
    setTimeout(() => void this.tick(), BOOT_RESUME_DELAY_MS).unref();
    this.timer = setInterval(() => void this.tick(), RESUME_INTERVAL_MS);
    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  /** One pass. Never throws, and never overlaps the previous pass. */
  async tick(): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    try {
      await this.accounts.resumeUnfinishedDeletions();
    } finally {
      this.running = false;
    }
  }
}
