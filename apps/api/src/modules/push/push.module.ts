import { Module } from '@nestjs/common';

import { AppConfigService } from '../../common/config/app-config.service';
import { ApnsMetadataPushProvider } from './apns-push.provider';
import { FcmMetadataPushProvider } from './fcm-push.provider';
import { NoopPushProvider, PUSH_PROVIDER, PushService } from './push.service';
import { UnifiedPushProvider } from './unifiedpush-push.provider';
import type { PushProvider } from './push.types';

@Module({
  providers: [
    {
      provide: PUSH_PROVIDER,
      inject: [AppConfigService],
      useFactory: (config: AppConfigService): PushProvider => {
        switch (config.pushProvider) {
          case 'apns':
            return new ApnsMetadataPushProvider(config);
          case 'fcm':
            return new FcmMetadataPushProvider(config);
          case 'unifiedpush':
            return new UnifiedPushProvider(config);
          case 'none':
          default:
            return new NoopPushProvider();
        }
      },
    },
    PushService,
  ],
  exports: [PushService],
})
export class PushModule {}
