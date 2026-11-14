import type { AppConfigService } from '../../src/common/config/app-config.service';
import { ConversationAccessService } from '../../src/common/conversation-access/conversation-access.service';
import { utcDayStart } from '../../src/common/device-activity';
import { revokeDevice } from '../../src/common/device-revocation';
import { EphemeralStoreService } from '../../src/common/ephemeral-store.service';
import { PrismaService } from '../../src/common/prisma.service';
import { GroupsService } from '../../src/modules/groups/groups.service';
import { DirectoryBudget } from '../../src/modules/prekeys/directory-budget';
import { MAX_UNCONSUMED_PREKEYS_PER_DEVICE } from '../../src/modules/prekeys/dto/upload-prekeys.dto';
import { PrekeysService } from '../../src/modules/prekeys/prekeys.service';
import {
  MAX_CIPHERTEXT_LENGTH,
  MAX_SECRET_BYTES_PER_CLIENT_DAY,
  MAX_STORED_SECRET_BYTES,
  MAX_STORED_SECRETS,
  MAX_TTL_SECONDS,
} from '../../src/modules/secret/dto/create-secret.dto';
import { SecretService } from '../../src/modules/secret/secret.service';
import {
  FakeEphemeralStoreService,
  FakeRealtimeGateway,
  FakeSafetyService,
} from '../support/fake-services';
import { device, id, users } from '../support/sql-rows';
import { ThrowawayPostgres, findPostgresBinDir } from '../support/throwaway-postgres';

// Invariants that only hold if the SQL Prisma sends does what the services
// assume: row locks, conditional updates, relation filters and raw queries,
// on a real Postgres with the full migrated schema. The in-memory fake runs
// one statement at a time and cannot show any of it. Needs the Postgres
// server binaries (see throwaway-postgres.ts).

const ALICE = id(0xa);
const BOB = id(0xb);
const CAROL = id(0xc);
const DAVE = id(0xd);
const ALICE_PHONE = id(0xa1);
const BOB_PHONE = id(0xb1);
const CAROL_PHONE = id(0xc1);
const DAVE_PHONE = id(0xd1);

const postgresBinDir = findPostgresBinDir();
const describeWithPostgres = postgresBinDir ? describe : describe.skip;
if (!postgresBinDir) {
  console.warn('relay-invariants-postgres.spec: no Postgres server binaries found; skipped');
}

