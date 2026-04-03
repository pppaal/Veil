import { Body, Controller, Get, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { ListDevicesResponse, RevokeDeviceResponse } from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { DevicesService } from './devices.service';
import { RevokeDeviceDto } from './dto/revoke-device.dto';

@ApiTags('devices')
@ApiBearerAuth()
@Controller('devices')
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Get()
  list(
    @Req() request: AuthenticatedRequest,
  ): Promise<ListDevicesResponse> {
    return this.devicesService.list(request.auth.userId, request.auth.deviceId);
  }

  @Post('revoke')
  revoke(
    @Req() request: AuthenticatedRequest,
    @Body() dto: RevokeDeviceDto,
  ): Promise<RevokeDeviceResponse> {
    return this.devicesService.revoke(request.auth.userId, dto);
  }
}
