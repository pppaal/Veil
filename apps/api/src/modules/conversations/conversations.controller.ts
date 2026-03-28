import { Body, Controller, Get, Param, Post, Query, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type {
  ConversationSummary,
  CreateDirectConversationResponse,
  ListMessagesResponse,
} from '@veil/contracts';

import { PaginationQueryDto } from '../../common/dto/pagination-query.dto';
import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { ConversationsService } from './conversations.service';
import { CreateDirectConversationDto } from './dto/create-direct-conversation.dto';

@ApiTags('conversations')
@ApiBearerAuth()
@Controller('conversations')
export class ConversationsController {
  constructor(private readonly conversationsService: ConversationsService) {}

  @Post('direct')
  createDirect(
    @Req() request: AuthenticatedRequest,
    @Body() dto: CreateDirectConversationDto,
  ): Promise<CreateDirectConversationResponse> {
    return this.conversationsService.createDirect(request.auth.userId, dto);
  }

  @Get()
  list(@Req() request: AuthenticatedRequest): Promise<ConversationSummary[]> {
    return this.conversationsService.listForUser(request.auth.userId);
  }

  @Get(':id/messages')
  listMessages(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
    @Query() query: PaginationQueryDto,
  ): Promise<ListMessagesResponse> {
    return this.conversationsService.listMessagesForUser(request.auth.userId, id, query);
  }
}
