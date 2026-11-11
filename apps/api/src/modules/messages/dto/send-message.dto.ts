import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
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
  PROD_ATTACHMENT_WRAP_ALGORITHM_HINT,
  SUPPORTED_ENVELOPE_VERSIONS,
  messageTypes,
  type MessageType,
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
  @IsIn([DEV_ATTACHMENT_WRAP_ALGORITHM_HINT, PROD_ATTACHMENT_WRAP_ALGORITHM_HINT])
  algorithmHint!: string;
}

// The outer attachment pointer. Only attachmentId is persisted or relayed;
// clients take attachment metadata from the authenticated inner payload.
// Older clients still send the full metadata block, so those fields are
// accepted (and shape-checked, so a malformed body is still a 400) and then
// discarded.
class AttachmentReferenceDto {
  @ApiProperty()
  @IsUUID()
  attachmentId!: string;

  @ApiProperty({ required: false, deprecated: true })
  @IsOptional()
  @IsString()
  @MaxLength(256)
  storageKey?: string;

  @ApiProperty({ required: false, deprecated: true })
  @IsOptional()
  @IsString()
  @MaxLength(128)
  contentType?: string;

  @ApiProperty({ required: false, deprecated: true })
  @IsOptional()
  @IsInt()
  @Min(1)
  sizeBytes?: number;

  @ApiProperty({ required: false, deprecated: true })
  @IsOptional()
  @IsString()
  @MaxLength(128)
  sha256?: string;

  @ApiProperty({ type: AttachmentEncryptionMaterialDto, required: false, deprecated: true })
  @IsOptional()
  @ValidateNested()
  @Type(() => AttachmentEncryptionMaterialDto)
  encryption?: AttachmentEncryptionMaterialDto;
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

  @ApiProperty({ required: false })
  @IsOptional()
  @IsUUID()
  recipientUserId?: string;

  @ApiProperty()
  @IsString()
  // 128KB ceiling — fits a ~30s opus@32kbps voice memo as inline
  // ciphertext after base64 inflation, which keeps the messages table
  // out of the attachment flow for short voice notes. Anything larger
  // must use the attachment upload-ticket path.
  @MaxLength(131072)
  ciphertext!: string;

  @ApiProperty()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,512}$/)
  nonce!: string;

  // 'system' stays allowed: clients send E2E-encrypted system notices, and
  // receivers render system chrome only from the decrypted kind.
  @ApiProperty()
  @IsIn(messageTypes)
  messageType!: MessageType;

  @ApiProperty({ required: false, nullable: true })
  @IsOptional()
  @IsISO8601()
  expiresAt?: string | null;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsBoolean()
  viewOnce?: boolean;

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

  @ApiProperty({ required: false, nullable: true })
  @IsOptional()
  @IsUUID()
  replyToMessageId?: string | null;

  // Group Sender Keys (phase AB.2). The membership generation the sender
  // encrypted under. Required and validated against conversations.current_epoch
  // only when the group has opted into Sender Keys; ignored otherwise, so
  // legacy clients and direct conversations are unaffected.
  @ApiProperty({ required: false })
  @IsOptional()
  @IsInt()
  @Min(0)
  groupEpoch?: number;
}

export class EditMessageDto {
  @ApiProperty()
  @IsString()
  // 128KB ceiling — fits a ~30s opus@32kbps voice memo as inline
  // ciphertext after base64 inflation, which keeps the messages table
  // out of the attachment flow for short voice notes. Anything larger
  // must use the attachment upload-ticket path.
  @MaxLength(131072)
  ciphertext!: string;

  @ApiProperty()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,512}$/)
  nonce!: string;

  @ApiProperty()
  @IsIn(SUPPORTED_ENVELOPE_VERSIONS)
  version!: string;
}
