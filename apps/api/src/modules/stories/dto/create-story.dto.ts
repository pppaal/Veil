import { ApiProperty } from '@nestjs/swagger';
import { Equals, IsIn, IsOptional, IsString, Length } from 'class-validator';

export const TEXT_STORY_CONTENT_URL = 'text://inline';

export class CreateStoryDto {
  // Media stories are disabled until they ship as encrypted attachments; a
  // free media URL would let any author plant a tracking pixel that logs the
  // IP of every viewer.
  @ApiProperty({ enum: ['text'] })
  @IsIn(['text'])
  contentType!: 'text';

  @ApiProperty({ required: false, default: TEXT_STORY_CONTENT_URL })
  @IsOptional()
  @Equals(TEXT_STORY_CONTENT_URL)
  contentUrl?: string;

  // Matches the stories.caption VarChar(300) column, so an over-long caption
  // is a 400 here instead of a database error.
  @ApiProperty({ required: false, maxLength: 300 })
  @IsOptional()
  @IsString()
  @Length(0, 300)
  caption?: string;
}
