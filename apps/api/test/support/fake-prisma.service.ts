import { randomUUID } from 'node:crypto';

import { Prisma } from '@prisma/client';

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

type MemberRole = 'owner' | 'admin' | 'member' | 'subscriber';

// Optional fields mirror schema defaults so specs can seed rows tersely;
// FakePrismaService fills them in (see ROW_DEFAULTS) before any query.
type ConversationRecord = {
  id: string;
  type: 'direct' | 'group' | 'channel';
  createdAt: Date;
  directKey?: string | null;
  currentEpoch?: number;
  groupUseSenderKeys?: boolean;
  disappearingTimerSeconds?: number | null;
  lastOrder?: number;
};

type ConversationMemberRecord = {
  id: string;
  conversationId: string;
  userId: string;
  role?: MemberRole;
  joinedAt: Date;
};

type GroupMetaRecord = {
  id: string;
  conversationId: string;
  name: string;
  description: string | null;
  avatarPath: string | null;
  createdByUserId: string;
  isPublic: boolean;
  memberLimit: number;
  link: string | null;
  createdAt: Date;
  updatedAt: Date;
};

type ChannelMetaRecord = {
  id: string;
  conversationId: string;
  name: string;
  description: string | null;
  avatarPath: string | null;
  createdByUserId: string;
  isPublic: boolean;
  subscriberCount: number;
  link: string | null;
  createdAt: Date;
  updatedAt: Date;
};

type GroupMemberEpochRecord = {
  conversationId: string;
  userId: string;
  joinedEpoch: number;
  leftEpoch: number | null;
};

