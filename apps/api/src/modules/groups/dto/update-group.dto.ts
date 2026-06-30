import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, Length } from 'class-validator';

export class UpdateGroupDto {
  @ApiPropertyOptional()
  @IsString()
  @IsOptional()
  @Length(1, 100)
  name?: string;

  @ApiPropertyOptional()
  @IsString()
  @IsOptional()
  @Length(0, 500)
  description?: string;

  @ApiPropertyOptional()
  @IsBoolean()
  @IsOptional()
  isPublic?: boolean;

  // Flip the group onto Sender Keys (phase AB.2). Enabling starts epoch
  // enforcement on the next send; clients must be on a Sender-Keys-capable
  // build before this is turned on for a live group.
  @ApiPropertyOptional()
  @IsBoolean()
  @IsOptional()
  useSenderKeys?: boolean;
}
