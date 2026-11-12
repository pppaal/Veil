import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

import type { DeviceStepUpProof } from '@veil/contracts';

// The step-up proof fields (AuthService.verifyDeviceStepUp), for request
// bodies that carry one. Optional here so a missing proof gets the same 401
// challenge_invalid from verifyDeviceStepUp as an expired one; revoking
// another, non-last device needs none.
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
