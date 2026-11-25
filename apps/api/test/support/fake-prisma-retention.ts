import { randomUUID } from 'node:crypto';

import { Prisma } from '@prisma/client';

import { FakePrismaService } from './fake-prisma.service';

// FakePrismaService models each query shape by hand. The retention sweeps,
// the key directory and the story audience checks use generic
// filters (OR, relation filters, take, compound uniques) and tables it does
// not model, so this subclass evaluates the subset of Prisma's where-language
// those services use. An operator it does not know throws, so a test can
// never pass by silently ignoring part of a filter.

type Row = Record<string, any>;
type RelationFilter = (row: Row, filter: any) => boolean;

type StoryRecord = {
  id: string;
  userId: string;
  ciphertext: string;
  envelopeVersion: string;
  expiresAt: Date;
  createdAt: Date;
};

type StoryViewRecord = { id: string; storyId: string; viewerUserId: string; viewedAt: Date };

type StoryAudienceRecord = { storyId: string; userId: string };

type UserBlockRecord = { blockerUserId: string; blockedUserId: string; createdAt: Date };

type CallRecordRow = {
  id: string;
  conversationId: string;
  initiatorDeviceId: string;
  callType: 'voice' | 'video';
  status: 'ringing' | 'active' | 'ended' | 'missed' | 'declined';
  startedAt: Date;
  endedAt: Date | null;
  duration: number | null;
};

type AbuseReportRecord = {
  id: string;
  reporterUserId: string;
  reportedUserId: string;
  conversationId: string | null;
  messageId: string | null;
  reason: string;
  createdAt: Date;
};

type SecretBlobRecord = { id: string; ciphertext: string; createdAt: Date; expiresAt: Date };

const isNullSentinel = (value: unknown): boolean =>
  value === Prisma.AnyNull || value === Prisma.DbNull || value === Prisma.JsonNull;

const isPlainObject = (value: unknown): value is Row =>
  typeof value === 'object' &&
  value !== null &&
  !(value instanceof Date) &&
  !Array.isArray(value) &&
  !isNullSentinel(value);

function isEqual(value: unknown, operand: unknown): boolean {
  if (operand === Prisma.AnyNull) {
    return value === null || value === undefined || value === Prisma.JsonNull;
  }
  if (operand instanceof Date) {
    return value instanceof Date && value.getTime() === operand.getTime();
  }
  return (value ?? null) === operand;
}

// Batched sweeps filter thousands of rows by `id in [...1000 ids]`; a Set
// keeps that linear.
const membershipSets = new WeakMap<unknown[], Set<unknown> | null>();
function isMember(value: unknown, operand: unknown[]): boolean {
  if (!membershipSets.has(operand)) {
    const primitive = operand.every((item) => typeof item !== 'object' || item === null);
    membershipSets.set(operand, primitive ? new Set(operand) : null);
  }
  const members = membershipSets.get(operand);
  return members ? members.has(value ?? null) : operand.some((item) => isEqual(value, item));
}

function matchesField(value: any, condition: unknown): boolean {
  if (!isPlainObject(condition)) {
    return isEqual(value, condition);
  }
  return Object.entries(condition).every(([operator, operand]) => {
    switch (operator) {
      case 'equals':
        return isEqual(value, operand);
      case 'not':
        return isPlainObject(operand) ? !matchesField(value, operand) : !isEqual(value, operand);
      case 'in':
        return isMember(value, operand as unknown[]);
      case 'notIn':
        return !isMember(value, operand as unknown[]);
      case 'lt':
        return value != null && value < (operand as any);
      case 'lte':
        return value != null && value <= (operand as any);
      case 'gt':
        return value != null && value > (operand as any);
      case 'gte':
        return value != null && value >= (operand as any);
      default:
        throw new Error(`fake prisma: unsupported operator '${operator}'`);
    }
  });
}

function matchesWhere(
  row: Row,
  where: Row | undefined,
  relations: Record<string, RelationFilter> = {},
): boolean {
  if (!where) return true;
  return Object.entries(where).every(([key, condition]) => {
    if (key === 'AND') {
      return [condition].flat().every((clause: Row) => matchesWhere(row, clause, relations));
    }
    if (key === 'OR') {
      return (condition as Row[]).some((clause) => matchesWhere(row, clause, relations));
    }
    if (key === 'NOT') {
      return ![condition].flat().some((clause: Row) => matchesWhere(row, clause, relations));
    }
    if (key in relations) {
      return relations[key](row, condition);
    }
    return matchesField(row[key], condition);
  });
}

