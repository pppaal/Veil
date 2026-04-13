import { ApiProperty } from '@nestjs/swagger';
import { IsIn, IsString, IsUUID } from 'class-validator';

export class InitiateCallDto {
  @ApiProperty()
  @IsUUID()
  conversationId!: string;

  @ApiProperty({ enum: ['voice', 'video'] })
  @IsString()
  @IsIn(['voice', 'video'])
  callType!: 'voice' | 'video';
}
