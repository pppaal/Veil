import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsOptional, IsString, Length } from 'class-validator';

// C0/C1 control characters, the BOM, and BiDi/format marks let an attacker
// embed invisible text in their display name to spoof another user or break
// chat list layout. Strip them before they ever reach the database.
//   \x00-\x1F : C0 control set
//   \x7F-\x9F : DEL + C1 control set
//   ​-‏: ZWSP/ZWNJ/ZWJ/LRM/RLM
//   ‪-‮: LRE/RLE/PDF/LRO/RLO
//   ⁠-⁯: WJ/invisible math/format chars
//   ﻿ : BOM
const SANITIZE_RE =
  /[\x00-\x1F\x7F-\x9F​-‏‪-‮⁠-⁯﻿]/g;

const sanitize = ({ value }: { value: unknown }): unknown => {
  if (typeof value !== 'string') return value;
  return value.replace(SANITIZE_RE, '').trim();
};

export class UpdateProfileDto {
  @ApiProperty({ required: false })
  @IsOptional()
  @Transform(sanitize)
  @IsString()
  @Length(1, 80)
  displayName?: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @Transform(sanitize)
  @IsString()
  @Length(0, 300)
  bio?: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @Transform(sanitize)
  @IsString()
  @Length(0, 100)
  statusMessage?: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @Transform(sanitize)
  @IsString()
  @Length(0, 4)
  statusEmoji?: string;
}