function matchesList(
  rows: Row[],
  filter: Row,
  relations?: Record<string, RelationFilter>,
): boolean {
  if (filter.some) return rows.some((row) => matchesWhere(row, filter.some, relations));
  if (filter.none) return !rows.some((row) => matchesWhere(row, filter.none, relations));
  if (filter.every) return rows.every((row) => matchesWhere(row, filter.every, relations));
  throw new Error(`fake prisma: unsupported list filter ${JSON.stringify(Object.keys(filter))}`);
}

function pick(row: Row, select?: Row): Row {
  if (!select) return { ...row };
  return Object.fromEntries(
    Object.entries(select)
      .filter(([, enabled]) => enabled)
      .map(([key]) => [key, row[key]]),
  );
}

function sortRows<T extends Row>(rows: T[], orderBy?: Row | Row[]): T[] {
  const rules = orderBy ? [orderBy].flat() : [];
  return [...rows].sort((left, right) => {
    for (const rule of rules) {
      const [key, direction] = Object.entries(rule)[0];
      const comparison = left[key] < right[key] ? -1 : left[key] > right[key] ? 1 : 0;
      if (comparison !== 0) return direction === 'desc' ? -comparison : comparison;
    }
    return 0;
  });
}

// Compound unique selectors (`{ a_b: { a, b } }`) become plain equality.
function flattenUnique(where: Row): Row {
  return Object.fromEntries(
    Object.entries(where).flatMap(([key, value]) =>
      key.includes('_') && isPlainObject(value) ? Object.entries(value) : [[key, value]],
    ),
  );
}

interface TableOptions<T extends Row> {
  rows: () => T[];
  replace: (rows: T[]) => void;
  create?: (data: Row) => T;
  relations?: () => Record<string, RelationFilter>;
  hydrate?: (row: T, include: Row) => Row;
}

function table<T extends Row>(options: TableOptions<T>) {
  const relations = () => options.relations?.() ?? {};
  const matching = (where?: Row) =>
    options.rows().filter((row) => matchesWhere(row, where, relations()));
  const project = (row: T, args: Row): Row =>
    args.include && options.hydrate ? options.hydrate(row, args.include) : pick(row, args.select);

  return {
    findMany: async (args: Row = {}) =>
      sortRows(matching(args.where), args.orderBy)
        .slice(0, args.take ?? undefined)
        .map((row) => project(row, args)),
    findFirst: async (args: Row = {}) => {
      const [row] = sortRows(matching(args.where), args.orderBy);
      return row ? project(row, args) : null;
    },
    findUnique: async (args: Row) => {
      const [row] = matching(flattenUnique(args.where));
      return row ? project(row, args) : null;
    },
    count: async (args: Row = {}) => matching(args.where).length,
    create: async (args: Row) => {
      if (!options.create) throw new Error('fake prisma: create not modelled for this table');
      const row = options.create(args.data);
      options.rows().push(row);
      return project(row, args);
    },
    upsert: async (args: Row) => {
      const [row] = matching(flattenUnique(args.where));
      if (row) {
        Object.assign(row, args.update);
        return project(row, args);
      }
      if (!options.create) throw new Error('fake prisma: create not modelled for this table');
      const created = options.create(args.create);
      options.rows().push(created);
      return project(created, args);
    },
    updateMany: async (args: Row) => {
      const rows = matching(args.where);
      for (const row of rows) Object.assign(row, args.data);
      return { count: rows.length };
    },
    delete: async (args: Row) => {
      const [row] = matching(flattenUnique(args.where));
      if (!row) throw Object.assign(new Error('Record not found'), { code: 'P2025' });
      options.replace(options.rows().filter((item) => item !== row));
      return row;
    },
    deleteMany: async (args: Row = {}) => {
      const doomed = new Set(matching(args.where));
      options.replace(options.rows().filter((row) => !doomed.has(row)));
      return { count: doomed.size };
    },
  };
}

export class RetentionFakePrismaService extends FakePrismaService {
  stories: StoryRecord[] = [];
  storyViews: StoryViewRecord[] = [];
  storyAudiences: StoryAudienceRecord[] = [];
  userBlocks: UserBlockRecord[] = [];
  callRecords: CallRecordRow[] = [];
  abuseReports: AbuseReportRecord[] = [];
  secretBlobs: SecretBlobRecord[] = [];

