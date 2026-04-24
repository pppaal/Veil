import { Body, Controller, Delete, Param, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type {
  DeleteLocalMessageResponse,
  MarkMessageReadResponse,
  SendMessageResponse,
} from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { MessagesService } from './messages.service';
import { SendMessageDto } from './dto/send-message.dto';
import { ReactionDto } from './dto/reaction.dto';

@ApiTags('messages')
@ApiBearerAuth()
@Controller('messages')
export class MessagesController {
  constructor(private readonly messagesService: MessagesService) {}

  // Caps sustained message abuse while leaving normal bursts alone. At 120/min
  // you can still paste a long conversation or send rapid reactions without
  // hitting the ceiling.
  @Throttle({ default: { ttl: 60_000, limit: 120 } })
  @Post()
  send(
    @Req() request: AuthenticatedRequest,
    @Body() dto: SendMessageDto,
  ): Promise<SendMessageResponse> {
    return this.messagesService.send(request.auth, dto);
  }

  @Post(':id/read')
  markRead(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ): Promise<MarkMessageReadResponse> {
    return this.messagesService.markRead(request.auth, id);
  }

  @Post(':id/delete-local')
  deleteLocal(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ): Promise<DeleteLocalMessageResponse> {
    return this.messagesService.deleteLocal(request.auth, id);
  }

  @Post(':id/reactions')
  addReaction(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
    @Body() dto: ReactionDto,
  ) {
    return this.messagesService.addReaction(request.auth, id, dto.emoji);
  }

  @Delete(':id/reactions')
  removeReaction(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ) {
    return this.messagesService.removeReaction(request.auth, id);
  }
}
