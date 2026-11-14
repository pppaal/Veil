import { ConversationAccessService } from '../../src/common/conversation-access/conversation-access.service';
import { AppLoggerService } from '../../src/common/logger/app-logger.service';
import { PrismaService } from '../../src/common/prisma.service';
import { AccountService } from '../../src/modules/account/account.service';
import { ConversationsService } from '../../src/modules/conversations/conversations.service';
import { CreateDirectConversationDto } from '../../src/modules/conversations/dto/create-direct-conversation.dto';
import { GroupsService } from '../../src/modules/groups/groups.service';
import { RetiredHandlesService } from '../../src/modules/handles/retired-handles.service';
import {
  FakeAttachmentStorageGateway,
  FakeEphemeralStoreService,
  FakeRealtimeGateway,
  FakeSafetyService,
} from '../support/fake-services';
import { conversation, device, directKey, id, users } from '../support/sql-rows';
import { ThrowawayPostgres, findPostgresBinDir } from '../support/throwaway-postgres';

// Account deletion through the real Prisma client on a real Postgres with the
// full migrated schema, so the direct-key search is the SQL Prisma actually
// sends (LIKE on direct_key), not the in-memory fake's reading of it. Needs
// the Postgres server binaries (see throwaway-postgres.ts).

const ALICE = id(0xa);
const BOB = id(0xb);
const CAROL = id(0xc);
const DAVE = id(0xd);
const ALICE_PHONE = id(0xa1);
const BOB_PHONE = id(0xb1);
const CAROL_PHONE = id(0xc1);
const AB = id(0x1ab0);
const AC = id(0x1ac0);
const BC = id(0x1bc0);
const GROUP = id(0x1ff0);
const AD = id(0x1ad0);

const postgresBinDir = findPostgresBinDir();
const describeWithPostgres = postgresBinDir ? describe : describe.skip;
if (!postgresBinDir) {
  console.warn('account-deletion-postgres.spec: no Postgres server binaries found; skipped');
}

