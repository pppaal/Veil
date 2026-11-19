import { ApiProperty } from '@nestjs/swagger';
import type { TransferGroupOwnershipRequest } from '@veil/contracts';
import { IsUUID } from 'class-validator';

export class TransferOwnershipDto implements TransferGroupOwnershipRequest {
  @ApiProperty({ description: 'Current member who becomes the owner.' })
  @IsUUID()
  userId!: string;
}
