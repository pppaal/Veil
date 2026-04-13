import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';

export class ReactionDto {
  @ApiProperty({ description: 'Emoji character(s)', example: '👍' })
  @IsString()
  @MinLength(1)
  @MaxLength(8)
  emoji!: string;
}
