import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Min,
  ValidateNested,
} from 'class-validator';

import { DEV_ENVELOPE_VERSION, messageTypes } from '@veil/shared';

class AttachmentEncryptionMaterialDto {
  @ApiProperty()
  @IsString()
  encryptedKey!: string;

  @ApiProperty()
  @IsString()
  nonce!: string;

  @ApiProperty()
  @IsString()
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
  @IsIn([DEV_ENVELOPE_VERSION])
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

  @ApiProperty({ type: EnvelopeDto })
  @ValidateNested()
  @Type(() => EnvelopeDto)
  envelope!: EnvelopeDto;
}
