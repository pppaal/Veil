import { Module } from '@nestjs/common';

import { AttachmentsModule } from '../attachments/attachments.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { AccountController } from './account.controller';
import { AccountService } from './account.service';

@Module({
  imports: [AttachmentsModule, RealtimeModule],
  controllers: [AccountController],
  providers: [AccountService],
})
export class AccountModule {}
