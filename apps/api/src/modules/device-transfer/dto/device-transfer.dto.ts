import { ApiProperty } from '@nestjs/swagger';
import { DevicePlatform } from '@prisma/client';
import { IsEnum, IsString, IsUUID, MaxLength } from 'class-validator';

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
  publicIdentityKey!: string;

  @ApiProperty()
  @IsString()
  signedPrekeyBundle!: string;

  @ApiProperty()
  @IsString()
  authPublicKey!: string;

  @ApiProperty()
  @IsString()
  authProof!: string;
}

export class DeviceTransferCompleteDto implements DeviceTransferCompleteRequest {
  @ApiProperty()
  @IsUUID()
  sessionId!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(256)
  transferToken!: string;

  @ApiProperty()
  @IsUUID()
  claimId!: string;
}
