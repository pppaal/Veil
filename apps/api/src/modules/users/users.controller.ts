import { Controller, Get, Param } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type { KeyBundleResponse, UserProfileResponse } from '@veil/contracts';

import { Public } from '../../common/guards/public.decorator';
import { UsersService } from './users.service';

@ApiTags('users')
@ApiBearerAuth()
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Public()
  @Throttle({ default: { ttl: 60_000, limit: 15 } })
  @Get(':handle')
  getByHandle(@Param('handle') handle: string): Promise<UserProfileResponse> {
    return this.usersService.getUserByHandle(handle);
  }

  @Public()
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @Get(':handle/key-bundle')
  getKeyBundle(@Param('handle') handle: string): Promise<KeyBundleResponse> {
    return this.usersService.getKeyBundle(handle);
  }
}