describeWithPostgres('relay invariants on Postgres', () => {
  let postgres: ThrowawayPostgres;
  const clients: PrismaService[] = [];

  beforeAll(() => {
    postgres = ThrowawayPostgres.start(postgresBinDir as string);
  }, 60_000);

  afterAll(async () => {
    await Promise.all(clients.map((client) => client.$disconnect()));
    postgres?.stop();
  });

  const database = (name: string, seed: string): PrismaService => {
    postgres.createDatabase(name);
    postgres.migrate(name);
    postgres.query(name, seed);
    const prisma = new PrismaService({ datasourceUrl: postgres.connectionUrl(name) });
    clients.push(prisma);
    return prisma;
  };

  const people = [
    users([ALICE, 'alice'], [BOB, 'bob'], [CAROL, 'carol'], [DAVE, 'dave']),
    device(ALICE_PHONE, ALICE),
    device(BOB_PHONE, BOB),
    device(CAROL_PHONE, CAROL),
    device(DAVE_PHONE, DAVE),
  ].join('\n');

  const groupsService = (prisma: PrismaService) => {
    const safety = new FakeSafetyService();
    return new GroupsService(
      prisma,
      new FakeRealtimeGateway() as never,
      new FakeEphemeralStoreService() as never,
      new ConversationAccessService(prisma, safety as never),
      safety as never,
    );
  };
  const auth = (userId: string, deviceId: string) => ({ userId, deviceId, handle: 'caller' });

  // Resolves once at least `count` sessions of the cluster wait for a lock.
  const sessionsWaitForALock = async (name: string, count: number) => {
    const deadline = Date.now() + 20_000;
    for (;;) {
      const [[waiting]] = postgres.query(name, 'SELECT count(*) FROM pg_locks WHERE NOT granted;');
      if (Number(waiting) >= count) return;
      if (Date.now() > deadline) throw new Error(`fewer than ${count} sessions waited for a lock`);
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
  };

  // A transaction on its own connection that holds what `work` locked until
  // released.
  const holdLocks = async (prisma: PrismaService, work: (tx: any) => Promise<unknown>) => {
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
    await started;
    return { release, done };
  };

  it('two concurrent ownership transfers leave the group with exactly one owner', async () => {
    const prisma = database('ownership_race', people);
    const groups = groupsService(prisma);
    const { id: groupId } = await groups.createGroup(auth(ALICE, ALICE_PHONE), {
      name: 'book club',
      memberHandles: ['bob', 'carol', 'dave'],
    });

    // Holding the owner's membership row lets both transfers pass every
    // check made outside their transaction and then wait inside it, which is
    // the interleaving a real race needs.
    const lockHolder = new PrismaService({
      datasourceUrl: postgres.connectionUrl('ownership_race'),
    });
    clients.push(lockHolder);
    const holder = await holdLocks(
      lockHolder,
      (tx) =>
        tx.$queryRaw`SELECT 1 FROM conversation_members
                    WHERE conversation_id = ${groupId}::uuid AND user_id = ${ALICE}::uuid
                    FOR UPDATE`,
    );
    const transfers = Promise.allSettled([
      groups.transferOwnership(auth(ALICE, ALICE_PHONE), groupId, { userId: BOB }),
      groups.transferOwnership(auth(ALICE, ALICE_PHONE), groupId, { userId: CAROL }),
    ]);
    await sessionsWaitForALock('ownership_race', 2);
    holder.release();
    await holder.done;
    const results = await transfers;

    expect(results.map((result) => result.status).sort()).toEqual(['fulfilled', 'rejected']);
    expect(
      postgres.query(
        'ownership_race',
        `SELECT count(*) FROM conversation_members
          WHERE conversation_id = '${groupId}' AND role = 'owner';`,
      ),
    ).toEqual([['1']]);
  });

  // leaveGroup and removeMember refuse the owner on a role read outside their
  // transaction. A transfer to the leaving member that commits in between
  // must not let the departure delete the new owner and leave none.
  it.each([
    [
      'leaves',
      'departure_leave',
      (groups: GroupsService, groupId: string) => groups.leaveGroup(auth(BOB, BOB_PHONE), groupId),
    ],
    [
      'is removed by an admin',
      'departure_remove',
      (groups: GroupsService, groupId: string) =>
        groups.removeMember(auth(CAROL, CAROL_PHONE), groupId, 'bob'),
    ],
  ])(
    'a member who %s as ownership passes to them keeps the group its one owner',
    async (_case, name, depart) => {
      const prisma = database(name, people);
      const groups = groupsService(prisma);
      const { id: groupId } = await groups.createGroup(auth(ALICE, ALICE_PHONE), {
        name: 'book club',
        memberHandles: ['bob', 'carol'],
      });
      // Carol is an admin, so she can remove members whatever Alice's role is.
      postgres.query(
        name,
        `UPDATE conversation_members SET role = 'admin'
          WHERE conversation_id = '${groupId}' AND user_id = '${CAROL}';`,
      );
      const transferrer = new PrismaService({ datasourceUrl: postgres.connectionUrl(name) });
      clients.push(transferrer);

      // The transfer to Bob has written its swap and holds both rows while
      // the departure, which already passed its owner check, waits on Bob's.
      const transfer = await holdLocks(
        transferrer,
        (tx) =>
          tx.$executeRaw`UPDATE conversation_members
                            SET role = CASE WHEN user_id = ${ALICE}::uuid THEN 'member'::"MemberRole"
                                            ELSE 'owner'::"MemberRole" END
                          WHERE conversation_id = ${groupId}::uuid
                            AND user_id IN (${ALICE}::uuid, ${BOB}::uuid)`,
      );
      const departure = depart(groups, groupId).then(
        () => 'departed',
        (error: unknown) => error,
      );
      await sessionsWaitForALock(name, 1);
      transfer.release();
      await transfer.done;

      await expect(departure).resolves.toMatchObject({ response: { code: 'owner_immutable' } });
      expect(
        postgres.query(
          name,
          `SELECT user_id, role FROM conversation_members
            WHERE conversation_id = '${groupId}' ORDER BY user_id;`,
        ),
      ).toEqual([
        [ALICE, 'member'],
        [BOB, 'owner'],
        [CAROL, 'admin'],
      ]);
    },
  );

  it('a member who leaves a group leaves no receipt behind in it', async () => {
    const prisma = database('leave_receipts', people);
    const groups = groupsService(prisma);
    const { id: groupId } = await groups.createGroup(auth(ALICE, ALICE_PHONE), {
      name: 'book club',
      memberHandles: ['bob', 'carol'],
    });
    const { id: otherGroupId } = await groups.createGroup(auth(ALICE, ALICE_PHONE), {
      name: 'chess',
      memberHandles: ['bob'],
    });
    postgres.query(
      'leave_receipts',
      [groupId, otherGroupId]
        .map(
          (conversationId, index) => `
          INSERT INTO messages (id, conversation_id, sender_device_id, client_message_id, conversation_order, ciphertext, nonce, message_type)
            VALUES ('${id(0x100 + index)}', '${conversationId}', '${ALICE_PHONE}', 'alice-${index}', 1, 'ct', 'n', 'text');
          INSERT INTO message_receipts (id, message_id, user_id, delivered_at, read_at)
            SELECT gen_random_uuid(), '${id(0x100 + index)}', member, now(), now()
              FROM unnest(ARRAY['${BOB}', '${CAROL}']::uuid[]) AS member
             WHERE EXISTS (SELECT 1 FROM conversation_members
                            WHERE conversation_id = '${conversationId}' AND user_id = member);`,
        )
        .join('\n'),
    );

    await groups.leaveGroup(auth(BOB, BOB_PHONE), groupId);

    expect(
      postgres.query(
        'leave_receipts',
        `SELECT m.conversation_id, r.user_id FROM message_receipts r
           JOIN messages m ON m.id = r.message_id ORDER BY m.conversation_id, r.user_id;`,
      ),
    ).toEqual(
      [
        [groupId, CAROL],
        [otherGroupId, BOB],
      ].sort(([a], [b]) => (a < b ? -1 : 1)),
    );
  });

  describe('one-time prekey pool cap', () => {
    const batch = (firstKeyId: number, size = 100) =>
      Array.from({ length: size }, (_, index) => ({
        keyId: firstKeyId + index,
        publicKey: `pk-${firstKeyId + index}`,
      }));
    const unused = (name: string) =>
      Number(
        postgres.query(
          name,
          `SELECT count(*) FROM one_time_prekeys
            WHERE device_id = '${BOB_PHONE}' AND consumed_at IS NULL;`,
        )[0][0],
      );
    const prekeysService = (prisma: PrismaService) =>
      new PrekeysService(
        prisma,
        new DirectoryBudget(new FakeEphemeralStoreService() as never),
        new FakeSafetyService() as never,
      );

    it('refuses a batch past the cap whole, and still accepts a retry of a stored batch', async () => {
      const prisma = database('prekey_cap', people);
      const prekeys = prekeysService(prisma);

      await expect(prekeys.upload(BOB, BOB_PHONE, batch(0))).resolves.toEqual({
        uploaded: 100,
        available: 100,
      });
      await expect(prekeys.upload(BOB, BOB_PHONE, batch(100))).resolves.toEqual({
        uploaded: 100,
        available: MAX_UNCONSUMED_PREKEYS_PER_DEVICE,
      });
      // A retry whose answer was lost adds nothing, so it is not refused.
      await expect(prekeys.upload(BOB, BOB_PHONE, batch(100))).resolves.toEqual({
        uploaded: 0,
        available: MAX_UNCONSUMED_PREKEYS_PER_DEVICE,
      });
      await expect(prekeys.upload(BOB, BOB_PHONE, batch(200, 1))).rejects.toMatchObject({
        response: { code: 'validation_failed' },
      });
      expect(unused('prekey_cap')).toBe(MAX_UNCONSUMED_PREKEYS_PER_DEVICE);
    });

    it('holds against concurrent uploads from one device', async () => {
      const prisma = database('prekey_cap_race', people);
      const prekeys = prekeysService(prisma);

      const results = await Promise.allSettled(
        [0, 100, 200, 300, 400, 500].map((firstKeyId) =>
          prekeys.upload(BOB, BOB_PHONE, batch(firstKeyId)),
        ),
      );

      expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(2);
      expect(unused('prekey_cap_race')).toBe(MAX_UNCONSUMED_PREKEYS_PER_DEVICE);
    });

    // An upload that passed the active-device check and then waited for the
    // device row behind a revocation must not store prekeys for the device
    // that revocation just retired.
    it('stores nothing for a device revoked while the upload waited for its row', async () => {
      const prisma = database('prekey_revoke_race', people);
      const prekeys = prekeysService(prisma);
      const revoker = new PrismaService({
        datasourceUrl: postgres.connectionUrl('prekey_revoke_race'),
      });
      clients.push(revoker);

      const revocation = await holdLocks(revoker, (tx) => revokeDevice(tx, BOB_PHONE, new Date()));
      const upload = prekeys.upload(BOB, BOB_PHONE, batch(0)).then(
        () => 'stored',
        (error: unknown) => error,
      );
      await sessionsWaitForALock('prekey_revoke_race', 1);
      revocation.release();
      await revocation.done;

      await expect(upload).resolves.toMatchObject({
        status: 401,
        response: { code: 'device_not_active' },
      });
      expect(unused('prekey_revoke_race')).toBe(0);
    });
  });

  // The store's in-memory fallback, which keeps keys to their absolute expiry.
  const secretService = (prisma: PrismaService) =>
    new SecretService(
      prisma,
      new EphemeralStoreService({ redisUrl: undefined } as AppConfigService),
    );

  it('refuses a one-time link once the stored links fill the relay-wide budget', async () => {
    const prisma = database('secret_budget', '');
    const secrets = secretService(prisma);
    postgres.query(
      'secret_budget',
      `INSERT INTO secret_blobs (id, ciphertext, expires_at)
         SELECT gen_random_uuid(), 'link-' || n, now() + interval '1 day'
           FROM generate_series(1, ${MAX_STORED_SECRETS - 1}) AS n;`,
    );

    await expect(
      secrets.create('the last one that fits', undefined, '198.51.100.7'),
    ).resolves.toMatchObject({ id: expect.any(String) });
    await expect(secrets.create('one too many', undefined, '203.0.113.9')).rejects.toMatchObject({
      status: 503,
      response: { code: 'secret_storage_full' },
    });
    expect(postgres.query('secret_budget', 'SELECT count(*) FROM secret_blobs;')).toEqual([
      [String(MAX_STORED_SECRETS)],
    ]);
  });

  // One client must not be able to fill the relay-wide budget and lock every
  // other client out until its links expire. Its network's daily quota stops
  // it first, with its own 429, even when it keeps creating maximal seven-day
  // links on every UTC day that its earlier links are still alive.
  it("holds one network's maximal links to its quota, far below the relay-wide budget", async () => {
    const prisma = database('secret_quota', '');
    const secrets = secretService(prisma);
    const attacker = '2001:db8:aa:bb::/64';
    const maximal = 'A'.repeat(MAX_CIPHERTEXT_LENGTH);
    const dayMs = 24 * 60 * 60 * 1000;
    const daysAlive = Math.ceil((MAX_TTL_SECONDS * 1000) / dayMs) + 1;
    const realNow = Date.now.bind(Date);
    const startedAt = realNow();
    const firstDay = utcDayStart(new Date(startedAt)).getTime() + dayMs + 1_000;

    try {
      for (let day = 0; day < daysAlive; day += 1) {
        // Each round runs just after the start of the next UTC day.
        const shift = firstDay + day * dayMs - realNow();
        jest.spyOn(Date, 'now').mockImplementation(() => realNow() + shift);
        let accepted = 0;
        let refusal: unknown;
        while (refusal === undefined && accepted <= 64) {
          try {
            await secrets.create(maximal, MAX_TTL_SECONDS, attacker);
            accepted += 1;
          } catch (error) {
            refusal = error;
          }
        }
        expect(refusal).toMatchObject({ status: 429, response: { code: 'secret_quota_exceeded' } });
        expect(accepted).toBe(Math.floor(MAX_SECRET_BYTES_PER_CLIENT_DAY / MAX_CIPHERTEXT_LENGTH));
        jest.restoreAllMocks();
      }
    } finally {
      jest.restoreAllMocks();
    }

    const [[blobs, bytes]] = postgres.query(
      'secret_quota',
      'SELECT count(*), sum(octet_length(ciphertext)) FROM secret_blobs;',
    );
    expect(Number(bytes)).toBe(daysAlive * MAX_SECRET_BYTES_PER_CLIENT_DAY);
    expect(Number(bytes)).toBeLessThanOrEqual(MAX_STORED_SECRET_BYTES / 8);
    expect(Number(blobs)).toBeLessThan(MAX_STORED_SECRETS);
    await expect(
      secrets.create('a 30-byte link from elsewhere.', undefined, '198.51.100.7'),
    ).resolves.toMatchObject({ id: expect.any(String) });
  });
});
