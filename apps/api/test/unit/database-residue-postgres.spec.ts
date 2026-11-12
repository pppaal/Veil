import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { ThrowawayPostgres, findPostgresBinDir } from '../support/throwaway-postgres';

// docs/server-data-inventory.md and docs/metadata-retention.md ("No database
// backups") say that a seized database volume can hold rows that were already
// deleted, because Postgres does not wipe a deleted row's bytes from its
// write-ahead log or from the table's pages. An earlier version of the
// inventory said the opposite. This shows the caveat on the real schema with
// the row it matters most for, a burned one-time link. If it ever fails because
// Postgres stopped leaving the bytes behind, narrow the caveat in both
// documents. Needs the Postgres server binaries (see throwaway-postgres.ts).

const DATABASE = 'residue';

const postgresBinDir = findPostgresBinDir();
const describeWithPostgres = postgresBinDir ? describe : describe.skip;
if (!postgresBinDir) {
  console.warn('database-residue-postgres.spec: no Postgres server binaries found; skipped');
}

describeWithPostgres('what a deleted row leaves on the Postgres volume', () => {
  let postgres: ThrowawayPostgres;

  beforeAll(() => {
    postgres = ThrowawayPostgres.start(postgresBinDir as string);
    postgres.createDatabase(DATABASE);
    postgres.migrate(DATABASE);
  }, 60_000);

  afterAll(() => {
    postgres?.stop();
  });

  it("keeps a burned one-time link's ciphertext in the write-ahead log and the table file after DELETE, VACUUM and CHECKPOINT", () => {
    const linkId = randomUUID();
    const ciphertext = `residue-${randomBytes(150).toString('base64url')}`;
    // Other links stay unread, as they would on a running relay, so the
    // vacuum below cannot simply truncate the page away.
    postgres.query(
      DATABASE,
      [
        `INSERT INTO secret_blobs (id, ciphertext, expires_at)
           SELECT gen_random_uuid(), 'other-link-' || n, now() + interval '1 day'
           FROM generate_series(1, 5) AS n;`,
        `INSERT INTO secret_blobs (id, ciphertext, expires_at)
           VALUES ('${linkId}', '${ciphertext}', now() + interval '1 day');`,
      ].join('\n'),
    );
    postgres.query(DATABASE, 'CHECKPOINT;');

    // The read burns the link the way SecretService does: one DELETE by id.
    expect(
      postgres.query(
        DATABASE,
        `DELETE FROM secret_blobs WHERE id = '${linkId}' RETURNING ciphertext;`,
      ),
    ).toEqual([[ciphertext]]);
    postgres.query(DATABASE, 'VACUUM secret_blobs;\nCHECKPOINT;', { transaction: false });

    expect(
      postgres.query(DATABASE, `SELECT count(*) FROM secret_blobs WHERE id = '${linkId}';`),
    ).toEqual([['0']]);
    expect(postgres.query(DATABASE, 'SELECT count(*) FROM secret_blobs;')).toEqual([['5']]);

    const dataDirectory = postgres.dataDirectory;
    const [[tableFile]] = postgres.query(DATABASE, "SELECT pg_relation_filepath('secret_blobs');");
    expect(readFileSync(join(dataDirectory, tableFile)).includes(ciphertext)).toBe(true);

    const walDirectory = join(dataDirectory, 'pg_wal');
    const walSegments = readdirSync(walDirectory).filter((name) => /^[0-9A-F]{24}$/.test(name));
    expect(
      walSegments.filter((name) => readFileSync(join(walDirectory, name)).includes(ciphertext)),
    ).not.toEqual([]);
  });
});
