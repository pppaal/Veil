import { randomUUID } from 'node:crypto';

import {
  MESSAGE_MAX_AGE_DAYS,
  RetentionService,
} from '../../src/modules/retention/retention.service';
import { RetentionFakePrismaService } from '../support/fake-prisma-retention';
import { FakeAttachmentStorageGateway } from '../support/fake-services';

const DAY_MS = 24 * 60 * 60 * 1000;
const ago = (ms: number) => new Date(Date.now() - ms);

function setup(config = { callRecordRetentionDays: 30, prekeyConsumedRetentionDays: 7 }) {
  const prisma = new RetentionFakePrismaService();
  const storage = new FakeAttachmentStorageGateway();
  const logs: Array<{ level: string; event: string; meta: Record<string, unknown> }> = [];
  const logger = {
    info: (event: string, meta: Record<string, unknown> = {}) =>
      logs.push({ level: 'info', event, meta }),
    warn: (event: string, meta: Record<string, unknown> = {}) =>
      logs.push({ level: 'warn', event, meta }),
    error: (event: string, meta: Record<string, unknown> = {}) =>
      logs.push({ level: 'error', event, meta }),
  };
  const service = new RetentionService(
    prisma as never,
    config as never,
    logger as never,
    storage as never,
  );

  let order = 0;
  const addMessage = async (
    overrides: {
      expiresAt?: Date | null;
      serverReceivedAt?: Date;
      attachmentId?: string | null;
      deletedAt?: Date | null;
    } = {},
  ) => {
    order += 1;
    const created = await prisma.message.create({
      data: {
        conversationId: 'conversation-1',
        senderDeviceId: 'device-1',
        clientMessageId: randomUUID(),
        conversationOrder: order,
        ciphertext: 'ciphertext',
        nonce: 'nonce',
        messageType: 'text',
        attachmentId: overrides.attachmentId ?? null,
        attachmentRef: overrides.attachmentId ? { attachmentId: overrides.attachmentId } : null,
        expiresAt: overrides.expiresAt ?? null,
      },
    });
    const stored = prisma.messages.find((message) => message.id === created.id)!;
    stored.serverReceivedAt = overrides.serverReceivedAt ?? stored.serverReceivedAt;
    stored.deletedAt = overrides.deletedAt ?? null;
    return stored;
  };

  const addAttachment = async (
    overrides: { createdAt?: Date; uploadStatus?: 'pending' | 'uploaded' | 'failed' } = {},
  ) => {
    const storageKey = `attachments/${randomUUID()}/${randomUUID()}`;
    const created = await prisma.attachment.create({
      data: {
        uploaderDeviceId: 'device-1',
        storageKey,
        contentType: 'application/octet-stream',
        sizeBytes: 10,
        sha256: 'a'.repeat(64),
        uploadStatus: overrides.uploadStatus ?? 'uploaded',
      },
    });
    const stored = prisma.attachments.find((attachment) => attachment.id === created.id)!;
    stored.createdAt = overrides.createdAt ?? stored.createdAt;
    storage.recordUploaded(storageKey, {
      sizeBytes: 10,
      contentType: 'application/octet-stream',
      metadata: {},
    });
    return stored;
  };

  const addCall = (
    status: 'ringing' | 'active' | 'ended' | 'missed' | 'declined',
    startedAt: Date,
  ) => {
    const call = {
      id: randomUUID(),
      conversationId: 'conversation-1',
      initiatorDeviceId: 'device-1',
      callType: 'voice' as const,
      status,
      startedAt,
      endedAt: null,
      duration: null,
    };
    prisma.callRecords.push(call);
    return call;
  };

  const sweptCounts = () => logs.find((log) => log.event === 'retention.swept')?.meta ?? {};

  return { prisma, storage, logs, service, addMessage, addAttachment, addCall, sweptCounts };
}

