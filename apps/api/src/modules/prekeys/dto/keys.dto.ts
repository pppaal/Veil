import { ApiProperty } from '@nestjs/swagger';
import { MAX_SIGNED_PREKEY_BUNDLE_LENGTH } from '@veil/shared';
import { IsIn, IsOptional, IsString, Matches, MaxLength } from 'class-validator';

import { KEY_CLAIM_MODES, type KeyClaimMode, type RotateSignedPrekeyRequest } from '../keys.types';

export class KeyDirectoryQueryDto {
  @ApiProperty({ enum: KEY_CLAIM_MODES, required: false, default: 'active' })
  @IsOptional()
  @IsIn(KEY_CLAIM_MODES)
  claim?: KeyClaimMode;
}

// Only the signed prekey can change here; the identity key is fixed for the
// device's lifetime, and the whitelisting ValidationPipe rejects any attempt
// to send one.
export class RotateSignedPrekeyDto implements RotateSignedPrekeyRequest {
  @ApiProperty({ description: 'Signed-prekey bundle v2 (base64url-nopad).' })
  @IsString()
  @MaxLength(MAX_SIGNED_PREKEY_BUNDLE_LENGTH)
  @Matches(/^[A-Za-z0-9_-]+$/)
  signedPrekeyBundle!: string;
}
