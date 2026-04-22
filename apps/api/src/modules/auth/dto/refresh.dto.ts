import { ApiProperty } from '@nestjs/swagger';
import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

import type { AuthLogoutRequest, AuthRefreshRequest } from '@veil/contracts';

export class RefreshDto implements AuthRefreshRequest {
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  refreshToken!: string;
}

export class LogoutDto implements AuthLogoutRequest {
  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  @MaxLength(256)
  refreshToken?: string;
}