describe('RetentionService locking and batching', () => {
  it('takes the transaction-scoped advisory lock for every batch', async () => {
    const { prisma, service, addMessage } = setup();
    await addMessage({ expiresAt: ago(1000) });

    await service.sweep();

    expect(prisma.rawQueries.length).toBeGreaterThan(0);
    for (const query of prisma.rawQueries) {
      expect(query).toContain("pg_try_advisory_xact_lock(hashtext('veil-retention'))");
    }
  });

  it('sweep skipped when advisory lock not acquired', async () => {
    const { prisma, service, logs, addMessage, addAttachment, addCall } = setup();
    await addMessage({ expiresAt: ago(1000) });
    await addAttachment({ createdAt: ago(2 * DAY_MS) });
    addCall('ringing', ago(10 * 60 * 1000));
    prisma.retentionLockAvailable = false;

    await service.sweep();

    expect(prisma.messages).toHaveLength(1);
    expect(prisma.attachments).toHaveLength(1);
    expect(prisma.callRecords[0].status).toBe('ringing');
    expect(prisma.rawQueries).toHaveLength(1);
    expect(logs.map((log) => log.event)).toEqual(['retention.lock_held']);
  });

  it('2500 expired messages deleted in 3 batches', async () => {
    const { prisma, service, addMessage, sweptCounts } = setup();
    for (let index = 0; index < 2500; index += 1) {
      await addMessage({ expiresAt: ago(1000) });
    }
    const deleteMany = jest.spyOn(prisma.message, 'deleteMany');

    await service.sweep();

    expect(prisma.messages).toHaveLength(0);
    expect(deleteMany.mock.calls.map(([args]) => args.where.id.in.length)).toEqual([
      1000, 1000, 500,
    ]);
    expect(sweptCounts()).toMatchObject({ expiredMessages: 2500 });
  });

  it('processes at most 20 batches per sweep per tick', async () => {
    const { prisma, service, addMessage } = setup();
    for (let index = 0; index < 20_500; index += 1) {
      await addMessage({ expiresAt: ago(1000) });
    }

    await service.sweep();
    expect(prisma.messages).toHaveLength(500);

    await service.sweep();
    expect(prisma.messages).toHaveLength(0);
  });

  it('a failing sweep is logged by kind and the others still run', async () => {
    const { prisma, service, logs, addCall } = setup();
    jest
      .spyOn(prisma.story, 'findMany')
      .mockRejectedValue(new Error('stories table offline for 3f6c-user-id'));
    addCall('ringing', ago(5 * 60 * 1000));

    await expect(service.sweep()).resolves.toBeUndefined();

    expect(logs).toContainEqual({
      level: 'warn',
      event: 'retention.sweep_failed',
      meta: { sweep: 'expiredStories', error: 'Error' },
    });
    expect(JSON.stringify(logs)).not.toContain('3f6c');
    expect(prisma.callRecords[0].status).toBe('missed');
  });
});

describe('RetentionService message sweeps', () => {
  it('expired message attachment blob deleted immediately when unreferenced', async () => {
    const { prisma, storage, service, addMessage, addAttachment } = setup();
    const attachment = await addAttachment();
    await addMessage({ expiresAt: ago(1000), attachmentId: attachment.id });

    await service.sweep();

    expect(prisma.messages).toHaveLength(0);
    expect(prisma.attachments).toHaveLength(0);
    expect(storage.uploaded.has(attachment.storageKey)).toBe(false);
  });

  it('keeps an attachment another live message still references', async () => {
    const { prisma, storage, service, addMessage, addAttachment } = setup();
    const attachment = await addAttachment();
    await addMessage({ expiresAt: ago(1000), attachmentId: attachment.id });
    const survivor = await addMessage({ attachmentId: attachment.id });

    await service.sweep();

    expect(prisma.messages.map((message) => message.id)).toEqual([survivor.id]);
    expect(prisma.attachments).toHaveLength(1);
    expect(storage.uploaded.has(attachment.storageKey)).toBe(true);
  });

  it('keeps the attachment row when its blob delete fails, for a later retry', async () => {
    const { prisma, storage, service, addMessage, addAttachment } = setup();
    const attachment = await addAttachment();
    await addMessage({ expiresAt: ago(1000), attachmentId: attachment.id });
    storage.deleteObject = async () => {
      throw new Error('storage unavailable');
    };

    await service.sweep();

    expect(prisma.messages).toHaveLength(0);
    expect(prisma.attachments.map((row) => row.id)).toEqual([attachment.id]);
  });

  it('31-day-old message deleted regardless of expiresAt', async () => {
    const { prisma, service, addMessage, sweptCounts } = setup();
    await addMessage({ serverReceivedAt: ago(31 * DAY_MS), expiresAt: null });
    await addMessage({
      serverReceivedAt: ago(31 * DAY_MS),
      expiresAt: new Date(Date.now() + 365 * DAY_MS),
    });
    const recent = await addMessage({ serverReceivedAt: ago(29 * DAY_MS) });

    await service.sweep();

    expect(MESSAGE_MAX_AGE_DAYS).toBe(30);
    expect(prisma.messages.map((message) => message.id)).toEqual([recent.id]);
    expect(sweptCounts()).toMatchObject({ agedMessages: 2 });
  });
});

