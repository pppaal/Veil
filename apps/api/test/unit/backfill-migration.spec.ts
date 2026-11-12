import { conversation, device, directKey, id, users } from '../support/sql-rows';
import { ThrowawayPostgres, findPostgresBinDir } from '../support/throwaway-postgres';

// 0020 is hand-written SQL that cleans rows earlier releases left behind, so
// it is run here on a real Postgres: every migration up to 0019 builds the
// schema, the rows are written the way the old code wrote them, then 0020
// runs. Needs the Postgres server binaries (see throwaway-postgres.ts).

const BEFORE = '0019_metadata_minimisation';
const BACKFILL = '0020_backfill_departed_metadata';

const ALICE = id(0xa);
const BOB = id(0xb);
const CAROL = id(0xc);
const DAVE = id(0xd);
const ERIN = id(0xe);
const FRANK = id(0xf);
const GINA = id(0x6);
const BOB_PHONE = id(0xb1);
const CAROL_PHONE = id(0xc1);

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

  it('clears direct keys that name someone who is no longer a member of the conversation', () => {
    const BE = id(0x3be0);
    const BF = id(0x3bf0);
    const BG = id(0x3b60);
    prepare(
      'departed_members',
      [
        users([BOB, 'bob'], [ERIN, 'erin', 'revoked'], [FRANK, 'frank'], [GINA, 'gina', 'revoked']),
        conversation(BE, 'direct', [BOB, ERIN]),
        conversation(BF, 'direct', [BOB, FRANK]),
        conversation(BG, 'direct', [BOB, GINA]),
        // Erin's deletion failed under a release before 0019: its Phase 2
        // deleted every membership of hers, direct ones included, and Phase 3
        // never ran, so her user row stays 'revoked'.
        `DELETE FROM conversation_members WHERE user_id = '${ERIN}';`,
        // Frank left through POST /groups/:id/leave, which did not check the
        // conversation type before the conversation-integrity release.
        `DELETE FROM conversation_members WHERE conversation_id = '${BF}' AND user_id = '${FRANK}';`,
        // Gina's deletion is in progress under the current code, which keeps
        // direct memberships until its last phase.
      ].join('\n'),
    );

    postgres.applyMigration('departed_members', BACKFILL);

    expect(
      postgres.query(
        'departed_members',
        `SELECT c.id, coalesce(c.direct_key, '-'), string_agg(m.user_id::text, ',' ORDER BY m.user_id)
           FROM conversations c LEFT JOIN conversation_members m ON m.conversation_id = c.id
          GROUP BY c.id ORDER BY c.id;`,
      ),
    ).toEqual([
      // Gina's retried deletion finds this conversation through her
      // membership and releases the key itself.
      [BG, directKey(BOB, GINA), [BOB, GINA].sort().join(',')],
      [BE, '-', BOB],
      [BF, '-', BOB],
    ]);

    // Erin has no direct membership left to be found by, so this holds even
    // for a retry that looks only through memberships: once her user row
    // goes, no key names her.
    postgres.query('departed_members', `DELETE FROM users WHERE id = '${ERIN}';`);
    expect(
      postgres.query(
        'departed_members',
        `SELECT count(*) FROM conversations WHERE direct_key LIKE '%${ERIN}%';`,
      ),
    ).toEqual([['0']]);
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
