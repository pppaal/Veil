import { randomUUID } from 'node:crypto';

import { Prisma } from '@prisma/client';

import { AttachmentsService } from './attachments.service';
import { RetentionFakePrismaService } from '../../../test/support/fake-prisma-retention';
import {
  FakeAttachmentStorageGateway,
  FakeConfigService,
} from '../../../test/support/fake-services';

function seedDeviceAndUser(prisma: RetentionFakePrismaService): {
  userId: string;
  deviceId: string;
} {
  const userId = randomUUID();
  const deviceId = randomUUID();
  prisma.users.push({
    id: userId,
    handle: 'tester',
    displayName: 'Tester',
    avatarPath: null,
    status: 'active',
    activeDeviceId: deviceId,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  prisma.devices.push({
    id: deviceId,
    userId,
    platform: 'ios',
    deviceName: 'Test',
    publicIdentityKey: 'pub-id',
    signedPrekeyBundle: 'prekey',
    authPublicKey: 'auth-pub',
    pushToken: null,
    isActive: true,
    revokedAt: null,
    trustedAt: new Date(),
    joinedFromDeviceId: null,
    createdAt: new Date(),
    lastSeenAt: new Date(),
    lastSyncAt: null,
  });
  return { userId, deviceId };
}

function makeService(): {
  service: AttachmentsService;
  prisma: RetentionFakePrismaService;
  storage: FakeAttachmentStorageGateway;
  config: FakeConfigService;
  metrics: { attachmentsBytesTotal: { inc: jest.Mock } };
} {
  const prisma = new RetentionFakePrismaService();
  const config = new FakeConfigService();
  const storage = new FakeAttachmentStorageGateway();
  const metrics = { attachmentsBytesTotal: { inc: jest.fn() } };
  const service = new AttachmentsService(
    prisma as never,
    config as never,
    storage as never,
    metrics as never,
  );
  return { service, prisma, storage, config, metrics };
}

describe('AttachmentsService', () => {
  describe('createUploadTicket', () => {
    it('issues a signed upload ticket and records a pending attachment', async () => {
      const { service, prisma } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);

      const ticket = await service.createUploadTicket(deviceId, {
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });

      expect(ticket.attachmentId).toBeTruthy();
      expect(ticket.upload.uploadUrl).toContain('signed-upload.invalid');
      expect(ticket.upload.headers['x-amz-meta-sha256']).toBe('a'.repeat(64));
      expect(prisma.attachments).toHaveLength(1);
      expect(prisma.attachments[0].uploadStatus).toBe('pending');
    });

    it('storageKey has no deviceId', async () => {
      const { service, prisma } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);

      const ticket = await service.createUploadTicket(deviceId, {
        contentType: 'image/png',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });

      expect(ticket.upload.storageKey).not.toContain(deviceId);
      expect(ticket.upload.storageKey).toMatch(/^attachments\/[0-9a-f-]{36}\/[0-9a-f-]{36}$/);
      expect(prisma.attachments[0].storageKey).toBe(ticket.upload.storageKey);
    });

    it('stored contentType is application/octet-stream', async () => {
      const { service, prisma } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);

      const ticket = await service.createUploadTicket(deviceId, {
        contentType: 'image/png',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });

      expect(prisma.attachments[0].contentType).toBe('application/octet-stream');
      expect(ticket.upload.contentType).toBe('application/octet-stream');
      // The client uploads with the ticket headers, so storage only sees ciphertext.
      expect(ticket.upload.headers['Content-Type']).toBe('application/octet-stream');
    });

    it('rejects disallowed MIME types', async () => {
      const { service, prisma } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);

      await expect(
        service.createUploadTicket(deviceId, {
          contentType: 'text/html',
          sizeBytes: 1024,
          sha256: 'a'.repeat(64),
        }),
      ).rejects.toThrow('MIME type is not allowed');
      expect(prisma.attachments).toHaveLength(0);
    });

    it('rejects oversized uploads', async () => {
      const { service, prisma, config } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);

      await expect(
        service.createUploadTicket(deviceId, {
          contentType: 'application/octet-stream',
          sizeBytes: config.attachmentMaxBytes + 1,
          sha256: 'a'.repeat(64),
        }),
      ).rejects.toThrow('size exceeds the current relay limit');
    });

    it('cleans up expired pending uploads before issuing a new ticket', async () => {
      const { service, prisma, storage } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);

      const staleKey = `attachments/${deviceId}/${randomUUID()}`;
      prisma.attachments.push({
        id: randomUUID(),
        uploaderDeviceId: deviceId,
        storageKey: staleKey,
        contentType: 'application/octet-stream',
        sizeBytes: 10,
        sha256: 'b'.repeat(64),
        uploadStatus: 'pending',
        createdAt: new Date(Date.now() - 30 * 60 * 1000),
      });
      storage.uploaded.set(staleKey, {
        sizeBytes: 10,
        contentType: 'application/octet-stream',
        metadata: {},
      });

      await service.createUploadTicket(deviceId, {
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });

      const stale = prisma.attachments.find((a) => a.storageKey === staleKey)!;
      expect(stale.uploadStatus).toBe('failed');
      expect(storage.uploaded.has(staleKey)).toBe(false);
    });
  });

  describe('completeUpload', () => {
    it('marks a correctly-uploaded blob as uploaded after HEAD validation', async () => {
      const { service, prisma, storage, metrics } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);

      const ticket = await service.createUploadTicket(deviceId, {
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });
      const storageKey = prisma.attachments[0].storageKey;
      storage.recordUploaded(storageKey, {
        sizeBytes: 1024,
        contentType: 'application/octet-stream',
        metadata: {
          encrypted: 'true',
          sha256: 'a'.repeat(64),
          'attachment-id': ticket.attachmentId,
        },
      });

      const result = await service.completeUpload(deviceId, {
        attachmentId: ticket.attachmentId,
        uploadStatus: 'uploaded',
      });

      expect(result.uploadStatus).toBe('uploaded');
      expect(prisma.attachments[0].uploadStatus).toBe('uploaded');
      // Accepted ciphertext bytes counted once.
      expect(metrics.attachmentsBytesTotal.inc).toHaveBeenCalledWith(1024);
    });

    it('rejects completion if the blob is missing from storage', async () => {
      const { service, prisma } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);
      const ticket = await service.createUploadTicket(deviceId, {
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });

      await expect(
        service.completeUpload(deviceId, {
          attachmentId: ticket.attachmentId,
          uploadStatus: 'uploaded',
        }),
      ).rejects.toThrow('missing from object storage');
    });

    it('rejects completion if the blob sha256 metadata does not match', async () => {
      const { service, prisma, storage } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);
      const ticket = await service.createUploadTicket(deviceId, {
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });
      const storageKey = prisma.attachments[0].storageKey;
      storage.recordUploaded(storageKey, {
        sizeBytes: 1024,
        contentType: 'application/octet-stream',
        metadata: {
          encrypted: 'true',
          sha256: 'f'.repeat(64),
          'attachment-id': ticket.attachmentId,
        },
      });

      await expect(
        service.completeUpload(deviceId, {
          attachmentId: ticket.attachmentId,
          uploadStatus: 'uploaded',
        }),
      ).rejects.toThrow('hash metadata does not match');
    });

    it('rejects completion if size mismatches the ticket', async () => {
      const { service, prisma, storage } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);
      const ticket = await service.createUploadTicket(deviceId, {
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });
      const storageKey = prisma.attachments[0].storageKey;
      storage.recordUploaded(storageKey, {
        sizeBytes: 2048,
        contentType: 'application/octet-stream',
        metadata: {
          encrypted: 'true',
          sha256: 'a'.repeat(64),
          'attachment-id': ticket.attachmentId,
        },
      });

      await expect(
        service.completeUpload(deviceId, {
          attachmentId: ticket.attachmentId,
          uploadStatus: 'uploaded',
        }),
      ).rejects.toThrow('size does not match');
    });

    it('forbids completing an attachment owned by a different device', async () => {
      const { service, prisma } = makeService();
      const owner = seedDeviceAndUser(prisma);
      const otherDeviceId = randomUUID();
      prisma.devices.push({
        id: otherDeviceId,
        userId: randomUUID(),
        platform: 'ios',
        deviceName: 'Imposter',
        publicIdentityKey: 'x',
        signedPrekeyBundle: 'x',
        authPublicKey: 'x',
        pushToken: null,
        isActive: true,
        revokedAt: null,
        trustedAt: new Date(),
        joinedFromDeviceId: null,
        createdAt: new Date(),
        lastSeenAt: new Date(),
        lastSyncAt: null,
      });

      const ticket = await service.createUploadTicket(owner.deviceId, {
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });

      await expect(
        service.completeUpload(otherDeviceId, {
          attachmentId: ticket.attachmentId,
          uploadStatus: 'uploaded',
        }),
      ).rejects.toThrow('does not belong to device');
    });

    it('removes the blob and marks the record failed when the client reports failure', async () => {
      const { service, prisma, storage } = makeService();
      const { deviceId } = seedDeviceAndUser(prisma);
      const ticket = await service.createUploadTicket(deviceId, {
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });
      const storageKey = prisma.attachments[0].storageKey;
      storage.recordUploaded(storageKey, {
        sizeBytes: 1024,
        contentType: 'application/octet-stream',
        metadata: {},
      });

      await service.completeUpload(deviceId, {
        attachmentId: ticket.attachmentId,
        uploadStatus: 'failed',
      });

      expect(storage.uploaded.has(storageKey)).toBe(false);
      expect(prisma.attachments[0].uploadStatus).toBe('failed');
    });
  });

  describe('createDownloadTicket', () => {
    async function uploadedAttachment() {
      const context = makeService();
      const uploader = seedDeviceAndUser(context.prisma);
      const ticket = await context.service.createUploadTicket(uploader.deviceId, {
        contentType: 'image/png',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });
      context.storage.recordUploaded(context.prisma.attachments[0].storageKey, {
        sizeBytes: 1024,
        contentType: 'application/octet-stream',
        metadata: {
          encrypted: 'true',
          sha256: 'a'.repeat(64),
          'attachment-id': ticket.attachmentId,
        },
      });
      await context.service.completeUpload(uploader.deviceId, {
        attachmentId: ticket.attachmentId,
        uploadStatus: 'uploaded',
      });
      return { ...context, uploader, attachmentId: ticket.attachmentId };
    }

    async function sendInConversation(
      prisma: RetentionFakePrismaService,
      senderDeviceId: string,
      memberUserIds: string[],
      attachmentId: string,
      overrides: { expiresAt?: Date | null } = {},
    ) {
      const conversationId = await prisma.addConversation('direct', memberUserIds);
      return prisma.message.create({
        data: {
          conversationId,
          senderDeviceId,
          clientMessageId: randomUUID(),
          conversationOrder: 1,
          ciphertext: 'ciphertext',
          nonce: 'nonce',
          messageType: 'image',
          attachmentId,
          attachmentRef: { attachmentId },
          expiresAt: overrides.expiresAt ?? null,
        },
      });
    }

    it('issues a signed download URL to a member of a conversation with a live message', async () => {
      const { service, prisma, uploader, attachmentId } = await uploadedAttachment();
      const recipient = seedDeviceAndUser(prisma);
      await sendInConversation(
        prisma,
        uploader.deviceId,
        [uploader.userId, recipient.userId],
        attachmentId,
      );

      for (const member of [recipient, uploader]) {
        const result = await service.createDownloadTicket(member, attachmentId);
        expect(result.ticket.downloadUrl).toContain('signed-download.invalid');
      }
    });

    it('does not authorize the uploader by upload alone', async () => {
      const { service, uploader, attachmentId } = await uploadedAttachment();

      await expect(service.createDownloadTicket(uploader, attachmentId)).rejects.toThrow(
        'not accessible to actor',
      );
    });

    it('rejects download for a non-member of the conversation', async () => {
      const { service, prisma, uploader, attachmentId } = await uploadedAttachment();
      const recipient = seedDeviceAndUser(prisma);
      const stranger = seedDeviceAndUser(prisma);
      await sendInConversation(
        prisma,
        uploader.deviceId,
        [uploader.userId, recipient.userId],
        attachmentId,
      );

      await expect(service.createDownloadTicket(stranger, attachmentId)).rejects.toThrow(
        'not accessible to actor',
      );
    });

    it('download ticket denied after delete-for-everyone', async () => {
      const { service, prisma, uploader, attachmentId } = await uploadedAttachment();
      const recipient = seedDeviceAndUser(prisma);
      const message = await sendInConversation(
        prisma,
        uploader.deviceId,
        [uploader.userId, recipient.userId],
        attachmentId,
      );
      await expect(service.createDownloadTicket(recipient, attachmentId)).resolves.toBeDefined();

      // Mirrors MessagesService.delete: tombstone, keep attachmentId, null the ref.
      await prisma.message.update({
        where: { id: message.id },
        data: {
          deletedAt: new Date(),
          ciphertext: 'deleted',
          nonce: 'deleted',
          attachmentRef: Prisma.JsonNull,
        },
      });

      await expect(service.createDownloadTicket(recipient, attachmentId)).rejects.toThrow(
        'not accessible to actor',
      );
    });

    it('denied after expiry', async () => {
      const { service, prisma, uploader, attachmentId } = await uploadedAttachment();
      const recipient = seedDeviceAndUser(prisma);
      await sendInConversation(
        prisma,
        uploader.deviceId,
        [uploader.userId, recipient.userId],
        attachmentId,
        { expiresAt: new Date(Date.now() - 1000) },
      );

      await expect(service.createDownloadTicket(recipient, attachmentId)).rejects.toThrow(
        'not accessible to actor',
      );
    });

    it('allows a disappearing message that has not expired yet', async () => {
      const { service, prisma, uploader, attachmentId } = await uploadedAttachment();
      const recipient = seedDeviceAndUser(prisma);
      await sendInConversation(
        prisma,
        uploader.deviceId,
        [uploader.userId, recipient.userId],
        attachmentId,
        { expiresAt: new Date(Date.now() + 60_000) },
      );

      await expect(service.createDownloadTicket(recipient, attachmentId)).resolves.toBeDefined();
    });

    it('rejects download when the attachment has not finished uploading', async () => {
      const { service, prisma } = makeService();
      const { userId, deviceId } = seedDeviceAndUser(prisma);
      const ticket = await service.createUploadTicket(deviceId, {
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
      });

      await expect(
        service.createDownloadTicket({ userId, deviceId }, ticket.attachmentId),
      ).rejects.toThrow('not available for download');
    });

    it('returns not-found for an unknown attachment id', async () => {
      const { service, prisma } = makeService();
      const { userId, deviceId } = seedDeviceAndUser(prisma);

      await expect(
        service.createDownloadTicket({ userId, deviceId }, randomUUID()),
      ).rejects.toThrow('Attachment not found');
    });
  });
});