  /** What pg_try_advisory_xact_lock answers for the retention sweep. */
  retentionLockAvailable = true;
  readonly rawQueries: string[] = [];
  /** $transaction callbacks still running, so tests can see what runs inside one. */
  openTransactions = 0;

  story = table<StoryRecord>({
    rows: () => this.stories,
    replace: (rows) => (this.stories = rows),
    create: (data) => {
      const id = randomUUID();
      for (const member of data.audience?.create ?? []) {
        this.storyAudiences.push({ storyId: id, userId: member.userId });
      }
      return {
        id,
        userId: data.userId,
        ciphertext: data.ciphertext,
        envelopeVersion: data.envelopeVersion,
        expiresAt: data.expiresAt,
        createdAt: new Date(),
      };
    },
    relations: () => ({
      audience: (story, filter) =>
        matchesList(
          this.storyAudiences.filter((member) => member.storyId === story.id),
          filter,
        ),
    }),
    hydrate: (story, include) => {
      const views = this.storyViews.filter((view) => view.storyId === story.id);
      const author = this.users.find((user) => user.id === story.userId)!;
      return {
        ...story,
        user: pick(author, include.user?.select),
        views: views
          .filter((view) => matchesWhere(view, include.views?.where))
          .map((view) => pick(view, include.views?.select)),
        _count: { views: views.length },
      };
    },
  });

  storyAudience = table<StoryAudienceRecord>({
    rows: () => this.storyAudiences,
    replace: (rows) => (this.storyAudiences = rows),
  });

  storyView = table<StoryViewRecord>({
    rows: () => this.storyViews,
    replace: (rows) => (this.storyViews = rows),
    create: (data) => ({
      id: randomUUID(),
      storyId: data.storyId,
      viewerUserId: data.viewerUserId,
      viewedAt: new Date(),
    }),
  });

  secretBlob = table<SecretBlobRecord>({
    rows: () => this.secretBlobs,
    replace: (rows) => (this.secretBlobs = rows),
  });

  oneTimePrekey = table({
    rows: () => this.oneTimePrekeys,
    replace: (rows) => (this.oneTimePrekeys = rows),
  });

