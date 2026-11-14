import { Module } from '@nestjs/common';

import { AttachmentsModule } from '../attachments/attachments.module';
import { AuthModule } from '../auth/auth.module';
import { HandlesModule } from '../handles/handles.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { AccountDeletionResumer } from './account-deletion-resumer';
import { AccountController } from './account.controller';
import { AccountService } from './account.service';

@Module({
  imports: [AttachmentsModule, AuthModule, HandlesModule, RealtimeModule],
  controllers: [AccountController],
  providers: [AccountService, AccountDeletionResumer],
})
export class AccountModule {}
