import { Inject, Injectable } from '@nestjs/common';

import type { MessagePushHint, PushProvider } from './push.types';

export const PUSH_PROVIDER = Symbol('PUSH_PROVIDER');

export class NoopPushProvider implements PushProvider {
  readonly kind = 'none' as const;

  async sendMessageHint(
    pushToken: string,
    hint: MessagePushHint,
  ): Promise<void> {
    void pushToken;
    void hint;
  }
}

@Injectable()
export class PushService {
  constructor(
    @Inject(PUSH_PROVIDER) private readonly provider: PushProvider,
  ) {}

  get providerKind(): PushProvider['kind'] {
    return this.provider.kind;
  }

  async sendMessageHint(
    pushToken: string,
    hint: MessagePushHint,
  ): Promise<void> {
    try {
      await this.provider.sendMessageHint(pushToken, hint);
    } catch {
      // Push delivery must never block the message relay path.
      // Provider-specific failures are handled out-of-band by health/ops review.
    }
  }
}
