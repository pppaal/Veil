import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { DevicePlatform } from '@prisma/client';
import { IsEnum, IsOptional, IsString, Length, Matches, MaxLength } from 'class-validator';

import type { RegisterRequest } from '@veil/contracts';

export class RegisterDto implements RegisterRequest {
  @ApiProperty({ example: 'veil.operator' })
  @IsString()
  @Length(3, 32)
  @Matches(/^[a-z0-9._]+$/)
  handle!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  displayName?: string;

  @ApiProperty({ example: 'Pixel 9 Pro' })
  @IsString()
  @MaxLength(80)
  deviceName!: string;

  @ApiProperty({ enum: DevicePlatform })
  @IsEnum(DevicePlatform)
  platform!: DevicePlatform;

  @ApiProperty()
  @IsString()
  publicIdentityKey!: string;

  @ApiProperty()
  @IsString()
  signedPrekeyBundle!: string;

  @ApiProperty()
  @IsString()
  authPublicKey!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  pushToken?: string;
}
