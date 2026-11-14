import { createHmac } from 'node:crypto';

import { Injectable } from '@nestjs/common';
import type { Prisma } from '@prisma/client';

import { AppConfigService } from '../../common/config/app-config.service';
import { PrismaService } from '../../common/prisma.service';

// Long enough for contacts to notice that an account is gone before anyone
// else can take its handle.
const HANDLE_QUARANTINE_DAYS = 90;
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Keeps deleted accounts' handles reserved. Contacts pin identities by
 * handle, so a re-registered @alice would otherwise look like Alice's first
 * use of a new device. The table holds only a peppered HMAC of each handle,
 * so it does not list which accounts existed.
 */
@Injectable()
export class RetiredHandlesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: AppConfigService,
  ) {}

  async isQuarantined(handle: string, now = new Date()): Promise<boolean> {
    const retired = await this.prisma.retiredHandle.findUnique({
      where: { handleHmac: this.digest(handle) },
      select: { retiredUntil: true },
    });
    return retired !== null && retired.retiredUntil > now;
  }

  /**
   * Reserves the handle. Callers run this in the transaction that deletes the
   * user row, so the handle is never free in between.
   */
  async retire(
    tx: Pick<Prisma.TransactionClient, 'retiredHandle'>,
    handle: string,
    now = new Date(),
  ): Promise<void> {
    const handleHmac = this.digest(handle);
    const retiredUntil = new Date(now.getTime() + HANDLE_QUARANTINE_DAYS * DAY_MS);
    await tx.retiredHandle.upsert({
      where: { handleHmac },
      update: { retiredUntil },
      create: { handleHmac, retiredUntil },
    });
  }

  private digest(handle: string): string {
    return createHmac('sha256', this.config.retiredHandlePepper)
      .update(handle.toLowerCase())
      .digest('hex');
  }
}
