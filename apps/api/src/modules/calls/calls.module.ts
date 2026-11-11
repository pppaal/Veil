import { Module } from '@nestjs/common';

import { ConversationAccessModule } from '../../common/conversation-access/conversation-access.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { CallsController } from './calls.controller';
import { CallsService } from './calls.service';

@Module({
  imports: [ConversationAccessModule, RealtimeModule],
  controllers: [CallsController],
  providers: [CallsService],
  exports: [CallsService],
})
export class CallsModule {}
