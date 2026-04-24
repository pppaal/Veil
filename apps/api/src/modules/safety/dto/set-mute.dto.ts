import { ApiProperty } from '@nestjs/swagger';
import { IsInt, IsOptional, Min, ValidateIf } from 'class-validator';

import type { SetConversationMuteRequest } from '@veil/contracts';

export class SetConversationMuteDto implements SetConversationMuteRequest {
  // null = unmute. Undefined = mute indefinitely. Positive integer = seconds
  // from now until auto-unmute. Capped at 10 years so we never build a Date
  // that overflows downstream systems.
  @ApiProperty({ type: Number, nullable: true, required: false })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsInt()
  @Min(1)
  mutedForSeconds!: number | null | undefined;
}
