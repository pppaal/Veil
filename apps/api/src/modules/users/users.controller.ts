import { Controller, Get, Param, Req, Res } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type { KeyBundleResponse, UserProfileResponse } from '@veil/contracts';
import type { Request, Response } from 'express';

import { Public } from '../../common/guards/public.decorator';
import { RequestTracker } from './request-tracker';
import { UsersService } from './users.service';

@ApiTags('users')
@ApiBearerAuth()
@Controller('users')
export class UsersController {
  constructor(
    private readonly usersService: UsersService,
    private readonly requestTracker: RequestTracker,
  ) {}

  // Takes a handle and reveals whether it exists, so it is limited even for
  // signed-in devices to keep namespace enumeration slow.
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @Get(':handle')
  getByHandle(@Param('handle') handle: string): Promise<UserProfileResponse> {
    return this.usersService.getUserByHandle(handle);
  }

  // Still public because both clients call it before they hold a session for
  // the peer; it goes away once they use GET /v1/keys/:handle.
  @Public()
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @Get(':handle/key-bundle')
  async getKeyBundle(
    @Param('handle') handle: string,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ): Promise<KeyBundleResponse> {
    response.setHeader('Deprecation', 'true');
    response.setHeader(
      'Link',
      `</v1/keys/${encodeURIComponent(handle.toLowerCase())}>; rel=successor-version`,
    );
    const clientTracker = await this.requestTracker.trackerFor(request);
    return this.usersService.getKeyBundle(handle, clientTracker);
  }
}
