import { ApiProperty } from '@nestjs/swagger';
import { IsOptional, IsString, Length, Matches } from 'class-validator';

export class AddContactDto {
  @ApiProperty()
  @IsString()
  @Length(3, 32)
  @Matches(/^[a-z0-9._]+$/)
  handle!: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  @Length(0, 80)
  nickname?: string;
}
