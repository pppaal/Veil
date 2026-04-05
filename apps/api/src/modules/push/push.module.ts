import { Module } from '@nestjs/common';

import { AppConfigService } from '../../common/config/app-config.service';
import {
  MetadataOnlySeamPushProvider,
  NoopPushProvider,
  PUSH_PROVIDER,
  PushService,
} from './push.service';
import type { PushProvider } from './push.types';

@Module({
  providers: [
    {
      provide: PUSH_PROVIDER,
      inject: [AppConfigService],
      useFactory: (config: AppConfigService): PushProvider => {
        switch (config.pushProvider) {
          case 'apns':
          case 'fcm':
            return new MetadataOnlySeamPushProvider(config.pushProvider);
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
