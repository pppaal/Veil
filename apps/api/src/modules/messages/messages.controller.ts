import { Body, Controller, Delete, Patch, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type {
  AddReactionResponse,
  DeleteLocalMessageResponse,
  DeleteMessageResponse,
  EditMessageResponse,
  MarkMessageReadResponse,
  RemoveReactionResponse,
  SendMessageResponse,
} from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { UuidParam } from '../../common/pipes/uuid-param.decorator';
import { MessagesService } from './messages.service';
import { EditMessageDto, SendMessageDto } from './dto/send-message.dto';
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
    @UuidParam('id') id: string,
  ): Promise<MarkMessageReadResponse> {
    return this.messagesService.markRead(request.auth, id);
  }

  @Post(':id/delete-local')
  deleteLocal(
    @Req() request: AuthenticatedRequest,
    @UuidParam('id') id: string,
  ): Promise<DeleteLocalMessageResponse> {
    return this.messagesService.deleteLocal(request.auth, id);
  }

  @Post(':id/reactions')
  addReaction(
    @Req() request: AuthenticatedRequest,
    @UuidParam('id') id: string,
    @Body() dto: ReactionDto,
  ): Promise<AddReactionResponse> {
    return this.messagesService.addReaction(request.auth, id, dto.emoji);
  }

  @Delete(':id/reactions')
  removeReaction(
    @Req() request: AuthenticatedRequest,
    @UuidParam('id') id: string,
  ): Promise<RemoveReactionResponse> {
    return this.messagesService.removeReaction(request.auth, id);
  }

  // Edit replaces the ciphertext in place. Only the original sending device
  // can re-encrypt, within 24 hours and under the original envelope version.
  @Patch(':id')
  edit(
    @Req() request: AuthenticatedRequest,
    @UuidParam('id') id: string,
    @Body() dto: EditMessageDto,
  ): Promise<EditMessageResponse> {
    return this.messagesService.edit(request.auth, id, dto);
  }

  // Soft delete. The row stays so reply chains still resolve, but the
  // ciphertext is wiped to a tombstone so the server cannot re-deliver
  // the original body even by accident.
  @Delete(':id')
  delete(
    @Req() request: AuthenticatedRequest,
    @UuidParam('id') id: string,
  ): Promise<DeleteMessageResponse> {
    return this.messagesService.delete(request.auth, id);
  }
}
