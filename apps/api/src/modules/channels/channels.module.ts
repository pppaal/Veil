import { Module } from '@nestjs/common';

import { ConversationAccessModule } from '../../common/conversation-access/conversation-access.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { ChannelsController } from './channels.controller';
import { ChannelsService } from './channels.service';

@Module({
  imports: [ConversationAccessModule, RealtimeModule],
  controllers: [ChannelsController],
  providers: [ChannelsService],
  exports: [ChannelsService],
})
export class ChannelsModule {}
