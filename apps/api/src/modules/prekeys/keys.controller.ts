import { Body, Controller, Get, Param, Put, Query, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type {
  GroupMemberKeysResponse,
  KeysResponse,
  RotateSignedPrekeyResponse,
} from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { KeyDirectoryQueryDto, RotateSignedPrekeyDto } from './dto/keys.dto';
import { KeysService } from './keys.service';

// The key directory. Every lookup is tied to an authenticated device, which
// is what makes the per-requester claim budgets enforceable; there is no
// anonymous way to read anyone's keys.
@ApiTags('keys')
@ApiBearerAuth()
@Controller('keys')
export class KeysController {
  constructor(private readonly keysService: KeysService) {}

  // Reveals whether a handle exists and its device keys, so it is held to the
  // same per-minute rate as GET /users/:handle to keep enumeration slow.
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @Get(':handle')
  getKeys(
    @Req() request: AuthenticatedRequest,
    @Param('handle') handle: string,
    @Query() query: KeyDirectoryQueryDto,
  ): Promise<KeysResponse> {
    return this.keysService.getKeys(request.auth, handle, query.claim ?? 'active');
  }

  // Every other member's keys for one Sender Keys distribution round. Two path
  // segments, so it never matches :handle. Nothing is claimed, but it still
  // lists a group's members and their devices, so it is rate limited too.
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  @Get('group/:conversationId')
  getGroupMemberKeys(
    @Req() request: AuthenticatedRequest,
    @Param('conversationId') conversationId: string,
  ): Promise<GroupMemberKeysResponse> {
    return this.keysService.getGroupMemberKeys(request.auth, conversationId);
  }

  @Put('signed-prekey')
  rotateSignedPrekey(
    @Req() request: AuthenticatedRequest,
    @Body() dto: RotateSignedPrekeyDto,
  ): Promise<RotateSignedPrekeyResponse> {
    return this.keysService.rotateSignedPrekey(request.auth, dto.signedPrekeyBundle);
  }
}
