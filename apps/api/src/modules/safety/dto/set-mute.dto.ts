import { ApiProperty } from '@nestjs/swagger';
import { IsInt, IsOptional, Max, Min, ValidateIf } from 'class-validator';

import type { SetConversationMuteRequest } from '@veil/contracts';

// The longest timed mute. A longer one would be indefinite in all but name,
// and a large enough value would not even make a valid Date.
export const MAX_MUTE_SECONDS = 10 * 365 * 24 * 60 * 60;

export class SetConversationMuteDto implements SetConversationMuteRequest {
  // null = unmute. Undefined = mute indefinitely. Positive integer = seconds
  // from now until auto-unmute, at most MAX_MUTE_SECONDS.
  @ApiProperty({ type: Number, nullable: true, required: false, maximum: MAX_MUTE_SECONDS })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsInt()
  @Min(1)
  @Max(MAX_MUTE_SECONDS)
  mutedForSeconds!: number | null | undefined;
}
