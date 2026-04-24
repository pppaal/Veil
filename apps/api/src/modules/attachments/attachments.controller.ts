import { Body, Controller, Get, Param, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type {
  AttachmentDownloadTicketResponse,
  CompleteAttachmentUploadResponse,
  CreateUploadTicketResponse,
} from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { AttachmentsService } from './attachments.service';
import {
  CompleteAttachmentUploadDto,
  CreateUploadTicketDto,
} from './dto/attachment.dto';

@ApiTags('attachments')
@ApiBearerAuth()
@Controller('attachments')
export class AttachmentsController {
  constructor(private readonly attachmentsService: AttachmentsService) {}

  // Upload tickets hold a presigned object-storage slot and cost more than a
  // plain message send; 40/min keeps bulk uploads possible while blocking
  // storage-exhaustion abuse.
  @Throttle({ default: { ttl: 60_000, limit: 40 } })
  @Post('upload-ticket')
  createUploadTicket(
    @Req() request: AuthenticatedRequest,
    @Body() dto: CreateUploadTicketDto,
  ): Promise<CreateUploadTicketResponse> {
    return this.attachmentsService.createUploadTicket(request.auth.deviceId, dto);
  }

  @Post('complete')
  completeUpload(
    @Req() request: AuthenticatedRequest,
    @Body() dto: CompleteAttachmentUploadDto,
  ): Promise<CompleteAttachmentUploadResponse> {
    return this.attachmentsService.completeUpload(request.auth.deviceId, dto);
  }

  @Throttle({ default: { ttl: 60_000, limit: 120 } })
  @Get(':id/download-ticket')
  createDownloadTicket(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ): Promise<AttachmentDownloadTicketResponse> {
    return this.attachmentsService.createDownloadTicket(request.auth, id);
  }
}
