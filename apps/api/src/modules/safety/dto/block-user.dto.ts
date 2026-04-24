import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';

import type { BlockUserRequest } from '@veil/contracts';

export class BlockUserDto implements BlockUserRequest {
  @ApiProperty({ format: 'uuid' })
  @IsUUID()
  userId!: string;
}
