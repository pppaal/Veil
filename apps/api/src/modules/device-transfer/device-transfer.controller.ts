import { Body, Controller, Get, Headers, Param, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type {
  DeviceTransferApproveResponse,
  DeviceTransferClaimResponse,
  DeviceTransferCompleteResponse,
  DeviceTransferInitResponse,
  DeviceTransferSessionStatusResponse,
} from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { Public } from '../../common/guards/public.decorator';
import { DeviceTransferService } from './device-transfer.service';
import {
  DeviceTransferApproveDto,
  DeviceTransferClaimDto,
  DeviceTransferCompleteDto,
  DeviceTransferInitDto,
} from './dto/device-transfer.dto';

@ApiTags('device-transfer')
@ApiBearerAuth()
@Controller('device-transfer')
export class DeviceTransferController {
  constructor(private readonly deviceTransferService: DeviceTransferService) {}

  @Post('init')
  init(
    @Req() request: AuthenticatedRequest,
    @Body() dto: DeviceTransferInitDto,
  ): Promise<DeviceTransferInitResponse> {
    return this.deviceTransferService.init(request.auth, dto);
  }

  @Post('approve')
  approve(
    @Req() request: AuthenticatedRequest,
    @Body() dto: DeviceTransferApproveDto,
  ): Promise<DeviceTransferApproveResponse> {
    return this.deviceTransferService.approve(request.auth, dto);
  }

  @Public()
  @Post('claim')
  claim(@Body() dto: DeviceTransferClaimDto): Promise<DeviceTransferClaimResponse> {
    return this.deviceTransferService.claim(dto);
  }

  @Public()
  @Post('complete')
  complete(@Body() dto: DeviceTransferCompleteDto): Promise<DeviceTransferCompleteResponse> {
    return this.deviceTransferService.complete(dto);
  }

  // Polled by the old device while it waits for the new device to claim
  // and present its public key fingerprint. The new device polls /complete
  // directly, so it doesn't need this endpoint — same auth proof, server
  // returns 403 transfer_approval_required until the old device approves.
  @Get('sessions/:sessionId')
  getStatus(
    @Param('sessionId') sessionId: string,
    @Req() request: AuthenticatedRequest,
  ): Promise<DeviceTransferSessionStatusResponse> {
    return this.deviceTransferService.getSessionStatus({
      sessionId,
      auth: request.auth,
    });
  }
}
