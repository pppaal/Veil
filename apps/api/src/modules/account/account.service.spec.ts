import { createHmac } from 'node:crypto';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { RetentionFakePrismaService } from '../../../test/support/fake-prisma-retention';
import {
  FakeAttachmentStorageGateway,
  FakeRealtimeGateway,
  FakeSafetyService,
} from '../../../test/support/fake-services';
import { ConversationsService } from '../conversations/conversations.service';
import { CreateDirectConversationDto } from '../conversations/dto/create-direct-conversation.dto';
import { RetiredHandlesService } from '../handles/retired-handles.service';
import { AccountService } from './account.service';

// Destructive-cascade spec. Phase L split deleteAccount into three phases:
//
//   Phase 1 (small tx): user.update(status=revoked, activeDeviceId=null)
//                       + device.updateMany(isActive=false)
//   Phase 2 (no tx):    chunked deleteMany on the bulky child tables, in
//                       Restrict-FK-respecting order.
//   Phase 3 (small tx): deviceTransferSession cleanup, then device.deleteMany,
//                       the handle quarantine and user.delete.
//
// These tests use jest.fn() mocks so we can verify the high-level contract
// without wiring up every model. The Restrict-ordering invariant is the key
// correctness property to preserve from the previous single-transaction
// implementation.

type StepName =
  | 'blobs.findMany'
  | 'blobs.deleteObject'
  | 'phase1.user.update'
  | 'phase1.device.updateMany'
  | 'phase2.message.deleteMany'
  | 'phase2.attachment.deleteMany'
  | 'phase2.callRecord.deleteMany'
  | 'phase2.messageReceipt.deleteMany'
  | 'phase2.storyView.deleteMany'
  | 'phase2.story.deleteMany'
  | 'phase2.userContact.deleteMany'
  | 'phase2.conversationMember.deleteMany'
  | 'phase2.conversation.deleteMany'
  | 'phase3.deviceTransferSession.deleteMany'
  | 'phase3.conversationMember.findMany'
  | 'phase3.conversation.updateMany'
  | 'phase3.conversationMember.deleteMany'
  | 'phase3.conversation.deleteMany'
  | 'phase3.user.update'
  | 'phase3.device.deleteMany'
  | 'phase3.retiredHandle.upsert'
  | 'phase3.user.delete';

const PEPPER = 'account-spec-pepper-0123456789abcdef';
const HANDLE = 'victim';

function buildPrismaMock(opts?: {
  deviceIds?: string[];
  ownedGroupConversationIds?: string[];
  ownedChannelConversationIds?: string[];
  uploadedStorageKeys?: string[];
  directConversationIds?: string[];
}) {
  const order: StepName[] = [];
  const directConversationIds = opts?.directConversationIds ?? [];
  const deviceIds = opts?.deviceIds ?? ['device-1'];
  const uploadedStorageKeys = opts?.uploadedStorageKeys ?? [];
  const ownedGroups = opts?.ownedGroupConversationIds ?? [];
  const ownedChannels = opts?.ownedChannelConversationIds ?? [];

  // Each call site records its label so the spec can assert the ordering.
  const record =
    (label: StepName) =>
    (...args: unknown[]): { count: number; handle: string } => {
      order.push(label);
      void args;
      return { count: 0, handle: HANDLE };
    };
  const upserts: Array<{ where: { handleHmac: string }; create: { retiredUntil: Date } }> = [];

  const transactionFn = jest.fn(async (cb: (tx: any) => Promise<unknown>) => {
    const tx = {
      user: {
        update: jest.fn(record('phase1.user.update')),
      },
      device: {
        updateMany: jest.fn(record('phase1.device.updateMany')),
        deleteMany: jest.fn(record('phase3.device.deleteMany')),
      },
      deviceTransferSession: {
        deleteMany: jest.fn(record('phase3.deviceTransferSession.deleteMany')),
      },
      conversationMember: {
        findMany: jest.fn(async () => {
          order.push('phase3.conversationMember.findMany');
          return directConversationIds.map((conversationId) => ({ conversationId }));
        }),
        deleteMany: jest.fn(record('phase3.conversationMember.deleteMany')),
      },
      conversation: {
        updateMany: jest.fn(record('phase3.conversation.updateMany')),
        deleteMany: jest.fn(record('phase3.conversation.deleteMany')),
      },
      retiredHandle: {
        upsert: jest.fn((args: (typeof upserts)[number]) => {
          upserts.push(args);
          return record('phase3.retiredHandle.upsert')();
        }),
      },
    };
    // First call: Phase 1 only sees user.update + device.updateMany.
    // Final call: Phase 3 sees deviceTransferSession + user update +
    //             device.deleteMany + the handle quarantine + user.delete.
    if (transactionFn.mock.calls.length === 1) {
      // Replace user.update label per phase by inspecting the call count.
      // (We just appended phase1.user.update via the closure above.)
    } else {
      // Re-bind labels for phase 3 since the same mock fn would otherwise
      // record phase1.user.update again.
      tx.user.update = jest.fn(record('phase3.user.update'));
    }
    (tx as any).user.delete = jest.fn(record('phase3.user.delete'));
    return cb(tx);
  });

  const prisma = {
    $transaction: transactionFn,
    device: {
      findMany: jest.fn().mockResolvedValue(deviceIds.map((id) => ({ id }))),
    },
    groupMeta: {
      findMany: jest.fn().mockResolvedValue(ownedGroups.map((id) => ({ conversationId: id }))),
    },
    channelMeta: {
      findMany: jest.fn().mockResolvedValue(ownedChannels.map((id) => ({ conversationId: id }))),
    },
    message: { deleteMany: jest.fn(record('phase2.message.deleteMany')) },
    attachment: {
      findMany: jest.fn(async () => {
        order.push('blobs.findMany');
        return uploadedStorageKeys.map((storageKey) => ({ storageKey }));
      }),
      deleteMany: jest.fn(record('phase2.attachment.deleteMany')),
    },
    callRecord: { deleteMany: jest.fn(record('phase2.callRecord.deleteMany')) },
    messageReceipt: { deleteMany: jest.fn(record('phase2.messageReceipt.deleteMany')) },
    storyView: { deleteMany: jest.fn(record('phase2.storyView.deleteMany')) },
    story: { deleteMany: jest.fn(record('phase2.story.deleteMany')) },
    userContact: { deleteMany: jest.fn(record('phase2.userContact.deleteMany')) },
    conversationMember: { deleteMany: jest.fn(record('phase2.conversationMember.deleteMany')) },
    conversation: { deleteMany: jest.fn(record('phase2.conversation.deleteMany')) },
  };

  return { prisma, order, upserts };
}

