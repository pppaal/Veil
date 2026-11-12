import { Body, Controller, Delete, HttpCode, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { AuthService } from '../auth/auth.service';
import { DeviceStepUpDto } from '../auth/dto/device-step-up.dto';
import { AccountService } from './account.service';

@ApiTags('account')
@ApiBearerAuth()
@Controller('account')
export class AccountController {
  constructor(
    private readonly accountService: AccountService,
    private readonly authService: AuthService,
  ) {}

  // Irreversible, so a bearer token alone is not enough: the device signs a
  // fresh challenge (purpose 'account-delete').
  @Delete()
  @HttpCode(200)
  async deleteAccount(@Req() request: AuthenticatedRequest, @Body() dto: DeviceStepUpDto) {
    await this.authService.verifyDeviceStepUp(request.auth.deviceId, 'account-delete', dto);
    return this.accountService.deleteAccount(request.auth.userId);
  }
}
