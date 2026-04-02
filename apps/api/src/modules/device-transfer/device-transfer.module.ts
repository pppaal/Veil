import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { DeviceTransferController } from './device-transfer.controller';
import { DeviceTransferService } from './device-transfer.service';

@Module({
  imports: [AuthModule, RealtimeModule],
  controllers: [DeviceTransferController],
  providers: [DeviceTransferService],
})
export class DeviceTransferModule {}
