import { Module } from '@nestjs/common';

import { ConversationAccessModule } from '../../common/conversation-access/conversation-access.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { SafetyModule } from '../safety/safety.module';
import { ConversationsController } from './conversations.controller';
import { ConversationsService } from './conversations.service';

@Module({
  imports: [ConversationAccessModule, RealtimeModule, SafetyModule],
  controllers: [ConversationsController],
  providers: [ConversationsService],
  exports: [ConversationsService],
})
export class ConversationsModule {}
