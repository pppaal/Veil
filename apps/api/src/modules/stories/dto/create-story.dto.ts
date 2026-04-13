import { ApiProperty } from '@nestjs/swagger';
import { IsEnum, IsOptional, IsString, Length } from 'class-validator';

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
  contentUrl!: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  @Length(0, 500)
  caption?: string;
}
