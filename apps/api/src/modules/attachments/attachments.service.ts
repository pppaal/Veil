import { Inject, Injectable } from '@nestjs/common';
import { Prisma, type Attachment } from '@prisma/client';
import type {
  AttachmentDownloadTicketResponse,
  CompleteAttachmentUploadResponse,
  CreateUploadTicketResponse,
} from '@veil/contracts';
import { randomUUID } from 'node:crypto';

import { PrismaService } from '../../common/prisma.service';
import { apiError, badRequest, forbidden, notFound } from '../../common/errors/api-error';
import { AppConfigService } from '../../common/config/app-config.service';
import { MetricsService } from '../metrics/metrics.service';
import {
  ATTACHMENT_STORAGE_GATEWAY,
  type AttachmentStorageGateway,
} from './attachment-storage.gateway';
import { CompleteAttachmentUploadDto, CreateUploadTicketDto } from './dto/attachment.dto';

// Every blob is ciphertext, so storage only ever sees this type; the real MIME
// type travels inside the end-to-end encrypted attachment pointer.
const STORED_ATTACHMENT_CONTENT_TYPE = 'application/octet-stream';

// Opaque on purpose: no device id, so the object store cannot group blobs by
// uploader.
const newStorageKey = (): string => `attachments/${randomUUID()}/${randomUUID()}`;

const attachmentIdConflict = () =>
  apiError('attachment_id_conflict', 'The proposed attachment id is not available');

@Injectable()
export class AttachmentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: AppConfigService,
    @Inject(ATTACHMENT_STORAGE_GATEWAY)
    private readonly storageGateway: AttachmentStorageGateway,
    private readonly metrics: MetricsService,
  ) {}

  async createUploadTicket(
    deviceId: string,
    dto: CreateUploadTicketDto,
  ): Promise<CreateUploadTicketResponse> {
    await this.cleanupExpiredPendingUploads(deviceId);
    this.assertUploadPolicy(dto);

    const attachment = dto.attachmentId
      ? await this.ticketProposedAttachment(deviceId, dto.attachmentId, dto)
      : await this.prisma.attachment.create({ data: this.pendingAttachmentData(deviceId, dto) });

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
    // The row being confirmed is judged by the HEAD check below, not by its
    // age: a PUT that started inside the ticket's window may finish long after
    // the sweep's cutoff, and sweeping it would delete the blob it confirms.
    await this.cleanupExpiredPendingUploads(deviceId, dto.attachmentId);

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
        throw badRequest(
          'attachment_upload_invalid',
          'Encrypted blob is missing from object storage',
        );
      }

      if (objectHead.sizeBytes !== attachment.sizeBytes) {
        throw badRequest(
          'attachment_upload_invalid',
          'Encrypted blob size does not match upload ticket',
        );
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
        throw badRequest(
          'attachment_upload_invalid',
          'Encrypted blob attachment binding is invalid',
        );
      }
    }

    const updated = await this.prisma.attachment.update({
      where: { id: dto.attachmentId },
      data: { uploadStatus: dto.uploadStatus },
    });

    if (dto.uploadStatus === 'uploaded') {
      // Cumulative accepted ciphertext bytes (operational throughput only —
      // no per-attachment identity). Guarded so a metrics hiccup never fails
      // an otherwise-successful upload.
      try {
        this.metrics.attachmentsBytesTotal.inc(attachment.sizeBytes);
      } catch {
        // best-effort telemetry
      }
    }

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
      throw badRequest(
        'attachment_upload_invalid',
        'Attachment blob is not available for download',
      );
    }

    // Access is granted by a live message only, never by having uploaded the
    // blob: once every referencing message is deleted for everyone, consumed
    // as view-once or expired, nobody can mint a new download URL.
    const now = new Date();
    const liveMessage = await this.prisma.message.findFirst({
      where: {
        attachmentId,
        deletedAt: null,
        attachmentRef: { not: Prisma.AnyNull },
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
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

    if (!liveMessage) {
      throw forbidden('attachment_forbidden', 'Attachment is not accessible to actor');
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

  // Protocol v2 binds the attachment id into the sealed blob's AAD, so the
  // client proposes the id before it asks for a ticket. The uploading
  // device's own unfinished row with the same ciphertext is re-issued: its
  // ticket expired or the upload failed, and with the plaintext gone the
  // same blob has to go up again under the same id.
  private async ticketProposedAttachment(
    deviceId: string,
    attachmentId: string,
    dto: CreateUploadTicketDto,
  ): Promise<Attachment> {
    const existing = await this.prisma.attachment.findUnique({ where: { id: attachmentId } });
    if (!existing) {
      try {
        return await this.prisma.attachment.create({
          data: { id: attachmentId, ...this.pendingAttachmentData(deviceId, dto) },
        });
      } catch (error) {
        if ((error as { code?: unknown } | null)?.code === 'P2002') {
          throw attachmentIdConflict();
        }
        throw error;
      }
    }

    const reissuable =
      existing.uploaderDeviceId === deviceId &&
      (existing.uploadStatus === 'pending' || existing.uploadStatus === 'failed') &&
      existing.sha256.toLowerCase() === dto.sha256.toLowerCase() &&
      existing.sizeBytes === dto.sizeBytes;
    if (!reissuable) {
      // One answer for every reason, so the caller learns nothing about who
      // holds the id or what state its blob is in.
      throw attachmentIdConflict();
    }

    const reissued = await this.prisma.attachment.update({
      where: { id: attachmentId },
      data: {
        storageKey: newStorageKey(),
        uploadStatus: 'pending',
        // The expired-pending sweep keys on createdAt; left alone, a row
        // first ticketed long ago would be swept on the next request.
        createdAt: new Date(),
      },
    });
    try {
      await this.storageGateway.deleteObject(existing.storageKey);
    } catch {
      // Best effort: nothing addresses the old key any more.
    }
    return reissued;
  }

  private pendingAttachmentData(
    deviceId: string,
    dto: CreateUploadTicketDto,
  ): Prisma.AttachmentUncheckedCreateInput {
    return {
      uploaderDeviceId: deviceId,
      storageKey: newStorageKey(),
      contentType: STORED_ATTACHMENT_CONTENT_TYPE,
      sizeBytes: dto.sizeBytes,
      sha256: dto.sha256,
      uploadStatus: 'pending',
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

  private async cleanupExpiredPendingUploads(
    deviceId: string,
    exceptAttachmentId?: string,
  ): Promise<void> {
    const cutoff = new Date(Date.now() - 15 * 60 * 1000);
    const expiredPending = await this.prisma.attachment.findMany({
      where: {
        uploaderDeviceId: deviceId,
        ...(exceptAttachmentId ? { id: { not: exceptAttachmentId } } : {}),
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
