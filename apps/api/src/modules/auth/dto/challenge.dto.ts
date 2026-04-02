import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsUUID, Length, Matches, MaxLength } from 'class-validator';

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
  @MaxLength(1024)
  @Matches(/^[A-Za-z0-9_-]+$/)
  signature!: string;
}
