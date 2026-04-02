import { ApiProperty } from '@nestjs/swagger';
import { DevicePlatform } from '@prisma/client';
import { IsEnum, IsString, IsUUID, Matches, MaxLength } from 'class-validator';

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
  @MaxLength(2048)
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
