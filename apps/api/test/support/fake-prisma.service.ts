type UserRecord = {
  id: string;
  handle: string;
  displayName: string | null;
  avatarPath: string | null;
  status: 'active' | 'locked' | 'revoked';
  activeDeviceId: string | null;
  createdAt: Date;
  updatedAt: Date;
};

type DeviceRecord = {
  id: string;
  userId: string;
  platform: 'ios' | 'android' | 'windows' | 'macos' | 'linux';
  deviceName: string;
  publicIdentityKey: string;
  signedPrekeyBundle: string;
  authPublicKey: string;
  pushToken: string | null;
  isActive: boolean;
  revokedAt: Date | null;
  trustedAt: Date;
  joinedFromDeviceId: string | null;
  createdAt: Date;
  lastSeenAt: Date;
  lastSyncAt: Date | null;
};

type ConversationRecord = {
  id: string;
  type: 'direct';
  createdAt: Date;
};

type ConversationMemberRecord = {
  id: string;
  conversationId: string;
  userId: string;
  joinedAt: Date;
};

type AttachmentRecord = {
  id: string;
  uploaderDeviceId: string;
  storageKey: string;
  contentType: string;
  sizeBytes: number;
  sha256: string;
  uploadStatus: 'pending' | 'uploaded' | 'failed';
  createdAt: Date;
};

type MessageRecord = {
  id: string;
  conversationId: string;
  senderDeviceId: string;
  clientMessageId: string;
  conversationOrder: number;
  ciphertext: string;
  nonce: string;
  messageType: 'text' | 'image' | 'file' | 'system';
  attachmentId: string | null;
  attachmentRef: unknown | null;
  serverReceivedAt: Date;
  deletedAt: Date | null;
  expiresAt: Date | null;
};

type MessageReceiptRecord = {
  id: string;
  messageId: string;
  userId: string;
  deliveredAt: Date | null;
  readAt: Date | null;
};

type DeviceConversationStateRecord = {
  id: string;
  deviceId: string;
  conversationId: string;
  lastSyncedConversationOrder: number | null;
  lastReadConversationOrder: number | null;
  updatedAt: Date;
};

type DeviceTransferSessionRecord = {
  id: string;
  userId: string;
  oldDeviceId: string;
  tokenHash: string;
  expiresAt: Date;
  completedAt: Date | null;
  createdAt: Date;
};

const makeId = (_prefix: string) => randomUUID();

export class FakePrismaService {
  users: UserRecord[] = [];
  devices: DeviceRecord[] = [];
  conversations: ConversationRecord[] = [];
  conversationMembers: ConversationMemberRecord[] = [];
  attachments: AttachmentRecord[] = [];
  messages: MessageRecord[] = [];
  messageReceipts: MessageReceiptRecord[] = [];
  deviceConversationStates: DeviceConversationStateRecord[] = [];
  transferSessions: DeviceTransferSessionRecord[] = [];

  user = {
    findUnique: async (_args: any) => undefined as any,
    create: async (_args: any) => undefined as any,
    update: async (_args: any) => undefined as any,
  };

  device = {
    findUnique: async (_args: any) => undefined as any,
    findFirst: async (_args: any) => undefined as any,
    findMany: async (_args: any) => [] as any[],
    create: async (_args: any) => undefined as any,
    update: async (_args: any) => undefined as any,
  };

  conversation = {
    findMany: async (_args: any) => [] as any[],
    create: async (_args: any) => undefined as any,
  };

  conversationMember = {
    findMany: async (_args: any) => [] as any[],
    findUnique: async (_args: any) => undefined as any,
  };

  attachment = {
    create: async (_args: any) => undefined as any,
    findUnique: async (_args: any) => undefined as any,
    findMany: async (_args: any) => [] as any[],
    update: async (_args: any) => undefined as any,
  };

  message = {
    create: async (_args: any) => undefined as any,
    findMany: async (_args: any) => [] as any[],
    findFirst: async (_args: any) => undefined as any,
    findUnique: async (_args: any) => undefined as any,
  };

  messageReceipt = {
    findUnique: async (_args: any) => undefined as any,
    upsert: async (_args: any) => undefined as any,
  };

  deviceConversationState = {
    findUnique: async (_args: any) => undefined as any,
    upsert: async (_args: any) => undefined as any,
  };

