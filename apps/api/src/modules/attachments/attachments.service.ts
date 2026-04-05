import {
  Inject,
  Injectable,
} from '@nestjs/common';
import type {
  AttachmentDownloadTicketResponse,
  CompleteAttachmentUploadResponse,
  CreateUploadTicketResponse,
} from '@veil/contracts';
import { randomUUID } from 'node:crypto';

import { PrismaService } from '../../common/prisma.service';
import {
  badRequest,
  forbidden,
  notFound,
} from '../../common/errors/api-error';
import { AppConfigService } from '../../common/config/app-config.service';
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
    private readonly config: AppConfigService,
    @Inject(ATTACHMENT_STORAGE_GATEWAY)
    private readonly storageGateway: AttachmentStorageGateway,
  ) {}

  async createUploadTicket(
    deviceId: string,
    dto: CreateUploadTicketDto,
  ): Promise<CreateUploadTicketResponse> {
    await this.cleanupExpiredPendingUploads(deviceId);
    this.assertUploadPolicy(dto);

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
        contentType: upload.contentType,
        sizeBytes: upload.sizeBytes,
        expiresAt: upload.expiresAt,
      },
      constraints: {
        maxSizeBytes: this.config.attachmentMaxBytes,
        allowedMimeTypes: this.config.attachmentAllowedMimeTypes,
      },
    };
  }

  async completeUpload(
    deviceId: string,
    dto: CompleteAttachmentUploadDto,
  ): Promise<CompleteAttachmentUploadResponse> {
    await this.cleanupExpiredPendingUploads(deviceId);

    const attachment = await this.prisma.attachment.findUnique({
      where: { id: dto.attachmentId },
    });

    if (!attachment) {
      throw notFound('attachment_not_found', 'Attachment not found');
    }

    if (attachment.uploaderDeviceId !== deviceId) {
      throw forbidden('attachment_forbidden', 'Attachment does not belong to device');
    }

    if (dto.uploadStatus === 'failed') {
      await this.storageGateway.deleteObject(attachment.storageKey);
    }

    if (dto.uploadStatus === 'uploaded') {
      const objectHead = await this.storageGateway.headObject(attachment.storageKey);
      if (!objectHead.exists) {
        throw badRequest('attachment_upload_invalid', 'Encrypted blob is missing from object storage');
      }

      if (objectHead.sizeBytes !== attachment.sizeBytes) {
        throw badRequest('attachment_upload_invalid', 'Encrypted blob size does not match upload ticket');
      }

      if (objectHead.contentType && objectHead.contentType !== attachment.contentType) {
        throw badRequest(
          'attachment_upload_invalid',
          'Encrypted blob content type does not match upload ticket',
        );
      }

      const metadata = objectHead.metadata ?? {};
      if (metadata.encrypted !== 'true') {
        throw badRequest('attachment_upload_invalid', 'Encrypted blob metadata is missing');
      }
      if (metadata.sha256 !== attachment.sha256) {
        throw badRequest(
          'attachment_upload_invalid',
          'Encrypted blob hash metadata does not match upload ticket',
        );
      }
      if (metadata['attachment-id'] !== attachment.id) {
        throw badRequest('attachment_upload_invalid', 'Encrypted blob attachment binding is invalid');
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
    await this.cleanupExpiredPendingUploads(auth.deviceId);

    const attachment = await this.prisma.attachment.findUnique({
      where: { id: attachmentId },
      select: {
        id: true,
        uploaderDeviceId: true,
        storageKey: true,
        uploadStatus: true,
      },
    });

    if (!attachment) {
      throw notFound('attachment_not_found', 'Attachment not found');
    }

    if (attachment.uploadStatus !== 'uploaded') {
      throw badRequest('attachment_upload_invalid', 'Attachment blob is not available for download');
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
        throw forbidden('attachment_forbidden', 'Attachment is not accessible to actor');
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

  private assertUploadPolicy(dto: CreateUploadTicketDto): void {
    const normalizedMime = dto.contentType.trim().toLowerCase();
    if (!this.config.attachmentAllowedMimeTypes.includes(normalizedMime)) {
      throw badRequest(
        'attachment_upload_invalid',
        'Attachment MIME type is not allowed for this relay',
      );
    }
    if (dto.sizeBytes > this.config.attachmentMaxBytes) {
      throw badRequest(
        'attachment_upload_invalid',
        'Attachment size exceeds the current relay limit',
      );
    }
  }

  private async cleanupExpiredPendingUploads(deviceId: string): Promise<void> {
    const cutoff = new Date(Date.now() - 15 * 60 * 1000);
    const expiredPending = await this.prisma.attachment.findMany({
      where: {
        uploaderDeviceId: deviceId,
        uploadStatus: 'pending',
        createdAt: {
          lt: cutoff,
        },
      },
      select: {
        id: true,
        storageKey: true,
      },
    });

    for (const attachment of expiredPending) {
      await this.storageGateway.deleteObject(attachment.storageKey);
      await this.prisma.attachment.update({
        where: { id: attachment.id },
        data: { uploadStatus: 'failed' },
      });
    }
  }
}
