import { MAX_SIGNED_PREKEY_BUNDLE_LENGTH } from '@veil/shared';
import { ApiProperty } from '@nestjs/swagger';
import { DevicePlatform } from '@prisma/client';
import { IsEnum, IsOptional, IsString, IsUUID, Matches, MaxLength } from 'class-validator';

import type {
  DeviceTransferApproveRequest,
  DeviceTransferClaimRequest,
  DeviceTransferCompleteRequest,
  DeviceTransferInitRequest,
} from '@veil/contracts';

export class DeviceTransferInitDto implements DeviceTransferInitRequest {
  @ApiProperty()
  @IsUUID()
  oldDeviceId!: string;
}

export class DeviceTransferApproveDto implements DeviceTransferApproveRequest {
  @ApiProperty()
  @IsUUID()
  sessionId!: string;

  @ApiProperty()
  @IsUUID()
  claimId!: string;

  // Required by every relay. Optional here so a missing proof gets the same
  // 401 invalid_device_signature as a wrong one, not a 400 from validation.
  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  @MaxLength(1024)
  approvalProof?: string;
}

export class DeviceTransferClaimDto implements DeviceTransferClaimRequest {
  @ApiProperty()
  @IsUUID()
  sessionId!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(256)
  @Matches(/^[A-Za-z0-9._-]+$/)
  transferToken!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(80)
  newDeviceName!: string;

  @ApiProperty({ enum: DevicePlatform })
  @IsEnum(DevicePlatform)
  platform!: DevicePlatform;

  @ApiProperty()
  @IsString()
  @MaxLength(1024)
  publicIdentityKey!: string;

  @ApiProperty()
  @IsString()
  // libsignal bundles carry a Kyber-1024 prekey (1568 raw bytes) alongside the
  // signed prekey, so they exceed the 2 KiB that fit the X25519-only bundle.
  @MaxLength(MAX_SIGNED_PREKEY_BUNDLE_LENGTH)
  signedPrekeyBundle!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(512)
  authPublicKey!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(1024)
  authProof!: string;
}

export class DeviceTransferCompleteDto implements DeviceTransferCompleteRequest {
  @ApiProperty()
  @IsUUID()
  sessionId!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(256)
  @Matches(/^[A-Za-z0-9._-]+$/)
  transferToken!: string;

  @ApiProperty()
  @IsUUID()
  claimId!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(1024)
  authProof!: string;
}
