import { ApiProperty } from '@nestjs/swagger';
import { AttachmentUploadStatus } from '@prisma/client';
import { IsEnum, IsInt, IsString, IsUUID, Matches, Max, MaxLength, Min } from 'class-validator';

import type { CompleteAttachmentUploadRequest, CreateUploadTicketRequest } from '@veil/contracts';

export class CreateUploadTicketDto implements CreateUploadTicketRequest {
  @ApiProperty()
  @IsString()
  @MaxLength(128)
  @Matches(/^[\w.+-]+\/[\w.+-]+$/)
  contentType!: string;

  @ApiProperty()
  @IsInt()
  @Min(1)
  @Max(50 * 1024 * 1024)
  sizeBytes!: number;

  @ApiProperty()
  @IsString()
  // A SHA-256 is exactly 64 hex chars. The prior /^[a-fA-F0-9-]{8,128}$/ let
  // through 8–128 chars and even hyphens, which is not a real content hash.
  @Matches(/^[a-f0-9]{64}$/i)
  sha256!: string;
}

export class CompleteAttachmentUploadDto implements CompleteAttachmentUploadRequest {
  @ApiProperty()
  @IsUUID()
  attachmentId!: string;

  @ApiProperty({ enum: AttachmentUploadStatus })
  @IsEnum(AttachmentUploadStatus)
  uploadStatus!: AttachmentUploadStatus;
}
