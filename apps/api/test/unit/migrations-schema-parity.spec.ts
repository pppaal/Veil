import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

import { ThrowawayPostgres, findPostgresBinDir } from '../support/throwaway-postgres';

// Production runs the hand-written SQL in prisma/migrations, while the client
// is generated from schema.prisma. A difference between the two is a column,
// index or default production has and the schema does not (or the reverse),
// and the next `prisma migrate dev` would emit it as a surprise migration.
// Every migration is applied to a real Postgres and Prisma is asked what it
// would change to reach schema.prisma: the answer must be nothing. Needs the
// Postgres server binaries (see throwaway-postgres.ts).

const API_ROOT = join(__dirname, '..', '..');
const PRISMA_CLI = join(API_ROOT, 'node_modules', '.bin', 'prisma');

const postgresBinDir = findPostgresBinDir();
const describeWithPostgres = postgresBinDir ? describe : describe.skip;
if (!postgresBinDir) {
  console.warn('migrations-schema-parity.spec: no Postgres server binaries found; skipped');
}

describeWithPostgres('prisma/migrations against schema.prisma', () => {
  let postgres: ThrowawayPostgres;

  beforeAll(() => {
    postgres = ThrowawayPostgres.start(postgresBinDir as string);
  }, 60_000);

  afterAll(() => {
    postgres?.stop();
  });

  it('leaves nothing for Prisma to change once every migration has run', () => {
    postgres.createDatabase('parity');
    postgres.migrate('parity');

    const script = execFileSync(
      PRISMA_CLI,
      [
        'migrate',
        'diff',
        '--from-url',
        postgres.connectionUrl('parity'),
        '--to-schema-datamodel',
        join(API_ROOT, 'prisma', 'schema.prisma'),
        '--script',
      ],
      { cwd: API_ROOT, encoding: 'utf8', stdio: 'pipe' },
    );

    const statements = script
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line !== '' && !line.startsWith('--'));
    expect(statements).toEqual([]);
  }, 120_000);
});
