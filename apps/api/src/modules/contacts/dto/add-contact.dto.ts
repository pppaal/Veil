import { ApiProperty } from '@nestjs/swagger';
import type { AddContactRequest } from '@veil/contracts';
import { IsOptional, IsString, Length, Matches } from 'class-validator';

export class AddContactDto implements AddContactRequest {
  @ApiProperty()
  @IsString()
  @Length(3, 32)
  @Matches(/^[a-z0-9._]+$/)
  handle!: string;

  /** @deprecated Accepted so older clients keep working; never stored. */
  @ApiProperty({ required: false, deprecated: true })
  @IsOptional()
  @IsString()
  @Length(0, 80)
  nickname?: string;
}
