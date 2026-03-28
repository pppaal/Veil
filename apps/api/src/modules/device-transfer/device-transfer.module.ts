import { Module } from '@nestjs/common';

import { DeviceTransferController } from './device-transfer.controller';
import { DeviceTransferService } from './device-transfer.service';

@Module({
  controllers: [DeviceTransferController],
  providers: [DeviceTransferService],
})
export class DeviceTransferModule {}
