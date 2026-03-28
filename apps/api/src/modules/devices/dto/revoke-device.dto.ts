import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';

import type { RevokeDeviceRequest } from '@veil/contracts';

export class RevokeDeviceDto implements RevokeDeviceRequest {
  @ApiProperty()
  @IsUUID()
  deviceId!: string;
}
