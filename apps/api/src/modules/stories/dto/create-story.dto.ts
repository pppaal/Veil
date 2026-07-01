import { ApiProperty } from '@nestjs/swagger';
import { IsEnum, IsOptional, IsString, Length, Matches, MaxLength } from 'class-validator';

export enum StoryContentType {
  TEXT = 'text',
  IMAGE = 'image',
  VIDEO = 'video',
}

export class CreateStoryDto {
  @ApiProperty({ enum: StoryContentType })
  @IsEnum(StoryContentType)
  contentType!: StoryContentType;

  @ApiProperty()
  @IsString()
  @MaxLength(2048)
  // Scheme allowlist: media stories carry an https URL, text stories carry the
  // `text://inline` sentinel. Requiring one of these bounds the value and
  // rejects dangerous schemes (javascript:, data:, file:) at the persistence
  // boundary. New media schemes must be added here deliberately.
  @Matches(/^(https?|text):\/\/.+/i)
  contentUrl!: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  @Length(0, 500)
  caption?: string;
}
