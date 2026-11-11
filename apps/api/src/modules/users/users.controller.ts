import { Controller, Get, Param } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type { UserProfileResponse } from '@veil/contracts';

import { UsersService } from './users.service';

// Key material comes from the authenticated GET /keys/:handle; nothing about a
// user is served without a bearer token.
@ApiTags('users')
@ApiBearerAuth()
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  // Takes a handle and reveals whether it exists, so it is limited even for
  // signed-in devices to keep namespace enumeration slow.
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @Get(':handle')
  getByHandle(@Param('handle') handle: string): Promise<UserProfileResponse> {
    return this.usersService.getUserByHandle(handle);
  }
}
