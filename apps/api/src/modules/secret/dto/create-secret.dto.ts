import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt, IsNotEmpty, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

// Caps. The server never decrypts this — it is opaque base64 ciphertext —
// but it must bound storage so the endpoint can't be used as a blob host.
export const MAX_CIPHERTEXT_LENGTH = 128 * 1024; // ~128 KB of base64
export const MIN_TTL_SECONDS = 60; // 1 minute
export const MAX_TTL_SECONDS = 7 * 24 * 60 * 60; // 7 days
export const DEFAULT_TTL_SECONDS = 24 * 60 * 60; // 1 day

export class CreateSecretDto {
  @ApiProperty({ description: 'Client-encrypted ciphertext (server never decrypts).' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(MAX_CIPHERTEXT_LENGTH)
  ciphertext!: string;

  @ApiPropertyOptional({ minimum: MIN_TTL_SECONDS, maximum: MAX_TTL_SECONDS })
  @IsOptional()
  @IsInt()
  @Min(MIN_TTL_SECONDS)
  @Max(MAX_TTL_SECONDS)
  ttlSeconds?: number;
}
