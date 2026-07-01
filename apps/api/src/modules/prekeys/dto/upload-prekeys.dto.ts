import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

// A device replenishes its pool in batches. 100 per call bounds the write and
// a healthy client keeps ~100 outstanding, topping up when the count drops.
export const MAX_PREKEYS_PER_UPLOAD = 100;
// Signed base64 X25519 public keys are ~44 chars; allow generous slack for
// wrapping/format markers without letting the column be abused as blob storage.
export const MAX_PREKEY_PUBLIC_KEY_LENGTH = 512;

class OneTimePrekeyDto {
  @ApiProperty({ description: 'Client-assigned prekey id, unique within the device.' })
  @IsInt()
  @Min(0)
  @Max(0x7fffffff)
  keyId!: number;

  @ApiProperty({ description: 'Public prekey (server never sees the private half).' })
  @IsString()
  @Matches(/^[A-Za-z0-9._:+/=-]+$/)
  @MaxLength(MAX_PREKEY_PUBLIC_KEY_LENGTH)
  publicKey!: string;
}

export class UploadPrekeysDto {
  @ApiProperty({ type: [OneTimePrekeyDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_PREKEYS_PER_UPLOAD)
  @ValidateNested({ each: true })
  @Type(() => OneTimePrekeyDto)
  prekeys!: OneTimePrekeyDto[];
}