function buildService(
  prismaMock: ReturnType<typeof buildPrismaMock>['prisma'],
  storage: { deleteObject: (storageKey: string) => Promise<void> } = {
    deleteObject: async () => undefined,
  },
) {
  const realtimeGateway = { disconnectUser: () => 0 } as never;
  const retiredHandles = new RetiredHandlesService(
    prismaMock as never,
    { retiredHandlePepper: PEPPER } as never,
  );
  return new AccountService(prismaMock as never, realtimeGateway, storage as never, retiredHandles);
}

const userId = 'user-victim';

describe('AccountService.deleteAccount', () => {
  it('runs Phase 1 (auth revoke) before any destructive deleteMany', async () => {
    const { prisma, order } = buildPrismaMock();
    await buildService(prisma).deleteAccount(userId);

    const phase1End = Math.max(
      order.indexOf('phase1.user.update'),
      order.indexOf('phase1.device.updateMany'),
    );
    const firstDeleteMany = order.findIndex((label) => label.startsWith('phase2.'));
    expect(phase1End).toBeGreaterThanOrEqual(0);
    expect(firstDeleteMany).toBeGreaterThan(phase1End);
  });

  it('removes Restrict-gated child rows before device.deleteMany', async () => {
    const { prisma, order } = buildPrismaMock();
    await buildService(prisma).deleteAccount(userId);

    const idx = (label: StepName) => order.indexOf(label);
    expect(idx('phase2.message.deleteMany')).toBeGreaterThanOrEqual(0);
    expect(idx('phase3.device.deleteMany')).toBeGreaterThanOrEqual(0);
    expect(idx('phase2.message.deleteMany')).toBeLessThan(idx('phase3.device.deleteMany'));
    expect(idx('phase2.attachment.deleteMany')).toBeLessThan(idx('phase3.device.deleteMany'));
    expect(idx('phase2.callRecord.deleteMany')).toBeLessThan(idx('phase3.device.deleteMany'));
  });

  it('skips the device-scoped deleteMany calls when the user has no devices', async () => {
    const { prisma, order } = buildPrismaMock({ deviceIds: [] });
    await buildService(prisma).deleteAccount(userId);

    expect(order).not.toContain('phase2.message.deleteMany');
    expect(order).not.toContain('phase2.attachment.deleteMany');
    expect(order).not.toContain('phase2.callRecord.deleteMany');
    // The user-level cleanups still run.
    expect(order).toContain('phase2.messageReceipt.deleteMany');
    expect(order).toContain('phase3.user.delete');
  });

  it('cascades owned group/channel conversations when the user owned them', async () => {
    const { prisma, order } = buildPrismaMock({
      ownedGroupConversationIds: ['g-1'],
      ownedChannelConversationIds: ['c-1'],
    });
    await buildService(prisma).deleteAccount(userId);
    expect(order).toContain('phase2.conversation.deleteMany');
  });

  it('quarantines the handle for 90 days in the transaction that deletes the user', async () => {
    const { prisma, order, upserts } = buildPrismaMock();
    const before = Date.now();
    await buildService(prisma).deleteAccount(userId);

    expect(order.slice(-2)).toEqual(['phase3.retiredHandle.upsert', 'phase3.user.delete']);
    expect(upserts).toHaveLength(1);
    // Only the peppered digest is stored, never the handle itself.
    expect(upserts[0]!.where.handleHmac).toBe(
      createHmac('sha256', PEPPER).update(HANDLE).digest('hex'),
    );
    expect(JSON.stringify(upserts[0])).not.toContain(HANDLE);
    const quarantineDays = (upserts[0]!.create.retiredUntil.getTime() - before) / 86_400_000;
    expect(Math.round(quarantineDays)).toBe(90);
  });

  it('finishes by deleting the user row inside the final transaction', async () => {
    const { prisma, order } = buildPrismaMock();
    await buildService(prisma).deleteAccount(userId);
    expect(order[order.length - 1]).toBe('phase3.user.delete');
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
  });

  it('deleteAccount calls deleteObject for every uploaded key', async () => {
    const uploadedStorageKeys = ['attachments/a/1', 'attachments/b/2', 'attachments/c/3'];
    const { prisma, order } = buildPrismaMock({
      deviceIds: ['device-1', 'device-2'],
      uploadedStorageKeys,
    });
    const deleted: string[] = [];
    const storage = {
      deleteObject: async (storageKey: string) => {
        order.push('blobs.deleteObject');
        deleted.push(storageKey);
      },
    };

    await buildService(prisma, storage).deleteAccount(userId);

    expect(deleted).toEqual(uploadedStorageKeys);
    expect(prisma.attachment.findMany).toHaveBeenCalledWith({
      where: { uploaderDeviceId: { in: ['device-1', 'device-2'] } },
      select: { storageKey: true },
    });
    // Blobs go before the rows that point at them.
    expect(order.lastIndexOf('blobs.deleteObject')).toBeLessThan(
      order.indexOf('phase2.attachment.deleteMany'),
    );
  });

  it('keeps erasing when a blob delete fails', async () => {
    const { prisma, order } = buildPrismaMock({ uploadedStorageKeys: ['attachments/a/1'] });
    const storage = {
      deleteObject: async () => {
        throw new Error('storage down');
      },
    };

    await expect(buildService(prisma, storage).deleteAccount(userId)).resolves.toEqual({
      deleted: true,
    });
    expect(order[order.length - 1]).toBe('phase3.user.delete');
  });
});

