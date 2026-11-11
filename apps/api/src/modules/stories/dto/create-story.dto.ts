import { ApiProperty } from '@nestjs/swagger';
import {
  STORY_MAX_AUDIENCE,
  STORY_MAX_CIPHERTEXT_LENGTH,
  type CreateStoryRequest,
} from '@veil/contracts';
import { SUPPORTED_ENVELOPE_VERSIONS } from '@veil/shared';
import {
  ArrayMaxSize,
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsIn,
  IsString,
  IsUUID,
  Length,
} from 'class-validator';

// The server stores a story as one opaque envelope plus the audience it is
// addressed to; its content and media type exist only inside the ciphertext.
export class CreateStoryDto implements CreateStoryRequest {
  @ApiProperty({ maxLength: STORY_MAX_CIPHERTEXT_LENGTH })
  @IsString()
  @Length(1, STORY_MAX_CIPHERTEXT_LENGTH)
  ciphertext!: string;

  @ApiProperty({ enum: SUPPORTED_ENVELOPE_VERSIONS })
  @IsIn(SUPPORTED_ENVELOPE_VERSIONS)
  envelopeVersion!: string;

  @ApiProperty({ type: [String], minItems: 1, maxItems: STORY_MAX_AUDIENCE })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(STORY_MAX_AUDIENCE)
  @ArrayUnique()
  @IsUUID('all', { each: true })
  audienceUserIds!: string[];
}
