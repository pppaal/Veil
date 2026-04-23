import { AccountService } from './account.service';

// Destructive-cascade spec. The transaction runs many deleteMany calls —
// these tests use jest.fn() mocks (not FakePrismaService) so we can verify
// the exact ordering and scoping of each step without wiring up every model.
// The ordering matters: several FKs in schema.prisma are `onDelete: Restrict`
// (Message.senderDevice, Attachment.uploaderDevice, CallRecord.initiatorDevice,
// GroupMeta.createdBy, ChannelMeta.createdBy, DeviceTransferSession.oldDevice)
// — those rows must be removed before the Device / User row they point at,
// or Postgres rejects the delete.

type MockTx = {
  reaction: { deleteMany: jest.Mock };
  storyView: { deleteMany: jest.Mock };
  story: { deleteMany: jest.Mock };
  messageReceipt: { deleteMany: jest.Mock };
  userContact: { deleteMany: jest.Mock };
  userProfile: { deleteMany: jest.Mock };
  conversationMember: { deleteMany: jest.Mock };
  deviceTransferSession: { deleteMany: jest.Mock };
  message: { deleteMany: jest.Mock };
  attachment: { deleteMany: jest.Mock };
  callRecord: { deleteMany: jest.Mock };
  conversation: { deleteMany: jest.Mock };
  groupMeta: { findMany: jest.Mock };
  channelMeta: { findMany: jest.Mock };
  user: { update: jest.Mock; delete: jest.Mock };
  device: { findMany: jest.Mock; deleteMany: jest.Mock };
};

function createTxMock(overrides?: {
  deviceIds?: string[];
  ownedGroupConversationIds?: string[];
  ownedChannelConversationIds?: string[];
}): MockTx {
  const deviceIds = overrides?.deviceIds ?? ['device-1'];
  const ownedGroups = overrides?.ownedGroupConversationIds ?? [];
  const ownedChannels = overrides?.ownedChannelConversationIds ?? [];
  return {
    reaction: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    storyView: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    story: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    messageReceipt: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    userContact: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    userProfile: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    conversationMember: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    deviceTransferSession: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    message: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    attachment: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    callRecord: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    conversation: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    groupMeta: {
      findMany: jest
        .fn()
        .mockResolvedValue(ownedGroups.map((id) => ({ conversationId: id }))),
    },
    channelMeta: {
      findMany: jest
        .fn()
        .mockResolvedValue(ownedChannels.map((id) => ({ conversationId: id }))),
    },
    user: {
      update: jest.fn().mockResolvedValue({}),
      delete: jest.fn().mockResolvedValue({}),
    },
    device: {
      findMany: jest.fn().mockResolvedValue(deviceIds.map((id) => ({ id }))),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
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

  it('collects device IDs before touching any Restrict-gated row', async () => {
    const tx = createTxMock({ deviceIds: ['device-a', 'device-b'] });
    const { service } = buildService(tx);

    const order: string[] = [];
    tx.device.findMany.mockImplementation(async () => {
      order.push('device.findMany');
      return [{ id: 'device-a' }, { id: 'device-b' }];
    });
    tx.message.deleteMany.mockImplementation(async () => {
      order.push('message.deleteMany');
      return { count: 0 };
    });
    tx.device.deleteMany.mockImplementation(async () => {
      order.push('device.deleteMany');
      return { count: 0 };
    });

    await service.deleteAccount(userId);

    expect(order[0]).toBe('device.findMany');
    expect(order.indexOf('message.deleteMany')).toBeLessThan(
      order.indexOf('device.deleteMany'),
    );
  });

  it('removes Restrict-gated child rows before device.deleteMany', async () => {
    const tx = createTxMock({ deviceIds: ['device-a', 'device-b'] });
    const { service } = buildService(tx);

    await service.deleteAccount(userId);

    expect(tx.message.deleteMany).toHaveBeenCalledWith({
      where: { senderDeviceId: { in: ['device-a', 'device-b'] } },
    });
    expect(tx.attachment.deleteMany).toHaveBeenCalledWith({
      where: { uploaderDeviceId: { in: ['device-a', 'device-b'] } },
    });
    expect(tx.callRecord.deleteMany).toHaveBeenCalledWith({
      where: { initiatorDeviceId: { in: ['device-a', 'device-b'] } },
    });
    expect(tx.deviceTransferSession.deleteMany).toHaveBeenCalledWith({
      where: {
        OR: [{ userId }, { oldDeviceId: { in: ['device-a', 'device-b'] } }],
      },
    });
  });

  it('skips the device-scoped deleteMany calls when the user has no devices', async () => {
    const tx = createTxMock({ deviceIds: [] });
    const { service } = buildService(tx);

    await service.deleteAccount(userId);

    expect(tx.message.deleteMany).not.toHaveBeenCalled();
    expect(tx.attachment.deleteMany).not.toHaveBeenCalled();
    expect(tx.callRecord.deleteMany).not.toHaveBeenCalled();
    // Still sweeps user-scoped transfer sessions even without devices.
    expect(tx.deviceTransferSession.deleteMany).toHaveBeenCalledWith({
      where: { userId },
    });
  });

  it('deletes conversations the user created (group + channel) before devices', async () => {
    const tx = createTxMock({
      ownedGroupConversationIds: ['conv-g1', 'conv-g2'],
      ownedChannelConversationIds: ['conv-c1'],
    });
    const { service } = buildService(tx);

    const order: string[] = [];
    tx.conversation.deleteMany.mockImplementation(async () => {
      order.push('conversation.deleteMany');
      return { count: 0 };
    });
    tx.device.deleteMany.mockImplementation(async () => {
      order.push('device.deleteMany');
      return { count: 0 };
    });

    await service.deleteAccount(userId);

    expect(tx.conversation.deleteMany).toHaveBeenCalledWith({
      where: { id: { in: ['conv-g1', 'conv-g2', 'conv-c1'] } },
    });
    expect(order.indexOf('conversation.deleteMany')).toBeLessThan(
      order.indexOf('device.deleteMany'),
    );
  });

  it('does not call conversation.deleteMany when the user owns none', async () => {
    const tx = createTxMock();
    const { service } = buildService(tx);

    await service.deleteAccount(userId);

    expect(tx.conversation.deleteMany).not.toHaveBeenCalled();
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
    // Later steps must not run — Prisma rolls back the whole transaction,
    // the service contract is just that it doesn't swallow the error.
    expect(tx.user.delete).not.toHaveBeenCalled();
  });
});
