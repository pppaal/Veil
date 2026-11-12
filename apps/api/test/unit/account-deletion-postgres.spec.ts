import { AppLoggerService } from '../../src/common/logger/app-logger.service';
import { PrismaService } from '../../src/common/prisma.service';
import { AccountService } from '../../src/modules/account/account.service';
import { RetiredHandlesService } from '../../src/modules/handles/retired-handles.service';
import { FakeAttachmentStorageGateway } from '../support/fake-services';
import { conversation, device, directKey, id, users } from '../support/sql-rows';
import { ThrowawayPostgres, findPostgresBinDir } from '../support/throwaway-postgres';

// Account deletion through the real Prisma client on a real Postgres with the
// full migrated schema, so the direct-key search is the SQL Prisma actually
// sends (LIKE on direct_key), not the in-memory fake's reading of it. Needs
// the Postgres server binaries (see throwaway-postgres.ts).

const ALICE = id(0xa);
const BOB = id(0xb);
const CAROL = id(0xc);
const ALICE_PHONE = id(0xa1);
const BOB_PHONE = id(0xb1);
const CAROL_PHONE = id(0xc1);
const AB = id(0x1ab0);
const AC = id(0x1ac0);
const BC = id(0x1bc0);
const GROUP = id(0x1ff0);

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

  const setup = (database: string, seed: string) => {
    postgres.createDatabase(database);
    postgres.migrate(database);
    postgres.query(database, seed);
    const prisma = new PrismaService({ datasourceUrl: postgres.connectionUrl(database) });
    clients.push(prisma);
    const account = new AccountService(
      prisma,
      { disconnectUser: () => 0 } as never,
      new FakeAttachmentStorageGateway() as never,
      new RetiredHandlesService(prisma, { retiredHandlePepper: 'postgres-spec-pepper' } as never),
      new AppLoggerService(),
    );
    const conversations = () =>
      postgres.query(
        database,
        `SELECT c.id, c.type, coalesce(c.direct_key, '-'), string_agg(m.user_id::text, ',' ORDER BY m.user_id)
           FROM conversations c LEFT JOIN conversation_members m ON m.conversation_id = c.id
          GROUP BY c.id ORDER BY c.id;`,
      );
    return { account, conversations };
  };

  const seed = [
    users([ALICE, 'alice'], [BOB, 'bob'], [CAROL, 'carol']),
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
});
