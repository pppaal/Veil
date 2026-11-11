import { createHash } from 'node:crypto';

import { Injectable } from '@nestjs/common';

import { EphemeralStoreService } from '../../common/ephemeral-store.service';

export interface DirectoryBudgetRule {
  readonly name: string;
  readonly limit: number;
}

// Every directory budget is a one-hour fixed window.
const BUDGET_WINDOW_SECONDS = 60 * 60;

export const DIRECTORY_BUDGETS = {
  // One requester device draining one target account.
  prekeyClaimsPerRequester: { name: 'opk-claim-requester', limit: 20 },
  // Every requester together draining one target device's pool.
  prekeyClaimsPerTargetDevice: { name: 'opk-claim-device', limit: 50 },
  // Anonymous lookups of the deprecated public key-bundle route.
  publicBundleLookups: { name: 'public-bundle', limit: 20 },
  signedPrekeyRotations: { name: 'spk-rotation', limit: 10 },
} as const satisfies Record<string, DirectoryBudgetRule>;

/**
 * Per-subject hourly budgets for key-directory operations, shared by every
 * route that spends them so an attacker gains nothing by switching routes.
 */
@Injectable()
export class DirectoryBudget {
  constructor(private readonly store: EphemeralStoreService) {}

  /** Spends one unit; false once the subject has exhausted the rule's window. */
  async tryConsume(rule: DirectoryBudgetRule, ...subject: string[]): Promise<boolean> {
    // The subject says who looked up whom; keep only a digest of it in the
    // shared store.
    const digest = createHash('sha256').update(subject.join('\u0000')).digest('base64url');
    const used = await this.store.incrementWithTtl(
      `budget:${rule.name}:${digest}`,
      BUDGET_WINDOW_SECONDS,
    );
    return used <= rule.limit;
  }
}
