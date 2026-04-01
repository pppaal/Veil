import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type {
  AttachmentDownloadTicketResponse,
  CompleteAttachmentUploadResponse,
  CreateUploadTicketResponse,
} from '@veil/contracts';
import { randomUUID } from 'node:crypto';

import { PrismaService } from '../../common/prisma.service';
import {
  ATTACHMENT_STORAGE_GATEWAY,
  type AttachmentStorageGateway,
} from './attachment-storage.gateway';
import {
  CompleteAttachmentUploadDto,
  CreateUploadTicketDto,
} from './dto/attachment.dto';

@Injectable()
export class AttachmentsService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(ATTACHMENT_STORAGE_GATEWAY)
    private readonly storageGateway: AttachmentStorageGateway,
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

    const upload = await this.storageGateway.createUploadTarget(attachment.storageKey, {
      attachmentId: attachment.id,
      sha256: attachment.sha256,
      sizeBytes: attachment.sizeBytes,
      contentType: attachment.contentType,
    });

    return {
      attachmentId: attachment.id,
      upload: {
        attachmentId: attachment.id,
        storageKey: attachment.storageKey,
        uploadUrl: upload.url,
        headers: upload.headers,
        expiresAt: upload.expiresAt,
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

    if (dto.uploadStatus === 'uploaded') {
      const objectHead = await this.storageGateway.headObject(attachment.storageKey);
      if (!objectHead.exists) {
        throw new BadRequestException('Encrypted blob is missing from object storage');
      }

      if (objectHead.sizeBytes !== attachment.sizeBytes) {
        throw new BadRequestException('Encrypted blob size does not match upload ticket');
      }

      const metadata = objectHead.metadata ?? {};
      if (metadata.encrypted !== 'true') {
        throw new BadRequestException('Encrypted blob metadata is missing');
      }
      if (metadata.sha256 !== attachment.sha256) {
        throw new BadRequestException('Encrypted blob hash metadata does not match upload ticket');
      }
      if (metadata['attachment-id'] !== attachment.id) {
        throw new BadRequestException('Encrypted blob attachment binding is invalid');
      }
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

    const download = await this.storageGateway.createDownloadTarget(attachment.storageKey);

    return {
      ticket: {
        attachmentId: attachment.id,
        downloadUrl: download.url,
        expiresAt: download.expiresAt,
      },
    };
  }
}
