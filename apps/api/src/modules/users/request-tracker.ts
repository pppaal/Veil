import { Injectable } from '@nestjs/common';
import type { Request } from 'express';

import { CfThrottlerGuard } from '../../common/guards/cf-throttler.guard';

/**
 * Exposes the global throttler's tracker key (the device for authenticated
 * calls, the trusted client IP otherwise) so per-caller budgets bucket callers
 * exactly like the rate limiter does. Extending the guard keeps the client-IP
 * policy in one place instead of re-deriving it from request headers here.
 */
@Injectable()
export class RequestTracker extends CfThrottlerGuard {
  trackerFor(request: Request): Promise<string> {
    return this.getTracker(request);
  }
}
