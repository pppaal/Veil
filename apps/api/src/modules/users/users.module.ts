import { Module } from '@nestjs/common';

import { PrekeysModule } from '../prekeys/prekeys.module';
import { RequestTracker } from './request-tracker';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  imports: [PrekeysModule],
  controllers: [UsersController],
  providers: [UsersService, RequestTracker],
  exports: [UsersService],
})
export class UsersModule {}
