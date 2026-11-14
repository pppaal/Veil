import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt, IsNotEmpty, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

// Caps. The server never decrypts this — it is opaque base64 ciphertext —
// but it must bound storage so the endpoint can't be used as a blob host.
export const MAX_CIPHERTEXT_LENGTH = 128 * 1024; // ~128 KB of base64
export const MIN_TTL_SECONDS = 60; // 1 minute
export const MAX_TTL_SECONDS = 7 * 24 * 60 * 60; // 7 days
export const DEFAULT_TTL_SECONDS = 24 * 60 * 60; // 1 day
// What every stored link together may hold. Creating one needs no account,
// so without a relay-wide budget the per-IP limit alone would let one
// address add gigabytes a day to the primary database (more from an IPv6
// prefix, whose addresses each get their own limit).
export const MAX_STORED_SECRETS = 50_000;
export const MAX_STORED_SECRET_BYTES = 256 * 1024 * 1024;
// What one client network (an IPv4 address or an IPv6 /64) may create per UTC
// day, checked before the relay-wide budget, so one client cannot fill that
// budget and lock everyone else out. A link lives at most MAX_TTL_SECONDS, so
// links from at most eight UTC days are alive at once: one network can hold
// at most 8 x 4 MiB = 32 MiB (1/8 of the byte budget) and 1,600 links (about
// 3% of the row budget), plus expired ones the ten-minute sweep has not yet
// removed. Many networks together can still fill the budget; that is the
// accepted cost of a backstop that keeps links from filling the disk.
export const MAX_SECRET_BYTES_PER_CLIENT_DAY = 4 * 1024 * 1024;
export const MAX_SECRETS_PER_CLIENT_DAY = 200;

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
