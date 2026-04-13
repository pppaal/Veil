import { Body, Controller, Get, Param, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { CallsService } from './calls.service';
import { InitiateCallDto } from './dto/initiate-call.dto';

@ApiTags('calls')
@ApiBearerAuth()
@Controller('calls')
export class CallsController {
  constructor(private readonly callsService: CallsService) {}

  @Post('initiate')
  initiateCall(
    @Req() request: AuthenticatedRequest,
    @Body() dto: InitiateCallDto,
  ) {
    return this.callsService.initiateCall(request.auth, dto);
  }

  @Post(':id/end')
  endCall(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ) {
    return this.callsService.endCall(request.auth, id);
  }

  @Get()
  listCalls(@Req() request: AuthenticatedRequest) {
    return this.callsService.listCalls(request.auth);
  }
}
