import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, Length, Matches } from 'class-validator';

export class ManageMemberDto {
  @ApiProperty()
  @IsString()
  @Length(3, 32)
  @Matches(/^[a-z0-9._]+$/)
  handle!: string;

  @ApiPropertyOptional()
  @IsString()
  @IsOptional()
  @IsIn(['member', 'admin'])
  role?: 'member' | 'admin';
}
