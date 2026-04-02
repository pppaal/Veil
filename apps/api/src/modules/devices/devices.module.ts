import { Module } from '@nestjs/common';

import { RealtimeModule } from '../realtime/realtime.module';
import { DevicesController } from './devices.controller';
import { DevicesService } from './devices.service';

@Module({
  imports: [RealtimeModule],
  controllers: [DevicesController],
  providers: [DevicesService],
  exports: [DevicesService],
})
export class DevicesModule {}
