import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

import {
  DEV_ATTACHMENT_WRAP_ALGORITHM_HINT,
  SUPPORTED_ENVELOPE_VERSIONS,
  messageTypes,
} from '@veil/shared';

class AttachmentEncryptionMaterialDto {
  @ApiProperty()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,512}$/)
  encryptedKey!: string;

  @ApiProperty()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,512}$/)
  nonce!: string;

  @ApiProperty()
  @IsIn([DEV_ATTACHMENT_WRAP_ALGORITHM_HINT])
  algorithmHint!: string;
}

class AttachmentReferenceDto {
  @ApiProperty()
  @IsUUID()
  attachmentId!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(256)
  storageKey!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(128)
  contentType!: string;

  @ApiProperty()
  @IsInt()
  @Min(1)
  sizeBytes!: number;

  @ApiProperty()
  @IsString()
  @MaxLength(128)
  sha256!: string;

  @ApiProperty({ type: AttachmentEncryptionMaterialDto })
  @ValidateNested()
  @Type(() => AttachmentEncryptionMaterialDto)
  encryption!: AttachmentEncryptionMaterialDto;
}

class EnvelopeDto {
  @ApiProperty()
  @IsIn(SUPPORTED_ENVELOPE_VERSIONS)
  version!: string;

  @ApiProperty()
  @IsUUID()
  conversationId!: string;

  @ApiProperty()
  @IsUUID()
  senderDeviceId!: string;

  @ApiProperty()
  @IsUUID()
  recipientUserId!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(16384)
  ciphertext!: string;

  @ApiProperty()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,512}$/)
  nonce!: string;

  @ApiProperty()
  @IsIn(messageTypes)
  messageType!: 'text' | 'image' | 'file' | 'system';

  @ApiProperty({ required: false, nullable: true })
  @IsOptional()
  @IsISO8601()
  expiresAt?: string | null;

  @ApiProperty({ required: false, nullable: true })
  @IsOptional()
  @ValidateNested()
  @Type(() => AttachmentReferenceDto)
  attachment?: AttachmentReferenceDto | null;
}

export class SendMessageDto {
  @ApiProperty()
  @IsUUID()
  conversationId!: string;

  @ApiProperty()
  @IsString()
  @Matches(/^[a-zA-Z0-9._:-]{8,80}$/)
  clientMessageId!: string;

  @ApiProperty({ type: EnvelopeDto })
  @ValidateNested()
  @Type(() => EnvelopeDto)
  envelope!: EnvelopeDto;
}
