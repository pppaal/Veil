import { Module } from '@nestjs/common';

import { RealtimeModule } from '../realtime/realtime.module';
import { AccountController } from './account.controller';
import { AccountService } from './account.service';

@Module({
  imports: [RealtimeModule],
  controllers: [AccountController],
  providers: [AccountService],
})
export class AccountModule {}
