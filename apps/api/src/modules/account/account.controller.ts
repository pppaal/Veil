import { Controller, Delete, HttpCode, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { AccountService } from './account.service';

@ApiTags('account')
@ApiBearerAuth()
@Controller('account')
export class AccountController {
  constructor(private readonly accountService: AccountService) {}

  @Delete()
  @HttpCode(200)
  deleteAccount(@Req() request: AuthenticatedRequest) {
    return this.accountService.deleteAccount(request.auth.userId);
  }
}
