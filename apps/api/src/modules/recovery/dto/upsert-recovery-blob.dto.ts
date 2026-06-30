import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsOptional, IsString, Matches, MaxLength } from 'class-validator';

// The server never decrypts this — it is the opaque, passphrase-sealed
// client envelope — but it must bound storage. A recovery backup is keys +
// small metadata, not message history, so 256 KB of base64 is generous.
export const MAX_RECOVERY_CIPHERTEXT_LENGTH = 256 * 1024;

export class UpsertRecoveryBlobDto {
  @ApiProperty({
    description: 'Passphrase-sealed client envelope (server never decrypts).',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(MAX_RECOVERY_CIPHERTEXT_LENGTH)
  ciphertext!: string;

  @ApiPropertyOptional({
    description: 'Envelope format marker, e.g. "veilbak:v1".',
  })
  @IsOptional()
  @IsString()
  @Matches(/^[a-z0-9:._-]{1,32}$/)
  format?: string;
}
