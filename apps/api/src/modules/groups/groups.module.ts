import { Module } from '@nestjs/common';

import { ConversationAccessModule } from '../../common/conversation-access/conversation-access.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { SafetyModule } from '../safety/safety.module';
import { GroupsController } from './groups.controller';
import { GroupsService } from './groups.service';

@Module({
  imports: [ConversationAccessModule, RealtimeModule, SafetyModule],
  controllers: [GroupsController],
  providers: [GroupsService],
  exports: [GroupsService],
})
export class GroupsModule {}
