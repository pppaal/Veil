import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { DevicePlatform } from '@prisma/client';
import { IsEnum, IsOptional, IsString, Length, Matches, MaxLength } from 'class-validator';

import type { RegisterRequest } from '@veil/contracts';

export class RegisterDto implements RegisterRequest {
  // Handles must start and end with a letter/digit and may not contain
  // consecutive separators. Without these guards, "..bob..", "a..b", or a
  // leading/trailing dot let attackers register lookalikes that render as
  // "bob" in most fonts and slip past human review.
  @ApiProperty({ example: 'veil.operator' })
  @IsString()
  @Length(3, 32)
  @Matches(/^[a-z0-9](?!.*[._]{2})[a-z0-9._]*[a-z0-9]$/)
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
  @MaxLength(1024)
  @Matches(/^[A-Za-z0-9_-]+={0,2}$/)
  publicIdentityKey!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(2048)
  @Matches(/^[A-Za-z0-9_-]+={0,2}$/)
  signedPrekeyBundle!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(512)
  @Matches(/^[A-Za-z0-9_-]+$/)
  authPublicKey!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(512)
  pushToken?: string;
}
