import { Module } from '@nestjs/common';

import { AttachmentsModule } from '../attachments/attachments.module';
import { HandlesModule } from '../handles/handles.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { AccountController } from './account.controller';
import { AccountService } from './account.service';

@Module({
  imports: [AttachmentsModule, HandlesModule, RealtimeModule],
  controllers: [AccountController],
  providers: [AccountService],
})
export class AccountModule {}
