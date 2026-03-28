import { ApiProperty } from '@nestjs/swagger';
import { IsString, Length, Matches } from 'class-validator';

import type { CreateDirectConversationRequest } from '@veil/contracts';

export class CreateDirectConversationDto implements CreateDirectConversationRequest {
  @ApiProperty()
  @IsString()
  @Length(3, 32)
  @Matches(/^[a-z0-9._]+$/)
  peerHandle!: string;
}
