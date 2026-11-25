import { Module } from '@nestjs/common';

import { RealtimeModule } from '../realtime/realtime.module';
import { SafetyModule } from '../safety/safety.module';
import { StoriesController } from './stories.controller';
import { StoriesService } from './stories.service';

@Module({
  imports: [RealtimeModule, SafetyModule],
  controllers: [StoriesController],
  providers: [StoriesService],
  exports: [StoriesService],
})
export class StoriesModule {}
