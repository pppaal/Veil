import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';

export class UpdatePushTokenDto {
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(512)
  pushToken!: string;
}

export class ClearPushTokenDto {}
