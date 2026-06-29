import { Module } from '@nestjs/common';

import { RetentionService } from './retention.service';

// PrismaService, AppConfigService, and AppLoggerService are provided globally
// by CoreModule, so no imports are needed here.
@Module({
  providers: [RetentionService],
  exports: [RetentionService],
})
export class RetentionModule {}
