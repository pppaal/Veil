import { AccountService } from './account.service';

// Destructive-cascade spec. The transaction runs many deleteMany calls —
// these tests use jest.fn() mocks (not FakePrismaService) so we can verify
// the exact ordering and scoping of each step without wiring up every model.

type MockTx = {
  reaction: { deleteMany: jest.Mock };
  storyView: { deleteMany: jest.Mock };
  story: { deleteMany: jest.Mock };
  messageReceipt: { deleteMany: jest.Mock };
  userContact: { deleteMany: jest.Mock };
  userProfile: { deleteMany: jest.Mock };
  conversationMember: { deleteMany: jest.Mock };
  deviceTransferSession: { deleteMany: jest.Mock };
  user: { update: jest.Mock; delete: jest.Mock };
  device: { deleteMany: jest.Mock };
};

function createTxMock(): MockTx {
  return {
    reaction: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    storyView: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    story: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    messageReceipt: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    userContact: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    userProfile: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    conversationMember: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    deviceTransferSession: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    user: {
      update: jest.fn().mockResolvedValue({}),
      delete: jest.fn().mockResolvedValue({}),
    },
    device: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
  };
}

function buildService(tx: MockTx) {
  const prisma = {
    $transaction: jest.fn(async (cb: (t: MockTx) => Promise<unknown>) => cb(tx)),
  };
  const service = new AccountService(prisma as never);
  return { prisma, service };
}

describe('AccountService.deleteAccount', () => {
  const userId = 'user-victim';

  it('runs every cascade step inside a single transaction', async () => {
    const tx = createTxMock();
    const { prisma, service } = buildService(tx);

    await service.deleteAccount(userId);

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.user.delete).toHaveBeenCalledTimes(1);
    expect(tx.user.delete).toHaveBeenCalledWith({ where: { id: userId } });
  });

  it('clears activeDeviceId before deleting the device rows to avoid a self-referential FK block', async () => {
    const tx = createTxMock();
    const { service } = buildService(tx);

    const order: string[] = [];
    tx.user.update.mockImplementation(async () => {
      order.push('user.update');
      return {};
    });
    tx.device.deleteMany.mockImplementation(async () => {
      order.push('device.deleteMany');
      return { count: 0 };
    });

    await service.deleteAccount(userId);

    expect(order).toEqual(['user.update', 'device.deleteMany']);
    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: userId },
      data: { activeDeviceId: null },
    });
  });

  it('deletes user-owned rows before cross-user rows to respect FK dependencies', async () => {
    const tx = createTxMock();
    const { service } = buildService(tx);

    const order: string[] = [];
    const record = (name: string) => {
      return async () => {
        order.push(name);
        return { count: 0 };
      };
    };
    tx.reaction.deleteMany.mockImplementation(record('reaction'));
    tx.messageReceipt.deleteMany.mockImplementation(record('messageReceipt'));
    tx.conversationMember.deleteMany.mockImplementation(record('conversationMember'));
    tx.device.deleteMany.mockImplementation(record('device'));
    tx.user.delete.mockImplementation(async () => {
      order.push('user.delete');
      return {};
    });

    await service.deleteAccount(userId);

    expect(order.indexOf('reaction')).toBeLessThan(order.indexOf('user.delete'));
    expect(order.indexOf('messageReceipt')).toBeLessThan(order.indexOf('user.delete'));
    expect(order.indexOf('conversationMember')).toBeLessThan(order.indexOf('device'));
    expect(order.indexOf('device')).toBeLessThan(order.indexOf('user.delete'));
  });

  it('scopes userContact deletion to both sides of the contact graph', async () => {
    const tx = createTxMock();
    const { service } = buildService(tx);

    await service.deleteAccount(userId);

    expect(tx.userContact.deleteMany).toHaveBeenCalledWith({
      where: { OR: [{ userId }, { contactUserId: userId }] },
    });
  });

  it('scopes storyView deletion by viewerUserId (not userId) since story views carry only the viewer', async () => {
    const tx = createTxMock();
    const { service } = buildService(tx);

    await service.deleteAccount(userId);

    expect(tx.storyView.deleteMany).toHaveBeenCalledWith({
      where: { viewerUserId: userId },
    });
  });

  it('propagates the { deleted: true } marker from a successful transaction', async () => {
    const tx = createTxMock();
    const { service } = buildService(tx);

    await expect(service.deleteAccount(userId)).resolves.toEqual({ deleted: true });
  });

  it('aborts cleanly when a cascade step throws — transaction must roll back', async () => {
    const tx = createTxMock();
    const boom = new Error('db busy');
    tx.conversationMember.deleteMany.mockRejectedValue(boom);
    const { service } = buildService(tx);

    await expect(service.deleteAccount(userId)).rejects.toThrow('db busy');
    // Later steps must not run — Prisma would roll back the whole transaction,
    // but the service layer contract is just that it doesn't swallow the error.
    expect(tx.user.delete).not.toHaveBeenCalled();
  });
});
