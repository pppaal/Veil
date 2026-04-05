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

export class MetadataOnlySeamPushProvider implements PushProvider {
  constructor(readonly kind: 'apns' | 'fcm') {}

  async sendMessageHint(
    pushToken: string,
    hint: MessagePushHint,
  ): Promise<void> {
    void pushToken;
    void hint;
    // Intentionally metadata-only. Real APNs/FCM integration belongs behind this seam.
    // This provider exists to preserve the boundary and release wiring without
    // claiming that a real provider has been privacy-reviewed or production-hardened.
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
    await this.provider.sendMessageHint(pushToken, hint);
  }
}
