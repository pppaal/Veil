import { Body, Controller, Get, Param, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type {
  ClaimOneTimePrekeyResponse,
  OneTimePrekeyCountResponse,
  UploadOneTimePrekeysResponse,
} from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { UploadPrekeysDto } from './dto/upload-prekeys.dto';
import { PrekeysService } from './prekeys.service';

@ApiTags('prekeys')
@ApiBearerAuth()
@Controller('prekeys')
export class PrekeysController {
  constructor(private readonly prekeysService: PrekeysService) {}

  // A device uploads/replenishes its own pool. The device id comes from the
  // token, so a device can only ever write its own prekeys.
  @Post()
  upload(
    @Req() request: AuthenticatedRequest,
    @Body() dto: UploadPrekeysDto,
  ): Promise<UploadOneTimePrekeysResponse> {
    return this.prekeysService.upload(request.auth.userId, request.auth.deviceId, dto.prekeys);
  }

  @Get('count')
  count(@Req() request: AuthenticatedRequest): Promise<OneTimePrekeyCountResponse> {
    return this.prekeysService.count(request.auth.userId, request.auth.deviceId);
  }

  // Legacy single-device claim, superseded by GET /v1/keys/:handle. A claim
  // consumes the target's pool, so it needs an authenticated requester whose
  // per-target budgets cap how fast any one device can drain it.
  @Post('claim/:handle')
  claim(
    @Req() request: AuthenticatedRequest,
    @Param('handle') handle: string,
  ): Promise<ClaimOneTimePrekeyResponse> {
    return this.prekeysService.claim(request.auth, handle);
  }
}