  deviceTransferSession = {
    create: async (_args: any) => undefined as any,
    findMany: async (_args: any) => [] as any[],
    findUnique: async (_args: any) => undefined as any,
    update: async (_args: any) => undefined as any,
    updateMany: async (_args: any) => ({ count: 0 }),
  };

  constructor() {
    this.user.findUnique = async ({ where, include, select }: any) => {
      const record = this.users.find((item) =>
        where.id ? item.id === where.id : item.handle === where.handle,
      );
      if (!record) {
        return null;
      }
      if (select) {
        return this.pick(record, select);
      }
      if (include?.activeDevice) {
        return {
          ...record,
          activeDevice: record.activeDeviceId
            ? this.devices.find((item) => item.id == record.activeDeviceId) ?? null
            : null,
        };
      }
      return record;
    };

    this.user.create = async ({ data }: any) => {
      const record: UserRecord = {
        id: makeId('user'),
        handle: data.handle,
        displayName: data.displayName ?? null,
        avatarPath: null,
        status: data.status ?? 'active',
        activeDeviceId: data.activeDeviceId ?? null,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      this.users.push(record);
      return record;
    };

    this.user.update = async ({ where, data }: any) => {
      const record = this.users.find((item) => item.id === where.id)!;
      Object.assign(record, data, { updatedAt: new Date() });
      return record;
    };

    this.device.findUnique = async ({ where, include, select }: any) => {
      const record = this.devices.find((item) => item.id === where.id);
      if (!record) {
        return null;
      }
      if (select) {
        return this.pick(record, select);
      }
      if (include?.user) {
        return {
          ...record,
          user: this.users.find((item) => item.id === record.userId)!,
        };
      }
      return record;
    };

    this.device.findFirst = async ({ where, select }: any) => {
      const record = this.devices.find(
        (item) =>
          (!where.id || item.id === where.id) &&
          (!where.userId || item.userId === where.userId) &&
          (where.isActive === undefined || item.isActive === where.isActive) &&
          (where.revokedAt === undefined ||
            (where.revokedAt === null ? item.revokedAt === null : item.revokedAt === where.revokedAt)),
      );
      if (!record) {
        return null;
      }
      return select ? this.pick(record, select) : record;
    };

    this.device.findMany = async ({ where, orderBy, select, include }: any) => {
      let records = [...this.devices];
      if (where?.userId) {
        records = records.filter((item) => item.userId === where.userId);
      }
      if (where?.isActive !== undefined) {
        records = records.filter((item) => item.isActive === where.isActive);
      }
      if (where?.revokedAt === null) {
        records = records.filter((item) => item.revokedAt === null);
      }
      if (where?.pushToken?.not === null) {
        records = records.filter((item) => item.pushToken !== null);
      }
      if (where?.id?.notIn) {
        records = records.filter((item) => !where.id.notIn.includes(item.id));
      }

      if (orderBy) {
        const orderRules = Array.isArray(orderBy) ? orderBy : [orderBy];
        records.sort((left, right) => {
          for (const rule of orderRules) {
            const entry = Object.entries(rule)[0];
            if (entry == null) {
              continue;
            }
            const key = entry[0] as keyof DeviceRecord;
            const direction = entry[1];
            const leftValue = left[key];
            const rightValue = right[key];
            let comparison = 0;
            if (typeof leftValue === 'boolean' && typeof rightValue === 'boolean') {
              comparison = Number(leftValue) - Number(rightValue);
            } else if (leftValue instanceof Date && rightValue instanceof Date) {
              comparison = leftValue.getTime() - rightValue.getTime();
            } else {
              comparison = String(leftValue).localeCompare(String(rightValue));
            }
            if (comparison != 0) {
              return direction === 'desc' ? -comparison : comparison;
            }
          }
          return 0;
        });
      }

      if (select) {
        return records.map((record) => this.pick(record, select));
      }
      if (include?.joinedFromDevice) {
        return records.map((record) => ({
          ...record,
          joinedFromDevice: record.joinedFromDeviceId
            ? this.pick(
                this.devices.find((item) => item.id === record.joinedFromDeviceId)!,
                include.joinedFromDevice.select,
              )
            : null,
        }));
      }
      return records;
    };

    this.device.create = async ({ data }: any) => {
      const record: DeviceRecord = {
        id: makeId('device'),
        userId: data.userId,
        platform: data.platform,
        deviceName: data.deviceName,
        publicIdentityKey: data.publicIdentityKey,
        signedPrekeyBundle: data.signedPrekeyBundle,
        authPublicKey: data.authPublicKey,
        pushToken: data.pushToken ?? null,
        isActive: data.isActive ?? true,
        revokedAt: data.revokedAt ?? null,
        trustedAt: data.trustedAt ?? new Date(),
        joinedFromDeviceId: data.joinedFromDeviceId ?? null,
        createdAt: new Date(),
        lastSeenAt: data.lastSeenAt ?? new Date(),
        lastSyncAt: data.lastSyncAt ?? null,
      };
      this.devices.push(record);
      return record;
    };

    this.device.update = async ({ where, data }: any) => {
      const record = this.devices.find((item) => item.id === where.id)!;
      Object.assign(record, data);
      return record;
    };

    this.conversation.findMany = async ({ where, include }: any) => {
      let records = [...this.conversations];
      if (where?.id?.in) {
        records = records.filter((item) => where.id.in.includes(item.id));
      }
      if (where?.type) {
        records = records.filter((item) => item.type === where.type);
      }
      return records.map((record) => this.hydrateConversation(record, include));
    };

    this.conversation.create = async ({ data, include }: any) => {
      const record: ConversationRecord = {
        id: makeId('conv'),
        type: data.type,
        createdAt: new Date(),
      };
      this.conversations.push(record);
      for (const member of data.members.create as Array<{ userId: string }>) {
        this.conversationMembers.push({
          id: makeId('member'),
          conversationId: record.id,
          userId: member.userId,
          joinedAt: new Date(),
        });
      }
      return this.hydrateConversation(record, include);
    };

    this.conversationMember.findMany = async ({ where, include }: any) => {
      let records = [...this.conversationMembers];
      if (where?.userId) {
        records = records.filter((item) => item.userId === where.userId);
      }
      if (where?.conversationId) {
        records = records.filter((item) => item.conversationId === where.conversationId);
      }
      return records.map((record) =>
        include?.conversation
          ? {
              ...record,
              conversation: this.hydrateConversation(
                this.conversations.find((item) => item.id === record.conversationId)!,
                include.conversation.include,
              ),
            }
          : record,
      );
    };

    this.conversationMember.findUnique = async ({ where, select }: any) => {
      const record = this.conversationMembers.find(
        (item) =>
          item.conversationId === where.conversationId_userId.conversationId &&
          item.userId === where.conversationId_userId.userId,
      );
      if (!record) {
        return null;
      }
      return select ? this.pick(record, select) : record;
    };

    this.attachment.create = async ({ data }: any) => {
      const record: AttachmentRecord = {
        id: makeId('attachment'),
        uploaderDeviceId: data.uploaderDeviceId,
        storageKey: data.storageKey,
        contentType: data.contentType,
        sizeBytes: data.sizeBytes,
        sha256: data.sha256,
        uploadStatus: data.uploadStatus,
        createdAt: new Date(),
      };
      this.attachments.push(record);
      return record;
    };

    this.attachment.findUnique = async ({ where, select }: any) => {
      const record = this.attachments.find((item) => item.id === where.id);
      if (!record) {
        return null;
      }
      return select ? this.pick(record, select) : record;
    };

    this.attachment.findMany = async ({ where, select }: any = {}) => {
      let records = [...this.attachments];
      if (where?.uploaderDeviceId) {
        records = records.filter((item) => item.uploaderDeviceId === where.uploaderDeviceId);
      }
      if (where?.uploadStatus) {
        records = records.filter((item) => item.uploadStatus === where.uploadStatus);
      }
      if (where?.createdAt?.lt) {
        records = records.filter((item) => item.createdAt < where.createdAt.lt);
      }
      return select ? records.map((record) => this.pick(record, select)) : records;
    };

    this.attachment.update = async ({ where, data }: any) => {
      const record = this.attachments.find((item) => item.id === where.id)!;
      Object.assign(record, data);
      return record;
    };

    this.message.create = async ({ data, include }: any) => {
      const record: MessageRecord = {
        id: makeId('msg'),
        conversationId: data.conversationId,
        senderDeviceId: data.senderDeviceId,
        clientMessageId: data.clientMessageId,
        conversationOrder: data.conversationOrder,
        ciphertext: data.ciphertext,
        nonce: data.nonce,
        messageType: data.messageType,
        attachmentId: data.attachmentId ?? null,
        attachmentRef: data.attachmentRef ?? null,
        serverReceivedAt: new Date(),
        deletedAt: null,
        expiresAt: data.expiresAt ?? null,
      };
      this.messages.push(record);
      for (const receipt of (data.receipts?.create ?? []) as Array<any>) {
        this.messageReceipts.push({
          id: makeId('receipt'),
          messageId: record.id,
          userId: receipt.userId,
          deliveredAt: receipt.deliveredAt ?? null,
          readAt: receipt.readAt ?? null,
        });
      }
      return this.hydrateMessage(record, include);
    };

    this.message.findMany = async ({ where, take, cursor, include }: any) => {
      let records = this.messages
        .filter((item) => item.conversationId === where.conversationId)
        .filter((item) =>
          where?.conversationOrder?.lt === undefined
            ? true
            : item.conversationOrder < where.conversationOrder.lt,
        )
        .sort((a, b) => b.conversationOrder - a.conversationOrder);
      if (cursor?.id) {
        const index = records.findIndex((item) => item.id === cursor.id);
        records = index >= 0 ? records.slice(index + 1) : records;
      }
      return records.slice(0, take ?? records.length).map((record) => this.hydrateMessage(record, include));
    };

    this.message.findUnique = async ({ where, include, select }: any) => {
      const record = this.messages.find((item) => item.id === where.id);
      if (!record) {
        return null;
      }
      if (select) {
        return this.pick(record as unknown as Record<string, any>, select);
      }
      const conversation = this.conversations.find((item) => item.id === record.conversationId)!;
      return {
        ...record,
        conversation: include?.conversation
          ? {
              ...conversation,
              members: this.conversationMembers.filter((item) => item.conversationId === conversation.id),
            }
          : undefined,
      };
    };

    this.message.findFirst = async ({ where, select }: any) => {
      const records = this.messages.filter((item) => {
        if (where?.senderDeviceId && item.senderDeviceId !== where.senderDeviceId) {
          return false;
        }
        if (where?.clientMessageId && item.clientMessageId !== where.clientMessageId) {
          return false;
        }
        if (where?.conversationId && item.conversationId !== where.conversationId) {
          return false;
        }
        if (where?.attachmentId && item.attachmentId !== where.attachmentId) {
          return false;
        }
        if (where?.conversation?.members?.some?.userId) {
          return this.conversationMembers.some(
            (member) =>
              member.conversationId === item.conversationId &&
              member.userId === where.conversation.members.some.userId,
          );
        }
        return true;
      });
      const record = records.sort((a, b) => b.conversationOrder - a.conversationOrder)[0];

      if (!record) {
        return null;
      }

      return select ? this.pick(record, select) : record;
    };

    this.messageReceipt.upsert = async ({ where, update, create }: any) => {
      const record = this.messageReceipts.find(
        (item) =>
          item.messageId === where.messageId_userId.messageId &&
          item.userId === where.messageId_userId.userId,
      );
      if (record) {
        Object.assign(record, update);
        return record;
      }
      const created: MessageReceiptRecord = {
        id: makeId('receipt'),
        messageId: create.messageId,
        userId: create.userId,
        deliveredAt: create.deliveredAt ?? null,
        readAt: create.readAt ?? null,
      };
      this.messageReceipts.push(created);
      return created;
    };

    this.messageReceipt.findUnique = async ({ where }: any) => {
      return (
        this.messageReceipts.find(
          (item) =>
            item.messageId === where.messageId_userId.messageId &&
            item.userId === where.messageId_userId.userId,
        ) ?? null
      );
    };

    this.deviceConversationState.findUnique = async ({ where }: any) => {
      return (
        this.deviceConversationStates.find(
          (item) =>
            item.deviceId === where.deviceId_conversationId.deviceId &&
            item.conversationId === where.deviceId_conversationId.conversationId,
        ) ?? null
      );
    };

    this.deviceConversationState.upsert = async ({ where, update, create }: any) => {
      const record = this.deviceConversationStates.find(
        (item) =>
          item.deviceId === where.deviceId_conversationId.deviceId &&
          item.conversationId === where.deviceId_conversationId.conversationId,
      );

      if (record) {
        Object.assign(record, update, { updatedAt: new Date() });
        return record;
      }

      const createdRecord: DeviceConversationStateRecord = {
        id: makeId('device-state'),
        deviceId: create.deviceId,
        conversationId: create.conversationId,
        lastSyncedConversationOrder: create.lastSyncedConversationOrder ?? null,
        lastReadConversationOrder: create.lastReadConversationOrder ?? null,
        updatedAt: new Date(),
      };
      this.deviceConversationStates.push(createdRecord);
      return createdRecord;
    };

    this.deviceTransferSession.create = async ({ data }: any) => {
      const record: DeviceTransferSessionRecord = {
        id: makeId('transfer'),
        userId: data.userId,
        oldDeviceId: data.oldDeviceId,
        tokenHash: data.tokenHash,
        expiresAt: data.expiresAt,
        completedAt: null,
        createdAt: new Date(),
      };
      this.transferSessions.push(record);
      return record;
    };

    this.deviceTransferSession.findUnique = async ({ where, include }: any) => {
      const record = this.transferSessions.find((item) => item.id === where.id);
      if (!record) {
        return null;
      }
      if (include?.user || include?.oldDevice) {
        return {
          ...record,
          user: include.user ? this.users.find((item) => item.id === record.userId)! : undefined,
          oldDevice: include.oldDevice
            ? this.devices.find((item) => item.id === record.oldDeviceId)!
            : undefined,
        };
      }
      return record;
    };

    this.deviceTransferSession.findMany = async ({ where }: any) => {
      let records = [...this.transferSessions];
      if (where?.userId) {
        records = records.filter((item) => item.userId === where.userId);
      }
      if (where?.oldDeviceId) {
        records = records.filter((item) => item.oldDeviceId === where.oldDeviceId);
      }
      if (where?.completedAt === null) {
        records = records.filter((item) => item.completedAt === null);
      }
      if (where?.expiresAt?.lt) {
        records = records.filter((item) => item.expiresAt < where.expiresAt.lt);
      }
      if (where?.id?.in) {
        records = records.filter((item) => where.id.in.includes(item.id));
      }
      return records;
    };

    this.deviceTransferSession.update = async ({ where, data }: any) => {
      const record = this.transferSessions.find((item) => item.id === where.id)!;
      Object.assign(record, data);
      return record;
    };

    this.deviceTransferSession.updateMany = async ({ where, data }: any) => {
      let updated = 0;
      for (const record of this.transferSessions) {
        const matchesUser = !where?.userId || record.userId === where.userId;
        const matchesOldDevice = !where?.oldDeviceId || record.oldDeviceId === where.oldDeviceId;
        const matchesIds = !where?.id?.in || where.id.in.includes(record.id);
        const matchesCompletedAt =
          where?.completedAt === undefined ||
          (where.completedAt === null ? record.completedAt === null : record.completedAt === where.completedAt);
        const matchesExpiresAt =
          where?.expiresAt?.lt === undefined || record.expiresAt < where.expiresAt.lt;
        if (!matchesUser || !matchesOldDevice || !matchesIds || !matchesCompletedAt || !matchesExpiresAt) {
          continue;
        }
        Object.assign(record, data);
        updated += 1;
      }
      return { count: updated };
    };
  }

  async $transaction<T>(
    callback: (tx: this) => Promise<T>,
    _options?: unknown,
  ): Promise<T> {
    return callback(this);
  }

  private hydrateConversation(record: ConversationRecord, include?: any): any {
    return {
      ...record,
      members: include?.members
        ? this.conversationMembers
            .filter((item) => item.conversationId === record.id)
            .map((member) => ({
              ...member,
              user: include.members.include?.user
                ? this.users.find((item) => item.id === member.userId)
                : undefined,
            }))
        : undefined,
      messages: include?.messages
        ? this.messages
            .filter((item) => item.conversationId === record.id)
            .sort((a, b) => b.conversationOrder - a.conversationOrder)
            .slice(0, include.messages.take ?? Number.MAX_SAFE_INTEGER)
            .map((message) => this.hydrateMessage(message, include.messages.include))
        : undefined,
    };
  }

  private hydrateMessage(record: MessageRecord, include?: any): any {
    return {
      ...record,
      senderDevice: include?.senderDevice
        ? this.pick(this.devices.find((item) => item.id === record.senderDeviceId)!, include.senderDevice.select)
        : undefined,
      attachment: include?.attachment && record.attachmentId
        ? this.attachments.find((item) => item.id === record.attachmentId) ?? null
        : null,
      receipts: include?.receipts
        ? this.messageReceipts.filter((item) => item.messageId === record.id)
        : undefined,
    };
  }

  private pick(record: Record<string, any>, select: Record<string, boolean>): Record<string, any> {
    return Object.fromEntries(
      Object.entries(select)
          .filter(([, enabled]) => enabled)
          .map(([key]) => [key, record[key]]),
    );
  }
}
import { randomUUID } from 'node:crypto';
