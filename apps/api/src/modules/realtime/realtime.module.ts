import { Module } from '@nestjs/common';

import { ConversationAccessModule } from '../../common/conversation-access/conversation-access.module';
import { RealtimeGateway } from './realtime.gateway';

@Module({
  imports: [ConversationAccessModule],
  providers: [RealtimeGateway],
  exports: [RealtimeGateway],
})
export class RealtimeModule {}
