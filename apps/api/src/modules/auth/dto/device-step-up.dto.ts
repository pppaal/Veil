import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

import type { DeviceStepUpProof } from '@veil/contracts';

// The step-up proof fields (AuthService.verifyDeviceStepUp), for request
// bodies that carry one.
export class DeviceStepUpDto implements DeviceStepUpProof {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  challengeId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1024)
  signature?: string;
}
