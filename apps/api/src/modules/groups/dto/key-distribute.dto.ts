import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

// One distribution per remaining member; the private-beta group cap is 25,
// so 64 leaves headroom without letting a single call fan out unboundedly.
export const MAX_DISTRIBUTIONS_PER_CALL = 64;
// An encrypted 32-byte chain key + counter + epoch under the 1:1 ratchet is
// well under 1 KiB base64; 4 KiB bounds abuse of the relay as blob storage.
export const MAX_ENCRYPTED_CHAIN_KEY_LENGTH = 4096;

class KeyDistributionDto {
  @ApiProperty({ description: 'Member the blob is encrypted for.' })
  @IsUUID()
  recipientUserId!: string;

  @ApiProperty({
    description: 'Chain key encrypted under the sender↔recipient 1:1 ratchet (opaque to server).',
  })
  @IsString()
  @Matches(/^[A-Za-z0-9._:+/=-]+$/)
  @MaxLength(MAX_ENCRYPTED_CHAIN_KEY_LENGTH)
  encryptedChainKey!: string;

  @ApiProperty({ description: 'AEAD nonce for the encrypted blob.' })
  @IsString()
  @Matches(/^[A-Za-z0-9._:+/=-]+$/)
  @MaxLength(256)
  nonce!: string;

  @ApiProperty({ description: 'Distribution payload version marker.' })
  @IsString()
  @Matches(/^[A-Za-z0-9._-]+$/)
  @MaxLength(64)
  version!: string;
}

export class KeyDistributeDto {
  @ApiProperty({ description: "Must equal the conversation's current epoch." })
  @IsInt()
  @Min(0)
  @Max(Number.MAX_SAFE_INTEGER)
  epoch!: number;

  @ApiProperty({ type: [KeyDistributionDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_DISTRIBUTIONS_PER_CALL)
  @ValidateNested({ each: true })
  @Type(() => KeyDistributionDto)
  distributions!: KeyDistributionDto[];
}
