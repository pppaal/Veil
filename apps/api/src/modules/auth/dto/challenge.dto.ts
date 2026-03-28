import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsUUID, Length, Matches } from 'class-validator';

import type { AuthChallengeRequest, AuthVerifyRequest } from '@veil/contracts';

export class ChallengeDto implements AuthChallengeRequest {
  @ApiProperty()
  @IsString()
  @Length(3, 32)
  @Matches(/^[a-z0-9._]+$/)
  handle!: string;

  @ApiProperty()
  @IsUUID()
  deviceId!: string;
}

export class VerifyDto implements AuthVerifyRequest {
  @ApiProperty()
  @IsUUID()
  challengeId!: string;

  @ApiProperty()
  @IsUUID()
  deviceId!: string;

  @ApiProperty()
  @IsString()
  signature!: string;
}
