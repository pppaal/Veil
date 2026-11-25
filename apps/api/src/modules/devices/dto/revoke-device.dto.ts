import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';

import type { RevokeDeviceRequest } from '@veil/contracts';

import { DeviceStepUpDto } from '../../auth/dto/device-step-up.dto';

export class RevokeDeviceDto extends DeviceStepUpDto implements RevokeDeviceRequest {
  @ApiProperty()
  @IsUUID()
  deviceId!: string;
}
