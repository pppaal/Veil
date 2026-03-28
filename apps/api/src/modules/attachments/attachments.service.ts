import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type {
  AttachmentDownloadTicketResponse,
  CompleteAttachmentUploadResponse,
  CreateUploadTicketResponse,
} from '@veil/contracts';
import { randomUUID } from 'node:crypto';

import { AppConfigService } from '../../common/config/app-config.service';
import { PrismaService } from '../../common/prisma.service';
import {
  CompleteAttachmentUploadDto,
  CreateUploadTicketDto,
} from './dto/attachment.dto';

@Injectable()
export class AttachmentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: AppConfigService,
  ) {}

  async createUploadTicket(
    deviceId: string,
    dto: CreateUploadTicketDto,
  ): Promise<CreateUploadTicketResponse> {
    const attachment = await this.prisma.attachment.create({
      data: {
        uploaderDeviceId: deviceId,
        storageKey: `attachments/${deviceId}/${randomUUID()}`,
        contentType: dto.contentType,
        sizeBytes: dto.sizeBytes,
        sha256: dto.sha256,
        uploadStatus: 'pending',
      },
    });

    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    return {
      attachmentId: attachment.id,
      upload: {
        attachmentId: attachment.id,
        storageKey: attachment.storageKey,
        uploadUrl: `${this.config.s3Endpoint}/${this.config.s3Bucket}/${attachment.storageKey}`,
        headers: {
          'x-amz-meta-encrypted': 'true',
        },
        expiresAt,
      },
    };
  }

  async completeUpload(
    deviceId: string,
    dto: CompleteAttachmentUploadDto,
  ): Promise<CompleteAttachmentUploadResponse> {
    const attachment = await this.prisma.attachment.findUnique({
      where: { id: dto.attachmentId },
    });

    if (!attachment) {
      throw new NotFoundException('Attachment not found');
    }

    if (attachment.uploaderDeviceId !== deviceId) {
      throw new ForbiddenException('Attachment does not belong to device');
    }

    const updated = await this.prisma.attachment.update({
      where: { id: dto.attachmentId },
      data: { uploadStatus: dto.uploadStatus },
    });

    return {
      attachmentId: updated.id,
      uploadStatus: updated.uploadStatus,
    };
  }

  async createDownloadTicket(
    auth: { userId: string; deviceId: string },
    attachmentId: string,
  ): Promise<AttachmentDownloadTicketResponse> {
    const attachment = await this.prisma.attachment.findUnique({
      where: { id: attachmentId },
      select: {
        id: true,
        uploaderDeviceId: true,
        storageKey: true,
      },
    });

    if (!attachment) {
      throw new NotFoundException('Attachment not found');
    }

    if (attachment.uploaderDeviceId !== auth.deviceId) {
      const visibleMessage = await this.prisma.message.findFirst({
        where: {
          attachmentId,
          conversation: {
            members: {
              some: {
                userId: auth.userId,
              },
            },
          },
        },
        select: { id: true },
      });

      if (!visibleMessage) {
        throw new ForbiddenException('Attachment is not accessible to actor');
      }
    }

    return {
      ticket: {
        attachmentId: attachment.id,
        downloadUrl: `${this.config.s3Endpoint}/${this.config.s3Bucket}/${attachment.storageKey}`,
        expiresAt: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
      },
    };
  }
}