describe('RetentionService metadata sweeps', () => {
  it('ringing call older than 90s becomes missed', async () => {
    const { service, addCall } = setup();
    const stale = addCall('ringing', ago(91 * 1000));
    const fresh = addCall('ringing', ago(30 * 1000));

    await service.sweep();

    expect(stale.status).toBe('missed');
    expect(stale.endedAt).toBeInstanceOf(Date);
    expect(fresh.status).toBe('ringing');
    expect(fresh.endedAt).toBeNull();
  });

  it('active older than 12h becomes ended', async () => {
    const { service, addCall } = setup();
    const stale = addCall('active', ago(12 * 60 * 60 * 1000 + 60_000));
    const live = addCall('active', ago(60 * 60 * 1000));

    await service.sweep();

    expect(stale.status).toBe('ended');
    expect(stale.endedAt).toBeInstanceOf(Date);
    expect(live.status).toBe('active');
  });

  it('prunes terminal calls past the retention window, including stale ones it just closed', async () => {
    const { prisma, service, addCall } = setup({
      callRecordRetentionDays: 30,
      prekeyConsumedRetentionDays: 7,
    });
    addCall('ended', ago(31 * DAY_MS));
    addCall('ringing', ago(31 * DAY_MS));
    const recent = addCall('declined', ago(DAY_MS));

    await service.sweep();

    expect(prisma.callRecords.map((call) => call.id)).toEqual([recent.id]);
  });

  it('keeps terminal calls when call retention is disabled', async () => {
    const { prisma, service, addCall } = setup({
      callRecordRetentionDays: 0,
      prekeyConsumedRetentionDays: 7,
    });
    addCall('ended', ago(400 * DAY_MS));

    await service.sweep();

    expect(prisma.callRecords).toHaveLength(1);
  });

  it('receipt read 8 days ago deleted', async () => {
    const { prisma, service } = setup();
    const receipt = (deliveredAt: Date | null, readAt: Date | null) => ({
      id: randomUUID(),
      messageId: randomUUID(),
      userId: 'user-1',
      deliveredAt,
      readAt,
    });
    const readLongAgo = receipt(ago(9 * DAY_MS), ago(8 * DAY_MS));
    const readRecently = receipt(ago(6 * DAY_MS), ago(6 * DAY_MS));
    const unreadOld = receipt(ago(31 * DAY_MS), null);
    const unreadRecent = receipt(ago(29 * DAY_MS), null);
    prisma.messageReceipts.push(readLongAgo, readRecently, unreadOld, unreadRecent);

    await service.sweep();

    expect(prisma.messageReceipts.map((row) => row.id)).toEqual([readRecently.id, unreadRecent.id]);
  });

  it('report 91 days old deleted', async () => {
    const { prisma, service } = setup();
    const report = (createdAt: Date) => ({
      id: randomUUID(),
      reporterUserId: 'user-1',
      reportedUserId: 'user-2',
      conversationId: null,
      messageId: null,
      reason: 'spam',
      note: null,
      createdAt,
    });
    const old = report(ago(91 * DAY_MS));
    const recent = report(ago(89 * DAY_MS));
    prisma.abuseReports.push(old, recent);

    await service.sweep();

    expect(prisma.abuseReports.map((row) => row.id)).toEqual([recent.id]);
  });

  it('expired story and views deleted', async () => {
    const { prisma, service } = setup();
    const story = (expiresAt: Date) => ({
      id: randomUUID(),
      userId: 'user-1',
      contentType: 'text' as const,
      contentUrl: 'text://inline',
      caption: null,
      expiresAt,
      viewCount: 0,
      createdAt: new Date(expiresAt.getTime() - DAY_MS),
    });
    const expired = story(ago(1000));
    const live = story(new Date(Date.now() + 60_000));
    prisma.stories.push(expired, live);
    prisma.storyViews.push(
      { id: randomUUID(), storyId: expired.id, viewerUserId: 'user-2', viewedAt: new Date() },
      { id: randomUUID(), storyId: live.id, viewerUserId: 'user-2', viewedAt: new Date() },
    );

    await service.sweep();

    expect(prisma.stories.map((row) => row.id)).toEqual([live.id]);
    expect(prisma.storyViews.map((row) => row.storyId)).toEqual([live.id]);
  });

  it('prunes consumed prekeys past their window and never unconsumed ones', async () => {
    const { prisma, service } = setup();
    const prekey = (keyId: number, consumedAt: Date | null) => ({
      id: randomUUID(),
      deviceId: 'device-1',
      keyId,
      publicKey: `opk-${keyId}`,
      consumedAt,
      createdAt: ago(100 * DAY_MS),
    });
    prisma.oneTimePrekeys.push(prekey(1, ago(8 * DAY_MS)), prekey(2, ago(DAY_MS)), prekey(3, null));

    await service.sweep();

    expect(prisma.oneTimePrekeys.map((row) => row.keyId)).toEqual([2, 3]);
  });

  it('prunes expired secret blobs', async () => {
    const { prisma, service } = setup();
    prisma.secretBlobs.push(
      { id: 'expired', ciphertext: 'c', createdAt: ago(DAY_MS), expiresAt: ago(1000) },
      {
        id: 'live',
        ciphertext: 'c',
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + DAY_MS),
      },
    );

    await service.sweep();

    expect(prisma.secretBlobs.map((row) => row.id)).toEqual(['live']);
  });
});

