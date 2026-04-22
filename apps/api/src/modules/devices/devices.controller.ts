import { Body, Controller, Delete, Get, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { ListDevicesResponse, RevokeDeviceResponse } from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { DevicesService } from './devices.service';
import { RevokeDeviceDto } from './dto/revoke-device.dto';
import { UpdatePushTokenDto } from './dto/update-push-token.dto';

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

  @Post('push-token')
  updatePushToken(
    @Req() request: AuthenticatedRequest,
    @Body() dto: UpdatePushTokenDto,
  ): Promise<{ deviceId: string; updatedAt: string }> {
    return this.devicesService.updatePushToken(
      request.auth.userId,
      request.auth.deviceId,
      dto.pushToken,
    );
  }

  @Delete('push-token')
  clearPushToken(
    @Req() request: AuthenticatedRequest,
  ): Promise<{ deviceId: string; clearedAt: string }> {
    return this.devicesService.clearPushToken(
      request.auth.userId,
      request.auth.deviceId,
    );
  }
}
