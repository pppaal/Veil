import { Body, Controller, Get, Param, Put, Query, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { KeyDirectoryQueryDto, RotateSignedPrekeyDto } from './dto/keys.dto';
import { KeysService } from './keys.service';
import type { KeyDirectoryResponse, RotateSignedPrekeyResponse } from './keys.types';

// Authenticated key directory (successor of the public
// /users/:handle/key-bundle). Every lookup is tied to a device, which is what
// makes the per-requester claim budgets enforceable.
@ApiTags('keys')
@ApiBearerAuth()
@Controller('keys')
export class KeysController {
  constructor(private readonly keysService: KeysService) {}

  // Reveals whether a handle exists and its device keys, so it is held to the
  // same per-minute rate as the lookups it replaces to keep enumeration slow.
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @Get(':handle')
  getKeys(
    @Req() request: AuthenticatedRequest,
    @Param('handle') handle: string,
    @Query() query: KeyDirectoryQueryDto,
  ): Promise<KeyDirectoryResponse> {
    return this.keysService.getKeys(request.auth, handle, query.claim ?? 'active');
  }

  @Put('signed-prekey')
  rotateSignedPrekey(
    @Req() request: AuthenticatedRequest,
    @Body() dto: RotateSignedPrekeyDto,
  ): Promise<RotateSignedPrekeyResponse> {
    return this.keysService.rotateSignedPrekey(request.auth, dto.signedPrekeyBundle);
  }
}
