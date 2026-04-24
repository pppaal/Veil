import { Body, Controller, Delete, Get, Param, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type {
  BlockUserResponse,
  FileAbuseReportResponse,
  ListBlockedUsersResponse,
  SetConversationMuteResponse,
  UnblockUserResponse,
} from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { BlockUserDto } from './dto/block-user.dto';
import { FileAbuseReportDto } from './dto/file-report.dto';
import { SetConversationMuteDto } from './dto/set-mute.dto';
import { SafetyService } from './safety.service';

@ApiTags('safety')
@ApiBearerAuth()
@Controller('safety')
export class SafetyController {
  constructor(private readonly safetyService: SafetyService) {}

  @Get('blocks')
  listBlocked(@Req() request: AuthenticatedRequest): Promise<ListBlockedUsersResponse> {
    return this.safetyService.listBlocked(request.auth.userId);
  }

  @Post('blocks')
  block(
    @Req() request: AuthenticatedRequest,
    @Body() dto: BlockUserDto,
  ): Promise<BlockUserResponse> {
    return this.safetyService.block(request.auth.userId, dto.userId);
  }

  @Delete('blocks/:userId')
  unblock(
    @Req() request: AuthenticatedRequest,
    @Param('userId') userId: string,
  ): Promise<UnblockUserResponse> {
    return this.safetyService.unblock(request.auth.userId, userId);
  }

  @Post('mutes/:conversationId')
  setMute(
    @Req() request: AuthenticatedRequest,
    @Param('conversationId') conversationId: string,
    @Body() dto: SetConversationMuteDto,
  ): Promise<SetConversationMuteResponse> {
    return this.safetyService.setConversationMute(
      request.auth.userId,
      conversationId,
      dto.mutedForSeconds,
    );
  }

  // Reports land in a privileged table reviewed out-of-band. Tight throttle
  // keeps the moderation queue from being weaponized as a DoS against a user.
  @Throttle({ default: { ttl: 60_000, limit: 6 } })
  @Post('reports')
  fileReport(
    @Req() request: AuthenticatedRequest,
    @Body() dto: FileAbuseReportDto,
  ): Promise<FileAbuseReportResponse> {
    return this.safetyService.fileReport(request.auth.userId, dto);
  }
}
