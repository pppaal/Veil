import { Module } from '@nestjs/common';

import { SafetyModule } from '../../modules/safety/safety.module';
import { ConversationAccessService } from './conversation-access.service';

@Module({
  imports: [SafetyModule],
  providers: [ConversationAccessService],
  exports: [ConversationAccessService],
})
export class ConversationAccessModule {}
