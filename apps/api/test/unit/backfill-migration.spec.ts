import { ThrowawayPostgres, findPostgresBinDir } from '../support/throwaway-postgres';

// 0020 is hand-written SQL that cleans rows earlier releases left behind, so
// it is run here on a real Postgres: every migration up to 0019 builds the
// schema, the rows are written the way the old code wrote them, then 0020
// runs. Needs the Postgres server binaries (see throwaway-postgres.ts).

const BEFORE = '0019_metadata_minimisation';
const BACKFILL = '0020_backfill_departed_metadata';

const id = (n: number): string => `00000000-0000-4000-8000-${n.toString(16).padStart(12, '0')}`;

const ALICE = id(0xa);
const BOB = id(0xb);
const CAROL = id(0xc);
const DAVE = id(0xd);
const ERIN = id(0xe);
const BOB_PHONE = id(0xb1);
const CAROL_PHONE = id(0xc1);

const directKey = (a: string, b: string): string => [a, b].sort().join('|');

const users = (...entries: Array<[string, string, string?]>): string =>
  entries
    .map(
      ([userId, handle, status = 'active']) =>
        `INSERT INTO users (id, handle, status, updated_at) VALUES ('${userId}', '${handle}', '${status}', now());`,
    )
    .join('\n');

const device = (deviceId: string, userId: string): string =>
  `INSERT INTO devices (id, user_id, platform, device_name, public_identity_key, signed_prekey_bundle, auth_public_key)
   VALUES ('${deviceId}', '${userId}', 'ios', 'phone', 'ik', 'spk', 'auth');`;

const conversation = (
  conversationId: string,
  type: 'direct' | 'group',
  members: string[],
): string =>
  [
    `INSERT INTO conversations (id, type, direct_key) VALUES ('${conversationId}', '${type}', ${
      type === 'direct' ? `'${directKey(members[0], members[1])}'` : 'NULL'
    });`,
    ...members.map(
      (userId) =>
        `INSERT INTO conversation_members (id, conversation_id, user_id)
         VALUES (gen_random_uuid(), '${conversationId}', '${userId}');`,
    ),
  ].join('\n');

const postgresBinDir = findPostgresBinDir();
const describeWithPostgres = postgresBinDir ? describe : describe.skip;
if (!postgresBinDir) {
  console.warn('backfill-migration.spec: no Postgres server binaries found; skipped');
}

describeWithPostgres(`migration ${BACKFILL}`, () => {
  let postgres: ThrowawayPostgres;

  beforeAll(() => {
    postgres = ThrowawayPostgres.start(postgresBinDir as string);
  }, 60_000);

  afterAll(() => {
    postgres?.stop();
  });

  const prepare = (database: string, seed: string): void => {
    postgres.createDatabase(database);
    postgres.migrate(database, BEFORE);
    postgres.query(database, seed);
  };

  it('clears direct keys that name deleted accounts and deletes direct conversations nobody is left in', () => {
    const AB = id(0x1ab0);
    const AC = id(0x1ac0);
    const BC = id(0x1bc0);
    const BD = id(0x1bd0);
    const BE = id(0x1be0);
    const GROUP = id(0x1ff0);
    prepare(
      'direct_keys',
      [
        users(
          [ALICE, 'alice'],
          [BOB, 'bob'],
          [CAROL, 'carol'],
          [DAVE, 'dave'],
          [ERIN, 'erin', 'revoked'],
        ),
        conversation(AB, 'direct', [ALICE, BOB]),
        conversation(AC, 'direct', [ALICE, CAROL]),
        conversation(BC, 'direct', [BOB, CAROL]),
        conversation(BD, 'direct', [BOB, DAVE]),
        conversation(BE, 'direct', [BOB, ERIN]),
        conversation(GROUP, 'group', [BOB, CAROL]),
        // How account deletion ended before 0019: the user row goes, its
        // memberships cascade, and direct_key keeps naming it.
        `DELETE FROM users WHERE id IN ('${ALICE}', '${CAROL}');`,
      ].join('\n'),
    );
    expect(
      postgres.query(
        'direct_keys',
        `SELECT count(*) FROM conversations WHERE direct_key LIKE '%${ALICE}%';`,
      ),
    ).toEqual([['2']]);

    postgres.applyMigration('direct_keys', BACKFILL);

    expect(
      postgres.query(
        'direct_keys',
        `SELECT c.id, c.type, coalesce(c.direct_key, '-'), string_agg(m.user_id::text, ',' ORDER BY m.user_id)
           FROM conversations c LEFT JOIN conversation_members m ON m.conversation_id = c.id
          GROUP BY c.id ORDER BY c.id;`,
      ),
    ).toEqual([
      // Alice and Carol are gone: the key no longer names them, and Bob keeps
      // the conversation.
      [AB, 'direct', '-', BOB],
      [BC, 'direct', '-', BOB],
      // Both live accounts: untouched.
      [BD, 'direct', directKey(BOB, DAVE), [BOB, DAVE].sort().join(',')],
      // Erin's deletion has not finished; its retry releases the key.
      [BE, 'direct', directKey(BOB, ERIN), [BOB, ERIN].sort().join(',')],
      // Groups have no key and are not this migration's concern.
      [GROUP, 'group', '-', BOB],
      // Alice-Carol had nobody left in it and is gone.
    ]);
  });

  it("deletes former members' sync cursors and mutes and keeps current members'", () => {
    const GROUP = id(0x2990);
    const BC = id(0x2bc0);
    prepare(
      'former_members',
      [
        users([BOB, 'bob'], [CAROL, 'carol']),
        device(BOB_PHONE, BOB),
        device(CAROL_PHONE, CAROL),
        conversation(GROUP, 'group', [BOB, CAROL]),
        conversation(BC, 'direct', [BOB, CAROL]),
        `INSERT INTO device_conversation_states (id, device_id, conversation_id, last_read_conversation_order) VALUES
           (gen_random_uuid(), '${BOB_PHONE}', '${GROUP}', 4),
           (gen_random_uuid(), '${CAROL_PHONE}', '${GROUP}', 3),
           (gen_random_uuid(), '${CAROL_PHONE}', '${BC}', 1);`,
        `INSERT INTO conversation_mutes (user_id, conversation_id) VALUES
           ('${BOB}', '${GROUP}'), ('${CAROL}', '${GROUP}'), ('${CAROL}', '${BC}');`,
        // How leaving a group ended before 0019: only the membership went.
        `DELETE FROM conversation_members WHERE conversation_id = '${GROUP}' AND user_id = '${CAROL}';`,
      ].join('\n'),
    );

    postgres.applyMigration('former_members', BACKFILL);

    expect(
      postgres.query(
        'former_members',
        'SELECT device_id, conversation_id FROM device_conversation_states ORDER BY device_id, conversation_id;',
      ),
    ).toEqual([
      [BOB_PHONE, GROUP],
      [CAROL_PHONE, BC],
    ]);
    expect(
      postgres.query(
        'former_members',
        'SELECT user_id, conversation_id FROM conversation_mutes ORDER BY user_id, conversation_id;',
      ),
    ).toEqual([
      [BOB, GROUP],
      [CAROL, BC],
    ]);
  });
});
