import { Module } from '@nestjs/common';

import { AttachmentsModule } from '../attachments/attachments.module';
import { RetentionService } from './retention.service';

// PrismaService, AppConfigService, and AppLoggerService are provided globally
// by CoreModule; the attachment storage gateway comes from AttachmentsModule.
@Module({
  imports: [AttachmentsModule],
  providers: [RetentionService],
  exports: [RetentionService],
})
export class RetentionModule {}
