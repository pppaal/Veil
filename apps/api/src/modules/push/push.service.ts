import { Inject, Injectable } from '@nestjs/common';

import { AppLoggerService } from '../../common/logger/app-logger.service';
import { MetricsService } from '../metrics/metrics.service';
import type { MessagePushHint, PushProvider } from './push.types';

export const PUSH_PROVIDER = Symbol('PUSH_PROVIDER');

export class NoopPushProvider implements PushProvider {
  readonly kind = 'none' as const;

  async sendMessageHint(pushToken: string, hint: MessagePushHint): Promise<void> {
    void pushToken;
    void hint;
  }
}

@Injectable()
export class PushService {
  constructor(
    @Inject(PUSH_PROVIDER) private readonly provider: PushProvider,
    private readonly logger: AppLoggerService,
    private readonly metrics: MetricsService,
  ) {}

  get providerKind(): PushProvider['kind'] {
    return this.provider.kind;
  }

  async sendMessageHint(pushToken: string, hint: MessagePushHint): Promise<void> {
    try {
      await this.provider.sendMessageHint(pushToken, hint);
      this.metrics.pushDeliveryTotal.inc({ provider: this.provider.kind, result: 'success' });
    } catch (error) {
      // Push delivery must never block the message relay path — still swallow.
      // But it must be observable: count it and log a redacted line (the
      // logger redacts pushToken) so silent push outages are diagnosable.
      this.metrics.pushDeliveryTotal.inc({ provider: this.provider.kind, result: 'failure' });
      this.logger.warn('push.delivery_failed', {
        provider: this.provider.kind,
        pushToken,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
}
