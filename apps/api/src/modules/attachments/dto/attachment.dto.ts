import { ApiProperty } from '@nestjs/swagger';
import { AttachmentUploadStatus } from '@prisma/client';
import { IsEnum, IsInt, IsString, IsUUID, Matches, Max, MaxLength, Min } from 'class-validator';

import type {
  CompleteAttachmentUploadRequest,
  CreateUploadTicketRequest,
} from '@veil/contracts';

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
  @MaxLength(128)
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
