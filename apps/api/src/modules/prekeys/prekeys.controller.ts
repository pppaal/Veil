import { Body, Controller, Get, Param, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type {
  ClaimOneTimePrekeyResponse,
  OneTimePrekeyCountResponse,
  UploadOneTimePrekeysResponse,
} from '@veil/contracts';

import { Public } from '../../common/guards/public.decorator';
import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { UploadPrekeysDto } from './dto/upload-prekeys.dto';
import { PrekeysService } from './prekeys.service';

@ApiTags('prekeys')
@Controller('prekeys')
export class PrekeysController {
  constructor(private readonly prekeysService: PrekeysService) {}

  // Authenticated: a device uploads/replenishes its own pool. The device id
  // comes from the token, so a device can only ever write its own prekeys.
  @ApiBearerAuth()
  @Post()
  upload(
    @Req() request: AuthenticatedRequest,
    @Body() dto: UploadPrekeysDto,
  ): Promise<UploadOneTimePrekeysResponse> {
    return this.prekeysService.upload(request.auth.userId, request.auth.deviceId, dto.prekeys);
  }

  @ApiBearerAuth()
  @Get('count')
  count(@Req() request: AuthenticatedRequest): Promise<OneTimePrekeyCountResponse> {
    return this.prekeysService.count(request.auth.userId, request.auth.deviceId);
  }

  // Public: an initiator claims one of the target's prekeys to start a session,
  // mirroring the @Public key-bundle lookup. Consuming write, so throttle it to
  // blunt pool-drain abuse; a claim reveals only opaque public key material.
  @Public()
  @Throttle({ default: { ttl: 60_000, limit: 30 } })
  @Post('claim/:handle')
  claim(@Param('handle') handle: string): Promise<ClaimOneTimePrekeyResponse> {
    return this.prekeysService.claim(handle);
  }
}
