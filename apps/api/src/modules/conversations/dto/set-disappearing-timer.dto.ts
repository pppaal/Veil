import { ApiProperty } from '@nestjs/swagger';
import { IsInt, IsOptional, Max, Min, ValidateIf } from 'class-validator';

import type { SetDisappearingTimerRequest } from '@veil/contracts';

export class SetDisappearingTimerDto implements SetDisappearingTimerRequest {
  // null / omitted disables the timer. Positive integer sets TTL in seconds.
  // Max 30 days — longer retention is functionally the same as no timer for
  // a privacy-oriented messenger and avoids absurd future Date values.
  @ApiProperty({ type: Number, nullable: true, required: false })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsInt()
  @Min(1)
  @Max(60 * 60 * 24 * 30)
  seconds!: number | null;
}
