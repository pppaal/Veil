import { Body, Controller, Param, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type {
  DeleteLocalMessageResponse,
  MarkMessageReadResponse,
  SendMessageResponse,
} from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { MessagesService } from './messages.service';
import { SendMessageDto } from './dto/send-message.dto';

@ApiTags('messages')
@ApiBearerAuth()
@Controller('messages')
export class MessagesController {
  constructor(private readonly messagesService: MessagesService) {}

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
}