  constructor() {
    super();

    const conversationRelations = (): Record<string, RelationFilter> => ({
      members: (conversation, filter) =>
        matchesList(
          this.conversationMembers.filter((member) => member.conversationId === conversation.id),
          filter,
        ),
    });
    const conversationOf: RelationFilter = (row, filter) => {
      const conversation = this.conversations.find((item) => item.id === row.conversationId);
      return (
        conversation !== undefined && matchesWhere(conversation, filter, conversationRelations())
      );
    };

    // The base fake models call records for the calls flow; retention only needs
    // the generic where-matching table, so its queries replace the base ones.
    Object.assign(
      this.callRecord,
      table<CallRecordRow>({
        rows: () => this.callRecords,
        replace: (rows) => (this.callRecords = rows),
      }),
    );

    const messages = table({
      rows: () => this.messages,
      replace: (rows) => (this.messages = rows),
      relations: () => ({ conversation: conversationOf }),
    });
    // History reads include relations (sender, receipts), which the base
    // engine projects; the sweeps' selects need this table's operators.
    const listWithRelations = this.message.findMany;
    const findFirstWithRelations = this.message.findFirst;
    Object.assign(this.message, {
      findMany: (args: Row = {}) =>
        args.include ? listWithRelations(args) : messages.findMany(args),
      findFirst: (args: Row = {}) =>
        args.include ? findFirstWithRelations(args) : messages.findFirst(args),
      deleteMany: messages.deleteMany,
    });

    const attachments = table({
      rows: () => this.attachments,
      replace: (rows) => (this.attachments = rows),
      relations: () => ({
        messages: (attachment, filter) =>
          matchesList(
            this.messages.filter((message) => message.attachmentId === attachment.id),
            filter,
          ),
      }),
    });
    Object.assign(this.attachment, {
      findMany: attachments.findMany,
      deleteMany: attachments.deleteMany,
    });

    const receipts = table({
      rows: () => this.messageReceipts,
      replace: (rows) => (this.messageReceipts = rows),
    });
    Object.assign(this.messageReceipt, {
      findMany: receipts.findMany,
      deleteMany: receipts.deleteMany,
    });

    const reports = table<AbuseReportRecord>({
      rows: () => this.abuseReports,
      replace: (rows) => (this.abuseReports = rows),
      create: (data) => ({
        id: randomUUID(),
        reporterUserId: data.reporterUserId,
        reportedUserId: data.reportedUserId,
        conversationId: data.conversationId ?? null,
        messageId: data.messageId ?? null,
        reason: data.reason,
        createdAt: new Date(),
      }),
    });
    Object.assign(this.abuseReport, {
      create: reports.create,
      findMany: reports.findMany,
      deleteMany: reports.deleteMany,
    });

    const blocks = table<UserBlockRecord>({
      rows: () => this.userBlocks,
      replace: (rows) => (this.userBlocks = rows),
      create: (data) => ({
        blockerUserId: data.blockerUserId,
        blockedUserId: data.blockedUserId,
        createdAt: new Date(),
      }),
      hydrate: (block, include) => ({
        ...block,
        blocked: pick(
          this.users.find((user) => user.id === block.blockedUserId)!,
          include.blocked?.select,
        ),
      }),
    });
    Object.assign(this.userBlock, {
      findFirst: blocks.findFirst,
      findMany: blocks.findMany,
      upsert: blocks.upsert,
    });

    const contacts = table({
      rows: () => this.userContacts,
      replace: (rows) => (this.userContacts = rows),
      hydrate: (contact, include) => ({
        ...contact,
        contactUser: pick(
          this.users.find((user) => user.id === contact.contactUserId)!,
          include.contactUser?.select,
        ),
      }),
    });
    Object.assign(this.userContact, { findMany: contacts.findMany });

    // The revoked-device sweep filters on the rows that still reference a
    // device; queries that include relations keep the base engine.
    const devices = table({
      rows: () => this.devices,
      replace: (rows) => (this.devices = rows),
      relations: () => ({
        sentMessages: (device, filter) =>
          matchesList(
            this.messages.filter((message) => message.senderDeviceId === device.id),
            filter,
          ),
        attachments: (device, filter) =>
          matchesList(
            this.attachments.filter((attachment) => attachment.uploaderDeviceId === device.id),
            filter,
          ),
        initiatedCalls: (device, filter) =>
          matchesList(
            this.callRecords.filter((call) => call.initiatorDeviceId === device.id),
            filter,
          ),
      }),
    });
    const listDevicesWithRelations = this.device.findMany;
    Object.assign(this.device, {
      findMany: (args: Row = {}) =>
        args.include ? listDevicesWithRelations(args) : devices.findMany(args),
      deleteMany: devices.deleteMany,
    });

    const members = table({
      rows: () => this.conversationMembers,
      replace: (rows) => (this.conversationMembers = rows),
      relations: () => ({ conversation: conversationOf }),
    });
    Object.assign(this.conversationMember, { findFirst: members.findFirst });
  }

  async $transaction<T>(callback: (tx: this) => Promise<T>, options?: unknown): Promise<T> {
    this.openTransactions += 1;
    try {
      return await super.$transaction(callback, options);
    } finally {
      this.openTransactions -= 1;
    }
  }

  async $queryRaw<T>(query: TemplateStringsArray, ..._values: unknown[]): Promise<T> {
    this.rawQueries.push(query.join('?'));
    return [{ acquired: this.retentionLockAvailable }] as T;
  }

  async addUser(handle: string): Promise<string> {
    const user = await this.user.create({ data: { handle } });
    return user.id;
  }

  async addDevice(userId: string, overrides: Row = {}): Promise<string> {
    const device = await this.device.create({
      data: {
        userId,
        platform: 'android',
        deviceName: 'Test device',
        publicIdentityKey: `ik-${randomUUID()}`,
        signedPrekeyBundle: `spk-${randomUUID()}`,
        authPublicKey: `auth-${randomUUID()}`,
        ...overrides,
      },
    });
    await this.user.update({ where: { id: userId }, data: { activeDeviceId: device.id } });
    return device.id;
  }

  addContact(userId: string, contactUserId: string): void {
    this.userContacts.push({
      id: randomUUID(),
      userId,
      contactUserId,
      createdAt: new Date(),
    });
  }

  addMutualContacts(userIdA: string, userIdB: string): void {
    this.addContact(userIdA, userIdB);
    this.addContact(userIdB, userIdA);
  }

  addBlock(blockerUserId: string, blockedUserId: string): void {
    this.userBlocks.push({ blockerUserId, blockedUserId, createdAt: new Date() });
  }

  async addConversation(
    type: 'direct' | 'group' | 'channel',
    memberUserIds: string[],
  ): Promise<string> {
    const conversation = await this.conversation.create({
      data: { type, members: { create: memberUserIds.map((userId) => ({ userId })) } },
    });
    return conversation.id;
  }
}
