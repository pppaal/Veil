import { Body, Controller, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type {
  DeviceTransferApproveResponse,
  DeviceTransferCompleteResponse,
  DeviceTransferInitResponse,
} from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { Public } from '../../common/guards/public.decorator';
import { DeviceTransferService } from './device-transfer.service';
import {
  DeviceTransferApproveDto,
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
  @Post('complete')
  complete(@Body() dto: DeviceTransferCompleteDto): Promise<DeviceTransferCompleteResponse> {
    return this.deviceTransferService.complete(dto);
  }
}