describeWithPostgres('AccountService.deleteAccount on Postgres', () => {
  let postgres: ThrowawayPostgres;
  const clients: PrismaService[] = [];

  beforeAll(() => {
    postgres = ThrowawayPostgres.start(postgresBinDir as string);
  }, 60_000);

  afterAll(async () => {
    await Promise.all(clients.map((client) => client.$disconnect()));
    postgres?.stop();
  });

  const client = (database: string) => {
    const prisma = new PrismaService({ datasourceUrl: postgres.connectionUrl(database) });
    clients.push(prisma);
    return prisma;
  };

  // Resolves once some session of the cluster is waiting for a lock. A row
  // lock is waited for on the holder's transaction id, a lock that names no
  // database; the tests in this file run one at a time on their own cluster.
  const someoneWaitsForALock = async (database: string) => {
    const deadline = Date.now() + 20_000;
    for (;;) {
      const [[waiting]] = postgres.query(
        database,
        'SELECT count(*) FROM pg_locks WHERE NOT granted;',
      );
      if (Number(waiting) > 0) return;
      if (Date.now() > deadline) throw new Error('no session ever waited for a lock');
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
  };

  // A transaction on its own connection that stays open until released.
  const openTransaction = (prisma: PrismaService, work: (tx: any) => Promise<unknown>) => {
    let release!: () => void;
    const released = new Promise<void>((resolve) => (release = resolve));
    let ready!: () => void;
    const started = new Promise<void>((resolve) => (ready = resolve));
    const done = prisma.$transaction(
      async (tx) => {
        await work(tx);
        ready();
        await released;
      },
      { timeout: 30_000, maxWait: 30_000 },
    );
    return { started, release, done };
  };

  const setup = (database: string, seed: string) => {
    postgres.createDatabase(database);
    postgres.migrate(database);
    postgres.query(database, seed);
    const prisma = client(database);
    const account = new AccountService(
      prisma,
      { disconnectUser: () => 0 } as never,
      new FakeAttachmentStorageGateway() as never,
      new RetiredHandlesService(prisma, { retiredHandlePepper: 'postgres-spec-pepper' } as never),
      new AppLoggerService(),
      { forgetDevice: async () => undefined } as never,
    );
    const conversations = () =>
      postgres.query(
        database,
        `SELECT c.id, c.type, coalesce(c.direct_key, '-'), string_agg(m.user_id::text, ',' ORDER BY m.user_id)
           FROM conversations c LEFT JOIN conversation_members m ON m.conversation_id = c.id
          GROUP BY c.id ORDER BY c.id;`,
      );
    const directConversations = new ConversationsService(
      prisma,
      { emitConversationMembers: () => undefined } as never,
      { isBlockedEitherWay: async () => false } as never,
      {} as never,
    );
    const safety = new FakeSafetyService();
    const groups = new GroupsService(
      prisma,
      new FakeRealtimeGateway() as never,
      new FakeEphemeralStoreService() as never,
      new ConversationAccessService(prisma, safety as never),
      safety as never,
    );
    return { account, conversations, directConversations, groups };
  };

  const groupState = (database: string) =>
    postgres.query(
      database,
      `SELECT c.id, gm.created_by_user_id,
              string_agg(m.user_id::text || ':' || m.role, ',' ORDER BY m.user_id),
              (SELECT count(*) FROM messages msg WHERE msg.conversation_id = c.id)
         FROM conversations c
         JOIN group_metas gm ON gm.conversation_id = c.id
         LEFT JOIN conversation_members m ON m.conversation_id = c.id
        WHERE c.type = 'group'
        GROUP BY c.id, gm.created_by_user_id ORDER BY c.id;`,
    );

  const groupSeed = [
    users([ALICE, 'alice'], [BOB, 'bob'], [CAROL, 'carol']),
    device(ALICE_PHONE, ALICE),
    device(BOB_PHONE, BOB),
    device(CAROL_PHONE, CAROL),
  ].join('\n');

  const sendFromBob = (database: string, conversationId: string) =>
    postgres.query(
      database,
      `INSERT INTO messages (id, conversation_id, sender_device_id, client_message_id, conversation_order, ciphertext, nonce, message_type)
       VALUES (gen_random_uuid(), '${conversationId}', '${BOB_PHONE}', 'bob-1', 1, 'ct', 'n', 'text');`,
    );

  it('keeps a group its creator handed over and left when the creator deletes their account', async () => {
    const { account, groups } = setup('transferred_group', groupSeed);
    const auth = (userId: string, deviceId: string) => ({ userId, deviceId, handle: 'caller' });
    const { id: groupId } = await groups.createGroup(auth(ALICE, ALICE_PHONE), {
      name: 'book club',
      memberHandles: ['bob', 'carol'],
    });
    await groups.transferOwnership(auth(ALICE, ALICE_PHONE), groupId, { userId: BOB });
    await groups.leaveGroup(auth(ALICE, ALICE_PHONE), groupId);
    sendFromBob('transferred_group', groupId);

    await expect(account.deleteAccount(ALICE)).resolves.toEqual({ deleted: true });

    expect(groupState('transferred_group')).toEqual([
      [groupId, BOB, [`${BOB}:owner`, `${CAROL}:member`].join(','), '1'],
    ]);
  });

  it("deletes a group with its current owner's account, not with its creator's", async () => {
    const { account, groups } = setup('owner_deleted', groupSeed);
    const auth = (userId: string, deviceId: string) => ({ userId, deviceId, handle: 'caller' });
    const { id: groupId } = await groups.createGroup(auth(ALICE, ALICE_PHONE), {
      name: 'book club',
      memberHandles: ['bob', 'carol'],
    });
    await groups.transferOwnership(auth(ALICE, ALICE_PHONE), groupId, { userId: BOB });
    sendFromBob('owner_deleted', groupId);

    await expect(account.deleteAccount(BOB)).resolves.toEqual({ deleted: true });

    // The same outcome as an owner who never handed the group over: no group
    // is left behind without an owner.
    expect(groupState('owner_deleted')).toEqual([]);
  });

  const seed = [
    users([ALICE, 'alice'], [BOB, 'bob'], [CAROL, 'carol'], [DAVE, 'dave']),
    device(ALICE_PHONE, ALICE),
    device(BOB_PHONE, BOB),
    device(CAROL_PHONE, CAROL),
    conversation(AB, 'direct', [ALICE, BOB]),
    conversation(AC, 'direct', [ALICE, CAROL]),
    conversation(BC, 'direct', [BOB, CAROL]),
    conversation(GROUP, 'group', [ALICE, BOB, CAROL]),
  ].join('\n');

  it('releases the keys of the direct conversations the user is in', async () => {
    const { account, conversations } = setup('member_keys', seed);

    await expect(account.deleteAccount(ALICE)).resolves.toEqual({ deleted: true });

    expect(conversations()).toEqual([
      [AB, 'direct', '-', BOB],
      [AC, 'direct', '-', CAROL],
      [BC, 'direct', directKey(BOB, CAROL), [BOB, CAROL].sort().join(',')],
      [GROUP, 'group', '-', [BOB, CAROL].sort().join(',')],
    ]);
  });

  it('releases keys that name the user after their direct memberships are already gone', async () => {
    // A deletion that failed under an earlier release: its Phase 2 deleted
    // every membership of hers, direct ones included, and left the user row
    // 'revoked'. The retry has no membership to find these conversations by.
    const { account, conversations } = setup(
      'orphaned_keys',
      [
        seed,
        `UPDATE users SET status = 'revoked' WHERE id = '${ALICE}';`,
        `DELETE FROM conversation_members WHERE user_id = '${ALICE}';`,
      ].join('\n'),
    );

    await expect(account.deleteAccount(ALICE)).resolves.toEqual({ deleted: true });

    expect(conversations()).toEqual([
      [AB, 'direct', '-', BOB],
      [AC, 'direct', '-', CAROL],
      // Bob and Carol's key names neither Alice nor anyone gone: untouched.
      [BC, 'direct', directKey(BOB, CAROL), [BOB, CAROL].sort().join(',')],
      [GROUP, 'group', '-', [BOB, CAROL].sort().join(',')],
    ]);
  });

  it('releases the key of a direct conversation opened while the deletion runs', async () => {
    // Dave's createDirect read Alice as active before the deletion revoked
    // her, and its insert lands while the deletion is under way: its
    // conversation is still uncommitted when the deletion's final step
    // begins, and commits while that step waits to delete her user row.
    const { account, conversations } = setup('concurrent_direct', seed);
    const dave = openTransaction(client('concurrent_direct'), (tx) =>
      tx.conversation.create({
        data: {
          id: AD,
          type: 'direct',
          directKey: directKey(ALICE, DAVE),
          members: { create: [{ userId: ALICE }, { userId: DAVE }] },
        },
      }),
    );
    await dave.started;

    const deletion = account.deleteAccount(ALICE);
    await someoneWaitsForALock('concurrent_direct');
    dave.release();
    await dave.done;
    await expect(deletion).resolves.toEqual({ deleted: true });

    expect(conversations()).toEqual([
      [AB, 'direct', '-', BOB],
      [AC, 'direct', '-', CAROL],
      [AD, 'direct', '-', DAVE],
      [BC, 'direct', directKey(BOB, CAROL), [BOB, CAROL].sort().join(',')],
      [GROUP, 'group', '-', [BOB, CAROL].sort().join(',')],
    ]);
  });

  it('answers createDirect with handle_not_found when the peer row is deleted under it, and keeps nothing', async () => {
    // The other order: the deletion's final step has deleted Dave's row but
    // not committed when Bob's createDirect, which read Dave as active,
    // inserts the membership. Its foreign-key check waits, then fails.
    const { directConversations, conversations } = setup('deleted_under_create', seed);
    const deletion = openTransaction(client('deleted_under_create'), (tx) =>
      tx.user.delete({ where: { id: DAVE } }),
    );
    await deletion.started;

    const dto = new CreateDirectConversationDto();
    dto.peerHandle = 'dave';
    const created = directConversations.createDirect(BOB, dto);
    // Keep the outcome observed so a rejection is not reported as unhandled
    // while the deletion still holds Dave's row.
    created.catch(() => undefined);
    await someoneWaitsForALock('deleted_under_create');
    deletion.release();
    await deletion.done;

    await expect(created).rejects.toMatchObject({
      status: 404,
      response: { code: 'handle_not_found' },
    });
    expect(conversations().map(([conversationId]) => conversationId)).toEqual([AB, AC, BC, GROUP]);
  });
});