describe('RetentionService attachment sweep', () => {
  it('orphan uploaded attachment: deleteObject then row', async () => {
    const { prisma, storage, service, addAttachment } = setup();
    const orphan = await addAttachment({ createdAt: ago(25 * 60 * 60 * 1000) });
    const rowPresentDuringDelete: boolean[] = [];
    const deleteObject = storage.deleteObject.bind(storage);
    storage.deleteObject = async (storageKey: string) => {
      rowPresentDuringDelete.push(prisma.attachments.some((row) => row.storageKey === storageKey));
      await deleteObject(storageKey);
    };

    await service.sweep();

    expect(rowPresentDuringDelete).toEqual([true]);
    expect(storage.uploaded.has(orphan.storageKey)).toBe(false);
    expect(prisma.attachments).toHaveLength(0);
  });

  it('sweeps abandoned pending and failed uploads but respects the 24h grace period', async () => {
    const { prisma, service, addAttachment } = setup();
    await addAttachment({ uploadStatus: 'pending', createdAt: ago(25 * 60 * 60 * 1000) });
    await addAttachment({ uploadStatus: 'failed', createdAt: ago(25 * 60 * 60 * 1000) });
    const fresh = await addAttachment({ createdAt: ago(23 * 60 * 60 * 1000) });

    await service.sweep();

    expect(prisma.attachments.map((row) => row.id)).toEqual([fresh.id]);
  });

  it('keeps old attachments that a live message references', async () => {
    const { prisma, service, addMessage, addAttachment } = setup();
    const attachment = await addAttachment({ createdAt: ago(5 * DAY_MS) });
    await addMessage({ attachmentId: attachment.id });

    await service.sweep();

    expect(prisma.attachments).toHaveLength(1);
  });

  it('releases a blob whose only reference is a delete-for-everyone tombstone', async () => {
    const { prisma, storage, service, addMessage, addAttachment } = setup();
    const attachment = await addAttachment({ createdAt: ago(25 * 60 * 60 * 1000) });
    const tombstone = await addMessage({ attachmentId: attachment.id, deletedAt: ago(1000) });

    await service.sweep();

    expect(storage.uploaded.has(attachment.storageKey)).toBe(false);
    expect(prisma.attachments).toHaveLength(0);
    expect(prisma.messages.map((message) => message.id)).toEqual([tombstone.id]);
  });
});

describe('RetentionService logging', () => {
  it('logs contain counts only', async () => {
    const { prisma, service, logs, addMessage, addAttachment, addCall } = setup();
    const attachment = await addAttachment();
    await addMessage({ expiresAt: ago(1000), attachmentId: attachment.id });
    await addMessage({ serverReceivedAt: ago(40 * DAY_MS) });
    addCall('ringing', ago(5 * 60 * 1000));
    prisma.abuseReports.push({
      id: randomUUID(),
      reporterUserId: 'reporter-7b1e',
      reportedUserId: 'reported-91aa',
      conversationId: null,
      messageId: null,
      reason: 'spam',
      note: null,
      createdAt: ago(100 * DAY_MS),
    });

    await service.sweep();

    expect(logs).toHaveLength(1);
    const [summary] = logs;
    expect(summary.event).toBe('retention.swept');
    expect(Object.values(summary.meta).every((value) => typeof value === 'number')).toBe(true);
    expect(summary.meta).toMatchObject({
      expiredMessages: 1,
      agedMessages: 1,
      missedCalls: 1,
      abuseReports: 1,
      attachmentBlobs: 1,
    });
    expect(JSON.stringify(logs)).not.toMatch(
      new RegExp(
        `${attachment.id}|${attachment.storageKey}|reporter-7b1e|reported-91aa|conversation-1|device-1`,
      ),
    );
  });

  it('logs nothing when there was nothing to sweep', async () => {
    const { service, logs } = setup();
    await service.sweep();
    expect(logs).toEqual([]);
  });
});
