import { AccountService } from './account.service';

// Destructive-cascade spec. Phase L split deleteAccount into three phases:
//
//   Phase 1 (small tx): user.update(status=revoked, activeDeviceId=null)
//                       + device.updateMany(isActive=false)
//   Phase 2 (no tx):    chunked deleteMany on the bulky child tables, in
//                       Restrict-FK-respecting order.
//   Phase 3 (small tx): deviceTransferSession + userProfile cleanup, then
//                       device.deleteMany + user.delete.
//
// These tests use jest.fn() mocks so we can verify the high-level contract
// without wiring up every model. The Restrict-ordering invariant is the key
// correctness property to preserve from the previous single-transaction
// implementation.

type StepName =
  | 'phase1.user.update'
  | 'phase1.device.updateMany'
  | 'phase2.message.deleteMany'
  | 'phase2.attachment.deleteMany'
  | 'phase2.callRecord.deleteMany'
  | 'phase2.messageReceipt.deleteMany'
  | 'phase2.reaction.deleteMany'
  | 'phase2.storyView.deleteMany'
  | 'phase2.story.deleteMany'
  | 'phase2.userContact.deleteMany'
  | 'phase2.conversationMember.deleteMany'
  | 'phase2.conversation.deleteMany'
  | 'phase3.deviceTransferSession.deleteMany'
  | 'phase3.userProfile.deleteMany'
  | 'phase3.user.update'
  | 'phase3.device.deleteMany'
  | 'phase3.user.delete';

function buildPrismaMock(opts?: {
  deviceIds?: string[];
  ownedGroupConversationIds?: string[];
  ownedChannelConversationIds?: string[];
}) {
  const order: StepName[] = [];
  const deviceIds = opts?.deviceIds ?? ['device-1'];
  const ownedGroups = opts?.ownedGroupConversationIds ?? [];
  const ownedChannels = opts?.ownedChannelConversationIds ?? [];

  // Each call site records its label so the spec can assert the ordering.
  const record =
    (label: StepName) =>
    (...args: unknown[]): { count: number } => {
      order.push(label);
      void args;
      return { count: 0 };
    };

  const transactionFn = jest.fn(async (cb: (tx: any) => Promise<unknown>) => {
    const tx = {
      user: {
        update: jest.fn(record('phase1.user.update')),
      },
      device: {
        updateMany: jest.fn(record('phase1.device.updateMany')),
        deleteMany: jest.fn(record('phase3.device.deleteMany')),
      },
      deviceTransferSession: { deleteMany: jest.fn(record('phase3.deviceTransferSession.deleteMany')) },
      userProfile: { deleteMany: jest.fn(record('phase3.userProfile.deleteMany')) },
    };
    // First call: Phase 1 only sees user.update + device.updateMany.
    // Final call: Phase 3 sees deviceTransferSession + userProfile + user
    //             update + device.deleteMany + user.delete.
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
    attachment: { deleteMany: jest.fn(record('phase2.attachment.deleteMany')) },
    callRecord: { deleteMany: jest.fn(record('phase2.callRecord.deleteMany')) },
    messageReceipt: { deleteMany: jest.fn(record('phase2.messageReceipt.deleteMany')) },
    reaction: { deleteMany: jest.fn(record('phase2.reaction.deleteMany')) },
    storyView: { deleteMany: jest.fn(record('phase2.storyView.deleteMany')) },
    story: { deleteMany: jest.fn(record('phase2.story.deleteMany')) },
    userContact: { deleteMany: jest.fn(record('phase2.userContact.deleteMany')) },
    conversationMember: { deleteMany: jest.fn(record('phase2.conversationMember.deleteMany')) },
    conversation: { deleteMany: jest.fn(record('phase2.conversation.deleteMany')) },
  };

  return { prisma, order };
}

function buildService(prismaMock: ReturnType<typeof buildPrismaMock>['prisma']) {
  return new AccountService(prismaMock as never);
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

  it('finishes by deleting the user row inside the final transaction', async () => {
    const { prisma, order } = buildPrismaMock();
    await buildService(prisma).deleteAccount(userId);
    expect(order[order.length - 1]).toBe('phase3.user.delete');
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
  });
});
