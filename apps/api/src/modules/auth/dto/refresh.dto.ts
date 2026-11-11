import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';

import type { AuthRefreshRequest } from '@veil/contracts';

export class RefreshDto implements AuthRefreshRequest {
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  refreshToken!: string;
}