// The same deletion against stored rows, with direct conversations opened by
// the real ConversationsService, so the key format is the one it writes.
describe('AccountService.deleteAccount against stored rows', () => {
  function setup() {
    const prisma = new RetentionFakePrismaService();
    const safety = new FakeSafetyService();
    const conversations = new ConversationsService(
      prisma as never,
      new FakeRealtimeGateway() as never,
      safety as never,
      new ConversationAccessService(prisma as never, safety as never),
    );
    const account = new AccountService(
      prisma as never,
      { disconnectUser: () => 0 } as never,
      new FakeAttachmentStorageGateway() as never,
      new RetiredHandlesService(prisma as never, { retiredHandlePepper: PEPPER } as never),
    );
    const addUser = async (handle: string) => {
      const id = await prisma.addUser(handle);
      await prisma.addDevice(id);
      return id;
    };
    const openDirect = async (fromUserId: string, peerHandle: string) => {
      const dto = new CreateDirectConversationDto();
      dto.peerHandle = peerHandle;
      return (await conversations.createDirect(fromUserId, dto)).conversation.id;
    };
    // Every stored row of every table the fake holds.
    const storedRows = () =>
      JSON.stringify(Object.values(prisma).filter((value) => Array.isArray(value)));
    return { prisma, account, addUser, openDirect, storedRows };
  }

  it('leaves no stored row naming the deleted user, while the peers keep their conversations', async () => {
    const { prisma, account, addUser, openDirect, storedRows } = setup();
    const alice = await addUser('alice');
    const bob = await addUser('bob');
    const carol = await addUser('carol');
    const withBob = await openDirect(alice, 'bob');
    const withCarol = await openDirect(carol, 'alice');
    expect(storedRows()).toContain(alice);

    await account.deleteAccount(alice);

    expect(storedRows()).not.toContain(alice);
    expect(prisma.conversations.map((conversation) => conversation.id).sort()).toEqual(
      [withBob, withCarol].sort(),
    );
    expect(
      prisma.conversationMembers.map((member) => [member.conversationId, member.userId]).sort(),
    ).toEqual(
      [
        [withBob, bob],
        [withCarol, carol],
      ].sort(),
    );
  });

  it('deletes a direct conversation once both of its members have deleted their accounts', async () => {
    const { prisma, account, addUser, openDirect } = setup();
    const alice = await addUser('alice');
    const bob = await addUser('bob');
    await openDirect(alice, 'bob');

    await account.deleteAccount(alice);
    await account.deleteAccount(bob);

    expect(prisma.conversations).toEqual([]);
    expect(prisma.conversationMembers).toEqual([]);
  });
});
