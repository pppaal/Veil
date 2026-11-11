import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { GROUP_MAX_MEMBERS } from '@veil/shared';
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsOptional,
  IsString,
  Length,
} from 'class-validator';

export class CreateGroupDto {
  @ApiProperty()
  @IsString()
  @Length(1, 100)
  name!: string;

  @ApiPropertyOptional()
  @IsString()
  @IsOptional()
  @Length(0, 500)
  description?: string;

  // The creator is the owner, so founding members fill the remaining seats.
  @ApiPropertyOptional({ maxItems: GROUP_MAX_MEMBERS - 1 })
  @IsArray()
  @ArrayMaxSize(GROUP_MAX_MEMBERS - 1)
  @ArrayUnique()
  @IsString({ each: true })
  @IsOptional()
  memberHandles?: string[];

  @ApiPropertyOptional()
  @IsBoolean()
  @IsOptional()
  isPublic?: boolean;

  // Opt the new group into Sender Keys (phase AB.2). Defaults false — the
  // group stays on the legacy shared key until clients implement the crypto.
  @ApiPropertyOptional()
  @IsBoolean()
  @IsOptional()
  useSenderKeys?: boolean;
}
