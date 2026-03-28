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
  platform: 'ios' | 'android';
  deviceName: string;
  publicIdentityKey: string;
  signedPrekeyBundle: string;
  authPublicKey: string;
  pushToken: string | null;
  isActive: boolean;
  revokedAt: Date | null;
  createdAt: Date;
  lastSeenAt: Date;
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

type DeviceTransferSessionRecord = {
  id: string;
  userId: string;
  oldDeviceId: string;
  tokenHash: string;
  expiresAt: Date;
  completedAt: Date | null;
  createdAt: Date;
};

const makeId = (prefix: string) => `${prefix}-${Math.random().toString(36).slice(2, 10)}`;

export class FakePrismaService {
  users: UserRecord[] = [];
  devices: DeviceRecord[] = [];
  conversations: ConversationRecord[] = [];
  conversationMembers: ConversationMemberRecord[] = [];
  attachments: AttachmentRecord[] = [];
  messages: MessageRecord[] = [];
  messageReceipts: MessageReceiptRecord[] = [];
  transferSessions: DeviceTransferSessionRecord[] = [];

  user = {
    findUnique: async (_args: any) => undefined as any,
    create: async (_args: any) => undefined as any,
    update: async (_args: any) => undefined as any,
  };

  device = {
    findUnique: async (_args: any) => undefined as any,
    findFirst: async (_args: any) => undefined as any,
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
    update: async (_args: any) => undefined as any,
  };

  message = {
    create: async (_args: any) => undefined as any,
    findMany: async (_args: any) => [] as any[],
    findFirst: async (_args: any) => undefined as any,
    findUnique: async (_args: any) => undefined as any,
  };

  messageReceipt = {
    upsert: async (_args: any) => undefined as any,
  };

  deviceTransferSession = {
    create: async (_args: any) => undefined as any,
    findUnique: async (_args: any) => undefined as any,
    update: async (_args: any) => undefined as any,
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
        createdAt: new Date(),
        lastSeenAt: data.lastSeenAt ?? new Date(),
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
        .sort((a, b) => b.serverReceivedAt.getTime() - a.serverReceivedAt.getTime());
      if (cursor?.id) {
        const index = records.findIndex((item) => item.id === cursor.id);
        records = index >= 0 ? records.slice(index + 1) : records;
      }
      return records.slice(0, take ?? records.length).map((record) => this.hydrateMessage(record, include));
    };

    this.message.findUnique = async ({ where, include }: any) => {
      const record = this.messages.find((item) => item.id === where.id);
      if (!record) {
        return null;
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
      const record = this.messages.find((item) => {
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

    this.deviceTransferSession.update = async ({ where, data }: any) => {
      const record = this.transferSessions.find((item) => item.id === where.id)!;
      Object.assign(record, data);
      return record;
    };
  }

  async $transaction<T>(callback: (tx: this) => Promise<T>): Promise<T> {
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
            .sort((a, b) => b.serverReceivedAt.getTime() - a.serverReceivedAt.getTime())
            .slice(0, include.messages.take ?? Number.MAX_SAFE_INTEGER)
        : undefined,
    };
  }

  private hydrateMessage(record: MessageRecord, include?: any): any {
    return {
      ...record,
      attachment: include?.attachment && record.attachmentId
        ? this.attachments.find((item) => item.id === record.attachmentId) ?? null
        : null,
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