type CallRecordRecord = {
  id: string;
  conversationId: string;
  initiatorDeviceId: string;
  callType: 'voice' | 'video';
  status: 'ringing' | 'active' | 'ended' | 'missed' | 'declined';
  startedAt: Date;
  endedAt: Date | null;
  duration: number | null;
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
  envelopeVersion?: string;
  ciphertext: string;
  nonce: string;
  messageType: 'text' | 'image' | 'file' | 'system' | 'voice' | 'sticker' | 'reaction' | 'call';
  attachmentId: string | null;
  attachmentRef: unknown | null;
  serverReceivedAt: Date;
  deletedAt: Date | null;
  expiresAt: Date | null;
  // Phase X reply/edit metadata. Optional on the fake so existing
  // create paths that don't supply these still type-check.
  replyToMessageId?: string | null;
  editedAt?: Date | null;
  editCount?: number;
  viewOnce?: boolean;
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

type UserContactRecord = {
  id: string;
  userId: string;
  contactUserId: string;
  nickname: string | null;
  createdAt: Date;
};

type UserProfileRecord = {
  id: string;
  userId: string;
  bio: string | null;
  statusMessage: string | null;
  statusEmoji: string | null;
  lastStatusAt: Date | null;
  avatarPath: string | null;
  createdAt: Date;
  updatedAt: Date;
};

type ReactionRecord = {
  id: string;
  messageId: string;
  userId: string;
  emoji: string;
  createdAt: Date;
};

type OneTimePrekeyRecord = {
  id: string;
  deviceId: string;
  keyId: number;
  publicKey: string;
  consumedAt: Date | null;
  createdAt: Date;
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

type Row = Record<string, any>;

// Models served by the generic query engine below. It evaluates the subset of
// Prisma's where/select/include/orderBy/take semantics the conversation and
// message domain uses, so specs exercise the services' real queries instead
// of hand-rolled return values.
type ModelName =
  | 'user'
  | 'device'
  | 'attachment'
  | 'conversation'
  | 'conversationMember'
  | 'message'
  | 'messageReceipt'
  | 'reaction'
  | 'groupMeta'
  | 'channelMeta'
  | 'groupMemberEpoch'
  | 'callRecord';

type RelationRows = { model: ModelName; many: boolean; rows: Row[] };

const ROW_DEFAULTS: Partial<Record<ModelName, Row>> = {
  conversation: {
    directKey: null,
    disappearingTimerSeconds: null,
    currentEpoch: 0,
    groupUseSenderKeys: false,
  },
  conversationMember: { role: 'member' },
  message: {
    envelopeVersion: 'veil-envelope-v1',
    replyToMessageId: null,
    editedAt: null,
    editCount: 0,
    viewOnce: false,
  },
};

const isPlainObject = (value: unknown): value is Row =>
  typeof value === 'object' && value !== null && !Array.isArray(value) && !(value instanceof Date);

const uniqueViolation = (fields: string): Error =>
  Object.assign(new Error(`Unique constraint failed on the fields: (${fields})`), {
    code: 'P2002',
    clientVersion: 'fake',
  });

const recordNotFound = (model: ModelName): Error =>
  Object.assign(new Error(`No ${model} record found`), { code: 'P2025', clientVersion: 'fake' });

const compareValues = (left: unknown, right: unknown): number => {
  if (left instanceof Date && right instanceof Date) return left.getTime() - right.getTime();
  if (typeof left === 'number' && typeof right === 'number') return left - right;
  if (typeof left === 'boolean' && typeof right === 'boolean') return Number(left) - Number(right);
  return String(left).localeCompare(String(right));
};

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
  oneTimePrekeys: OneTimePrekeyRecord[] = [];
  reactions: ReactionRecord[] = [];
  userContacts: UserContactRecord[] = [];
  userProfiles: UserProfileRecord[] = [];
  groupMetas: GroupMetaRecord[] = [];
  channelMetas: ChannelMetaRecord[] = [];
  groupMemberEpochs: GroupMemberEpochRecord[] = [];
  callRecords: CallRecordRecord[] = [];

  user = {
    findUnique: async (_args: any) => undefined as any,
    findMany: async (args: any = {}) =>
      this.findRows('user', args).map((row) => this.project('user', row, args)),
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

  conversation = this.delegate('conversation', (data) => this.insertConversation(data));

  conversationMember = this.delegate('conversationMember', (data) => this.insertMember(data));

  groupMeta = this.delegate('groupMeta', (data) => this.insertGroupMeta(data));

  channelMeta = this.delegate('channelMeta', (data) => this.insertChannelMeta(data));

  groupMemberEpoch = this.delegate('groupMemberEpoch', (data) => {
    const record: GroupMemberEpochRecord = {
      conversationId: data.conversationId,
      userId: data.userId,
      joinedEpoch: data.joinedEpoch,
      leftEpoch: data.leftEpoch ?? null,
    };
    this.groupMemberEpochs.push(record);
    return record;
  });

  callRecord = this.delegate('callRecord', (data) => {
    const record: CallRecordRecord = {
      id: makeId('call'),
      conversationId: data.conversationId,
      initiatorDeviceId: data.initiatorDeviceId,
      callType: data.callType,
      status: data.status ?? 'ringing',
      startedAt: data.startedAt ?? new Date(),
      endedAt: data.endedAt ?? null,
      duration: data.duration ?? null,
    };
    this.callRecords.push(record);
    return record;
  });

  // Stubs for the safety-related tables — returning empty defaults is enough
  // for the e2e suite, which exercises the happy path through createDirect /
  // sendMessage where neither side has blocked the other.
  userBlock = {
    findFirst: async (_args: any) => null,
    findMany: async (_args: any) => [] as any[],
    create: async (_args: any) => undefined as any,
    delete: async (_args: any) => undefined as any,
    deleteMany: async (_args: any) => ({ count: 0 }),
  };

  conversationMute = {
    findFirst: async (_args: any) => null,
    findUnique: async (_args: any) => null,
    findMany: async (_args: any) => [] as any[],
    upsert: async (_args: any) => undefined as any,
    delete: async (_args: any) => undefined as any,
  };

  abuseReport = {
    create: async (_args: any) => undefined as any,
  };

  attachment = {
    create: async (_args: any) => undefined as any,
    findUnique: async (_args: any) => undefined as any,
    findMany: async (_args: any) => [] as any[],
    update: async (_args: any) => undefined as any,
    delete: async (_args: any) => undefined as any,
  };

  message = this.delegate('message', (data) => this.insertMessage(data));

  messageReceipt = this.delegate('messageReceipt', (data) => {
    const record: MessageReceiptRecord = {
      id: makeId('receipt'),
      messageId: data.messageId,
      userId: data.userId,
      deliveredAt: data.deliveredAt ?? null,
      readAt: data.readAt ?? null,
    };
    this.messageReceipts.push(record);
    return record;
  });

  deviceConversationState = {
    findUnique: async (_args: any) => undefined as any,
    upsert: async (_args: any) => undefined as any,
  };

  reaction = this.delegate('reaction', (data) => {
    const record: ReactionRecord = {
      id: makeId('reaction'),
      messageId: data.messageId,
      userId: data.userId,
      emoji: data.emoji,
      createdAt: new Date(),
    };
    this.reactions.push(record);
    return record;
  });

  userContact = {
    findMany: async (_args: any) => [] as any[],
    findUnique: async (_args: any) => undefined as any,
    create: async (_args: any) => undefined as any,
    delete: async (_args: any) => undefined as any,
  };

  userProfile = {
    findUnique: async (_args: any) => undefined as any,
    upsert: async (_args: any) => undefined as any,
  };

  oneTimePrekey = {
    // Only the groupBy shape getKeyBundle uses: count of unconsumed prekeys
    // per device, restricted to a deviceId in-list.
    groupBy: async ({ where }: any) => {
      const counts = new Map<string, number>();
      for (const item of this.oneTimePrekeys) {
        if (where?.deviceId?.in && !where.deviceId.in.includes(item.deviceId)) continue;
        if (where?.consumedAt === null && item.consumedAt !== null) continue;
        counts.set(item.deviceId, (counts.get(item.deviceId) ?? 0) + 1);
      }
      return [...counts.entries()].map(([deviceId, total]) => ({
        deviceId,
        _count: { _all: total },
      }));
    },
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
            ? (this.devices.find((item) => item.id == record.activeDeviceId) ?? null)
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
            (where.revokedAt === null
              ? item.revokedAt === null
              : item.revokedAt === where.revokedAt)),
      );
      if (!record) {
        return null;
      }
      return select ? this.pick(record, select) : record;
    };

    this.device.findMany = async ({ where, orderBy, select, include }: any) => {
      let records = [...this.devices];
      if (typeof where?.userId === 'string') {
        records = records.filter((item) => item.userId === where.userId);
      }
      if (where?.userId?.in) {
        records = records.filter((item) => where.userId.in.includes(item.userId));
      }
      if (where?.id?.in) {
        records = records.filter((item) => where.id.in.includes(item.id));
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

    this.attachment.findUnique = async (args: any) => {
      const [row] = this.findRows('attachment', { where: args.where });
      return row ? this.project('attachment', row, args) : null;
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

    this.attachment.delete = async ({ where }: any) => {
      const index = this.attachments.findIndex((item) => item.id === where.id);
      if (index < 0) return null;
      const [removed] = this.attachments.splice(index, 1);
      return removed;
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

    this.userContact.findMany = async ({ where, include, orderBy }: any) => {
      let records = [...this.userContacts];
      if (where?.userId) {
        records = records.filter((item) => item.userId === where.userId);
      }
      if (orderBy?.createdAt) {
        records.sort((a, b) =>
          orderBy.createdAt === 'asc'
            ? a.createdAt.getTime() - b.createdAt.getTime()
            : b.createdAt.getTime() - a.createdAt.getTime(),
        );
      }
      return records.map((record) => {
        if (!include?.contactUser) {
          return record;
        }
        const user = this.users.find((item) => item.id === record.contactUserId);
        if (!user) {
          return { ...record, contactUser: null };
        }
        const select = include.contactUser.select ?? {};
        const contactUser: any = {};
        if (select.id) contactUser.id = user.id;
        if (select.handle) contactUser.handle = user.handle;
        if (select.displayName) contactUser.displayName = user.displayName;
        if (select.profile) {
          const profile = this.userProfiles.find((item) => item.userId === user.id);
          contactUser.profile = profile ? this.pick(profile, select.profile.select) : null;
        }
        return { ...record, contactUser };
      });
    };

    this.userContact.findUnique = async ({ where }: any) => {
      const key = where.userId_contactUserId;
      return (
        this.userContacts.find(
          (item) => item.userId === key.userId && item.contactUserId === key.contactUserId,
        ) ?? null
      );
    };

    this.userContact.create = async ({ data }: any) => {
      const record: UserContactRecord = {
        id: makeId('contact'),
        userId: data.userId,
        contactUserId: data.contactUserId,
        nickname: data.nickname ?? null,
        createdAt: new Date(),
      };
      this.userContacts.push(record);
      return record;
    };

    this.userContact.delete = async ({ where }: any) => {
      const key = where.userId_contactUserId;
      const index = this.userContacts.findIndex(
        (item) => item.userId === key.userId && item.contactUserId === key.contactUserId,
      );
      if (index < 0) return null;
      const [removed] = this.userContacts.splice(index, 1);
      return removed;
    };

    this.userProfile.findUnique = async ({ where, select }: any) => {
      const record = this.userProfiles.find((item) => item.userId === where.userId);
      if (!record) return null;
      return select ? this.pick(record, select) : record;
    };

    this.userProfile.upsert = async ({ where, update, create }: any) => {
      const record = this.userProfiles.find((item) => item.userId === where.userId);
      if (record) {
        Object.assign(record, update, { updatedAt: new Date() });
        return record;
      }
      const created: UserProfileRecord = {
        id: makeId('profile'),
        userId: create.userId ?? where.userId,
        bio: create.bio ?? null,
        statusMessage: create.statusMessage ?? null,
        statusEmoji: create.statusEmoji ?? null,
        lastStatusAt: create.lastStatusAt ?? null,
        avatarPath: create.avatarPath ?? null,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      this.userProfiles.push(created);
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
          (where.completedAt === null
            ? record.completedAt === null
            : record.completedAt === where.completedAt);
        const matchesExpiresAt =
          where?.expiresAt?.lt === undefined || record.expiresAt < where.expiresAt.lt;
        if (
          !matchesUser ||
          !matchesOldDevice ||
          !matchesIds ||
          !matchesCompletedAt ||
          !matchesExpiresAt
        ) {
          continue;
        }
        Object.assign(record, data);
        updated += 1;
      }
      return { count: updated };
    };
  }

  // Fixture helpers: a user with one active device.
  seedUser(handle: string, options: { pushToken?: string | null } = {}) {
    const userId = randomUUID();
    const deviceId = this.seedDevice(userId, options);
    const now = new Date();
    this.users.push({
      id: userId,
      handle,
      displayName: handle,
      avatarPath: null,
      status: 'active',
      activeDeviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    });
    return { userId, deviceId };
  }

  seedDevice(
    userId: string,
    options: { pushToken?: string | null; isActive?: boolean; revokedAt?: Date | null } = {},
  ): string {
    const deviceId = randomUUID();
    const now = new Date();
    this.devices.push({
      id: deviceId,
      userId,
      platform: 'ios',
      deviceName: 'Test device',
      publicIdentityKey: 'pub-id',
      signedPrekeyBundle: 'prekey',
      authPublicKey: 'auth-pub',
      pushToken: options.pushToken ?? null,
      isActive: options.isActive ?? true,
      revokedAt: options.revokedAt ?? null,
      trustedAt: now,
      joinedFromDeviceId: null,
      createdAt: now,
      lastSeenAt: now,
      lastSyncAt: null,
    });
    return deviceId;
  }

  // A conversation with its members (a bare userId joins as 'member') and,
  // for groups and channels, the meta row.
  seedConversation(
    type: ConversationRecord['type'],
    members: Array<string | { userId: string; role?: MemberRole; joinedAt?: Date }>,
    options: {
      groupUseSenderKeys?: boolean;
      currentEpoch?: number;
      disappearingTimerSeconds?: number | null;
      isPublic?: boolean;
      memberLimit?: number;
    } = {},
  ): string {
    const conversation = this.insertConversation({
      type,
      groupUseSenderKeys: options.groupUseSenderKeys,
      currentEpoch: options.currentEpoch,
      disappearingTimerSeconds: options.disappearingTimerSeconds,
    });
    for (const member of members) {
      this.insertMember({
        conversationId: conversation.id,
        ...(typeof member === 'string' ? { userId: member } : member),
      });
    }
    const createdByUserId = typeof members[0] === 'string' ? members[0] : members[0]?.userId;
    const meta = {
      conversationId: conversation.id,
      name: `${type} ${conversation.id.slice(0, 8)}`,
      createdByUserId,
      isPublic: options.isPublic,
      memberLimit: options.memberLimit,
    };
    if (type === 'group') this.insertGroupMeta(meta);
    if (type === 'channel') this.insertChannelMeta(meta);
    return conversation.id;
  }

  // Interactive transactions run the callback against the fake directly.
  // There is no rollback. Increments ({ increment: n }) apply synchronously,
  // so concurrent transactions see the same per-row serialization that the
  // Postgres row lock gives conversations.last_order.
  async $transaction<T>(callback: (tx: this) => Promise<T>, _options?: unknown): Promise<T> {
    return callback(this);
  }

  private delegate(model: ModelName, insert: (data: any) => Row) {
    const create = async ({ data, select, include }: any) =>
      this.project(model, insert(data), { select, include });
    const findFirst = async (args: any = {}) => {
      const [row] = this.findRows(model, { ...args, take: 1 });
      return row ? this.project(model, row, args) : null;
    };
    return {
      create,
      createMany: async ({ data }: any) => {
        for (const item of data) insert(item);
        return { count: data.length };
      },
      findMany: async (args: any = {}) =>
        this.findRows(model, args).map((row) => this.project(model, row, args)),
      findFirst,
      findUnique: findFirst,
      count: async (args: any = {}) => this.findRows(model, args).length,
      update: async ({ where, data, select, include }: any) => {
        const row = this.requireRow(model, where);
        this.applyData(row, data);
        return this.project(model, row, { select, include });
      },
      updateMany: async ({ where, data }: any) => {
        const rows = this.findRows(model, { where });
        for (const row of rows) this.applyData(row, data);
        return { count: rows.length };
      },
      upsert: async ({ where, update, create: createData, select, include }: any) => {
        const [row] = this.findRows(model, { where });
        if (!row) return create({ data: createData, select, include });
        this.applyData(row, update);
        return this.project(model, row, { select, include });
      },
      delete: async ({ where }: any) => {
        const row = this.requireRow(model, where);
        this.removeRows(model, [row]);
        return { ...row };
      },
      deleteMany: async ({ where }: any = {}) => {
        const rows = this.findRows(model, { where });
        this.removeRows(model, rows);
        return { count: rows.length };
      },
    };
  }

  private insertConversation(data: any): ConversationRecord {
    // Mirror the unique index on direct_key — a duplicate insert from
    // concurrent createDirect calls should surface as P2002 so the
    // service's catch-and-lookup branch behaves the same in tests.
    if (data.directKey && this.conversations.some((c) => c.directKey === data.directKey)) {
      throw uniqueViolation('direct_key');
    }
    const record: ConversationRecord = {
      id: makeId('conv'),
      type: data.type ?? 'direct',
      createdAt: new Date(),
      directKey: data.directKey ?? null,
      currentEpoch: data.currentEpoch ?? 0,
      groupUseSenderKeys: data.groupUseSenderKeys ?? false,
      disappearingTimerSeconds: data.disappearingTimerSeconds ?? null,
      lastOrder: 0,
    };
    this.conversations.push(record);
    for (const member of data.members?.create ?? []) {
      this.insertMember({ ...member, conversationId: record.id });
    }
    if (data.groupMeta?.create) {
      this.insertGroupMeta({ ...data.groupMeta.create, conversationId: record.id });
    }
    if (data.channelMeta?.create) {
      this.insertChannelMeta({ ...data.channelMeta.create, conversationId: record.id });
    }
    return record;
  }

  private insertMember(data: any): ConversationMemberRecord {
    if (
      this.conversationMembers.some(
        (m) => m.conversationId === data.conversationId && m.userId === data.userId,
      )
    ) {
      throw uniqueViolation('conversation_id, user_id');
    }
    const record: ConversationMemberRecord = {
      id: makeId('member'),
      conversationId: data.conversationId,
      userId: data.userId,
      role: data.role ?? 'member',
      joinedAt: data.joinedAt ?? new Date(),
    };
    this.conversationMembers.push(record);
    return record;
  }

  private insertGroupMeta(data: any): GroupMetaRecord {
    const record: GroupMetaRecord = {
      id: makeId('group-meta'),
      conversationId: data.conversationId,
      name: data.name,
      description: data.description ?? null,
      avatarPath: data.avatarPath ?? null,
      createdByUserId: data.createdByUserId,
      isPublic: data.isPublic ?? false,
      memberLimit: data.memberLimit ?? 500,
      link: data.link ?? null,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    this.groupMetas.push(record);
    return record;
  }

  private insertChannelMeta(data: any): ChannelMetaRecord {
    const record: ChannelMetaRecord = {
      id: makeId('channel-meta'),
      conversationId: data.conversationId,
      name: data.name,
      description: data.description ?? null,
      avatarPath: data.avatarPath ?? null,
      createdByUserId: data.createdByUserId,
      isPublic: data.isPublic ?? false,
      subscriberCount: data.subscriberCount ?? 0,
      link: data.link ?? null,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    this.channelMetas.push(record);
    return record;
  }

  private insertMessage(data: any): MessageRecord {
    // Both unique indexes of the messages table: idempotency per sending
    // device, and one message per (conversation, order).
    if (
      this.messages.some(
        (m) =>
          m.senderDeviceId === data.senderDeviceId && m.clientMessageId === data.clientMessageId,
      )
    ) {
      throw uniqueViolation('sender_device_id, client_message_id');
    }
    if (
      this.messages.some(
        (m) =>
          m.conversationId === data.conversationId &&
          m.conversationOrder === data.conversationOrder,
      )
    ) {
      throw uniqueViolation('conversation_id, conversation_order');
    }
    const record: MessageRecord = {
      id: makeId('msg'),
      conversationId: data.conversationId,
      senderDeviceId: data.senderDeviceId,
      clientMessageId: data.clientMessageId,
      conversationOrder: data.conversationOrder,
      envelopeVersion: data.envelopeVersion ?? 'veil-envelope-v1',
      ciphertext: data.ciphertext,
      nonce: data.nonce,
      messageType: data.messageType,
      attachmentId: data.attachmentId ?? null,
      attachmentRef: this.toStoredValue(data.attachmentRef) ?? null,
      serverReceivedAt: data.serverReceivedAt ?? new Date(),
      deletedAt: null,
      expiresAt: data.expiresAt ?? null,
      replyToMessageId: data.replyToMessageId ?? null,
      editedAt: null,
      editCount: 0,
      viewOnce: data.viewOnce ?? false,
    };
    this.messages.push(record);
    for (const receipt of data.receipts?.create ?? []) {
      this.messageReceipts.push({
        id: makeId('receipt'),
        messageId: record.id,
        userId: receipt.userId,
        deliveredAt: receipt.deliveredAt ?? null,
        readAt: receipt.readAt ?? null,
      });
    }
    return record;
  }

  private table(model: ModelName): Row[] {
    switch (model) {
      case 'user':
        return this.users;
      case 'device':
        return this.devices;
      case 'attachment':
        return this.attachments;
      case 'conversation':
        return this.conversations;
      case 'conversationMember':
        return this.conversationMembers;
      case 'message':
        return this.messages;
      case 'messageReceipt':
        return this.messageReceipts;
      case 'reaction':
        return this.reactions;
      case 'groupMeta':
        return this.groupMetas;
      case 'channelMeta':
        return this.channelMetas;
      case 'groupMemberEpoch':
        return this.groupMemberEpochs;
      case 'callRecord':
        return this.callRecords;
    }
  }

  // Rows of a model with schema defaults filled in. A seeded conversation
  // without lastOrder starts from its highest message order, as the 0017
  // backfill does for existing rows.
  private rows(model: ModelName): Row[] {
    const rows = this.table(model);
    const defaults = ROW_DEFAULTS[model] ?? {};
    for (const row of rows) {
      for (const [key, value] of Object.entries(defaults)) {
        if (row[key] === undefined) row[key] = value;
      }
      if (model === 'conversation' && row.lastOrder === undefined) {
        row.lastOrder = this.messages
          .filter((message) => message.conversationId === row.id)
          .reduce((max, message) => Math.max(max, message.conversationOrder), 0);
      }
    }
    return rows;
  }

  private relation(model: ModelName, row: Row, name: string): RelationRows | undefined {
    const many = (target: ModelName, matches: (candidate: Row) => boolean): RelationRows => ({
      model: target,
      many: true,
      rows: this.rows(target).filter(matches),
    });
    const one = (target: ModelName, matches: (candidate: Row) => boolean): RelationRows => ({
      model: target,
      many: false,
      rows: this.rows(target).filter(matches).slice(0, 1),
    });

    switch (`${model}.${name}`) {
      case 'user.conversationRefs':
        return many('conversationMember', (m) => m.userId === row.id);
      case 'user.devices':
        return many('device', (d) => d.userId === row.id);
      case 'device.user':
        return one('user', (u) => u.id === row.userId);
      case 'attachment.uploaderDevice':
        return one('device', (d) => d.id === row.uploaderDeviceId);
      case 'conversation.members':
        return many('conversationMember', (m) => m.conversationId === row.id);
      case 'conversation.messages':
        return many('message', (m) => m.conversationId === row.id);
      case 'conversation.groupMeta':
        return one('groupMeta', (g) => g.conversationId === row.id);
      case 'conversation.channelMeta':
        return one('channelMeta', (c) => c.conversationId === row.id);
      case 'conversation.callRecords':
        return many('callRecord', (c) => c.conversationId === row.id);
      case 'conversationMember.conversation':
        return one('conversation', (c) => c.id === row.conversationId);
      case 'conversationMember.user':
        return one('user', (u) => u.id === row.userId);
      case 'message.conversation':
        return one('conversation', (c) => c.id === row.conversationId);
      case 'message.senderDevice':
        return one('device', (d) => d.id === row.senderDeviceId);
      case 'message.attachment':
        return one('attachment', (a) => a.id === row.attachmentId);
      case 'message.receipts':
        return many('messageReceipt', (r) => r.messageId === row.id);
      case 'message.reactions':
        return many('reaction', (r) => r.messageId === row.id);
      case 'groupMeta.conversation':
      case 'channelMeta.conversation':
      case 'callRecord.conversation':
        return one('conversation', (c) => c.id === row.conversationId);
      case 'callRecord.initiatorDevice':
        return one('device', (d) => d.id === row.initiatorDeviceId);
      default:
        return undefined;
    }
  }

  private findRows(model: ModelName, args: Row): Row[] {
    return this.applyListArgs(model, this.rows(model), args);
  }

  private applyListArgs(model: ModelName, rows: Row[], args: Row): Row[] {
    let result = args.where
      ? rows.filter((row) => this.matches(model, row, args.where))
      : [...rows];
    if (args.orderBy) {
      const rules: Row[] = Array.isArray(args.orderBy) ? args.orderBy : [args.orderBy];
      result.sort((left, right) => {
        for (const rule of rules) {
          const [field, direction] = Object.entries(rule)[0]!;
          const comparison = compareValues(left[field], right[field]);
          if (comparison !== 0) return direction === 'desc' ? -comparison : comparison;
        }
        return 0;
      });
    }
    if (args.skip) result = result.slice(args.skip);
    if (args.take !== undefined) result = result.slice(0, args.take);
    return result;
  }

  private matches(model: ModelName, row: Row, where: Row): boolean {
    return Object.entries(where).every(([key, filter]) => {
      if (filter === undefined) return true;
      if (key === 'OR') return (filter as Row[]).some((clause) => this.matches(model, row, clause));
      if (key === 'AND') {
        return ([] as Row[]).concat(filter).every((clause) => this.matches(model, row, clause));
      }
      if (key === 'NOT') {
        return !([] as Row[]).concat(filter).some((clause) => this.matches(model, row, clause));
      }
      const relation = this.relation(model, row, key);
      if (relation) return this.matchesRelation(relation, filter);
      // Compound unique selectors such as conversationId_userId.
      if (key.includes('_') && !(key in row) && isPlainObject(filter)) {
        return Object.entries(filter).every(([field, value]) =>
          this.matchesScalar(row[field], value),
        );
      }
      return this.matchesScalar(row[key], filter);
    });
  }

  private matchesRelation(relation: RelationRows, filter: any): boolean {
    const matchesTarget = (target: Row, clause: Row) =>
      this.matches(relation.model, target, clause);
    if (relation.many) {
      if (filter.some) return relation.rows.some((target) => matchesTarget(target, filter.some));
      if (filter.every) return relation.rows.every((target) => matchesTarget(target, filter.every));
      if (filter.none) return !relation.rows.some((target) => matchesTarget(target, filter.none));
      throw new Error(
        `FakePrismaService: unsupported list relation filter ${JSON.stringify(filter)}`,
      );
    }
    if (filter === null) return relation.rows.length === 0;
    const [target] = relation.rows;
    return target !== undefined && matchesTarget(target, filter);
  }

  private matchesScalar(value: any, filter: any): boolean {
    if (filter === null) return value === null || value === undefined;
    if (filter instanceof Date)
      return value instanceof Date && value.getTime() === filter.getTime();
    if (!isPlainObject(filter)) return value === filter;
    return Object.entries(filter).every(([operator, operand]) => {
      switch (operator) {
        case 'equals':
          return this.matchesScalar(value, operand);
        case 'not':
          return !this.matchesScalar(value, operand);
        case 'in':
          return (operand as unknown[]).includes(value);
        case 'notIn':
          return !(operand as unknown[]).includes(value);
        case 'lt':
          return value != null && value < operand;
        case 'lte':
          return value != null && value <= operand;
        case 'gt':
          return value != null && value > operand;
        case 'gte':
          return value != null && value >= operand;
        default:
          throw new Error(`FakePrismaService: unsupported filter operator "${operator}"`);
      }
    });
  }

  private project(model: ModelName, row: Row, args?: Row): Row {
    if (args?.select) return this.projectFields(model, row, args.select, {});
    return args?.include ? this.projectFields(model, row, args.include, { ...row }) : { ...row };
  }

  private projectFields(model: ModelName, row: Row, fields: Row, base: Row): Row {
    for (const [key, spec] of Object.entries(fields)) {
      if (!spec) continue;
      if (key === '_count') {
        base._count = this.countRelations(model, row, spec.select);
        continue;
      }
      const relation = this.relation(model, row, key);
      base[key] = relation
        ? this.projectRelation(relation, spec === true ? undefined : spec)
        : row[key];
    }
    return base;
  }

  private projectRelation(relation: RelationRows, spec?: Row): Row | Row[] | null {
    if (!relation.many) {
      const [target] = relation.rows;
      return target ? this.project(relation.model, target, spec) : null;
    }
    return this.applyListArgs(relation.model, relation.rows, spec ?? {}).map((target) =>
      this.project(relation.model, target, spec),
    );
  }

  private countRelations(model: ModelName, row: Row, select: Row): Row {
    return Object.fromEntries(
      Object.entries(select)
        .filter(([, spec]) => spec)
        .map(([key, spec]) => {
          const relation = this.relation(model, row, key)!;
          const where = spec === true ? undefined : spec.where;
          return [key, this.applyListArgs(relation.model, relation.rows, { where }).length];
        }),
    );
  }

  private requireRow(model: ModelName, where: Row): Row {
    const [row] = this.findRows(model, { where });
    if (!row) throw recordNotFound(model);
    return row;
  }

  private toStoredValue(value: unknown): unknown {
    return value === Prisma.JsonNull || value === Prisma.DbNull ? null : value;
  }

  private applyData(row: Row, data: Row): void {
    for (const [key, value] of Object.entries(data ?? {})) {
      if (value === undefined) continue;
      if (isPlainObject(value) && 'increment' in value) {
        row[key] = (row[key] ?? 0) + value.increment;
      } else if (isPlainObject(value) && 'decrement' in value) {
        row[key] = (row[key] ?? 0) - value.decrement;
      } else {
        row[key] = this.toStoredValue(value);
      }
    }
    if ('updatedAt' in row) row.updatedAt = new Date();
  }

  // Deletes rows in place and applies the schema's referential actions for
  // the relations the services rely on.
  private removeRows(model: ModelName, rows: Row[]): void {
    const table = this.table(model);
    for (const row of rows) {
      const index = table.indexOf(row);
      if (index >= 0) table.splice(index, 1);
    }
    if (model === 'message') {
      const removedIds = new Set(rows.map((row) => row.id));
      this.messageReceipts = this.messageReceipts.filter((r) => !removedIds.has(r.messageId));
      this.reactions = this.reactions.filter((r) => !removedIds.has(r.messageId));
      for (const message of this.messages) {
        if (message.replyToMessageId && removedIds.has(message.replyToMessageId)) {
          message.replyToMessageId = null;
        }
      }
    }
  }

  private pick(record: Record<string, any>, select: Record<string, boolean>): Record<string, any> {
    return Object.fromEntries(
      Object.entries(select)
        .filter(([, enabled]) => enabled)
        .map(([key]) => [key, record[key]]),
    );
  }
}
