import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
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
  encryptedKey!: string;

  @ApiProperty()
  @IsString()
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
  storageKey!: string;

  @ApiProperty()
  @IsString()
  contentType!: string;

  @ApiProperty()
  @IsInt()
  @Min(1)
  sizeBytes!: number;

  @ApiProperty()
  @IsString()
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
  ciphertext!: string;

  @ApiProperty()
  @IsString()
  nonce!: string;

  @ApiProperty()
  @IsIn(messageTypes)
  messageType!: 'text' | 'image' | 'file' | 'system';

  @ApiProperty({ required: false, nullable: true })
  @IsOptional()
  @IsString()
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
