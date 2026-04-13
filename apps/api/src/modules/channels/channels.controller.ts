import { Body, Controller, Get, Param, Patch, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { ChannelsService } from './channels.service';
import { CreateChannelDto } from './dto/create-channel.dto';
import { UpdateChannelDto } from './dto/update-channel.dto';

@ApiTags('channels')
@ApiBearerAuth()
@Controller('conversations/channel')
export class ChannelsController {
  constructor(private readonly channelsService: ChannelsService) {}

  @Post()
  createChannel(
    @Req() request: AuthenticatedRequest,
    @Body() dto: CreateChannelDto,
  ) {
    return this.channelsService.createChannel(request.auth, dto);
  }

  @Get(':id')
  getChannel(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ) {
    return this.channelsService.getChannel(request.auth, id);
  }

  @Patch(':id')
  updateChannel(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
    @Body() dto: UpdateChannelDto,
  ) {
    return this.channelsService.updateChannel(request.auth, id, dto);
  }

  @Post(':id/subscribe')
  subscribe(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ) {
    return this.channelsService.subscribe(request.auth, id);
  }

  @Post(':id/unsubscribe')
  unsubscribe(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ) {
    return this.channelsService.unsubscribe(request.auth, id);
  }
}
