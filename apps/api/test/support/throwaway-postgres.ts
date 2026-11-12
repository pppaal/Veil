import { execFileSync, type ExecFileSyncOptions } from 'node:child_process';
import { chownSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// A private Postgres cluster for tests that have to run real SQL, such as
// hand-written data migrations the in-memory fake cannot evaluate. It listens
// only on a Unix socket inside its own temporary directory and is deleted on
// stop. The server binaries come from VEIL_TEST_PG_BINDIR, `pg_config
// --bindir`, or the newest /usr/lib/postgresql/<version>/bin.

const MIGRATIONS_DIR = join(__dirname, '../../prisma/migrations');
const SUPERUSER = 'veil';

const hasServerBinaries = (dir: string): boolean =>
  ['initdb', 'pg_ctl', 'psql'].every((name) => existsSync(join(dir, name)));

export const findPostgresBinDir = (): string | null => {
  const candidates: string[] = [];
  if (process.env.VEIL_TEST_PG_BINDIR) {
    candidates.push(process.env.VEIL_TEST_PG_BINDIR);
  }
  try {
    candidates.push(execFileSync('pg_config', ['--bindir'], { encoding: 'utf8' }).trim());
  } catch {
    // No pg_config on PATH.
  }
  if (existsSync('/usr/lib/postgresql')) {
    const versions = readdirSync('/usr/lib/postgresql')
      .filter((name) => /^\d+$/.test(name))
      .sort((a, b) => Number(b) - Number(a));
    candidates.push(...versions.map((version) => `/usr/lib/postgresql/${version}/bin`));
  }
  return candidates.find(hasServerBinaries) ?? null;
};

// The server refuses to run as root, so as root it runs as `nobody`.
const serverIdentity = (): { uid: number; gid: number } | null => {
  if (process.getuid?.() !== 0) {
    return null;
  }
  const entry = readFileSync('/etc/passwd', 'utf8')
    .split('\n')
    .map((line) => line.split(':'))
    .find((fields) => fields[0] === 'nobody');
  if (!entry) {
    throw new Error('running as root, but there is no nobody user to run Postgres as');
  }
  return { uid: Number(entry[2]), gid: Number(entry[3]) };
};

export class ThrowawayPostgres {
  private constructor(
    private readonly binDir: string,
    private readonly dir: string,
    private readonly serverOptions: ExecFileSyncOptions,
  ) {}

  static start(binDir: string): ThrowawayPostgres {
    const dir = mkdtempSync(join(tmpdir(), 'veil-pg-'));
    const identity = serverIdentity();
    if (identity) {
      chownSync(dir, identity.uid, identity.gid);
    }
    const serverOptions: ExecFileSyncOptions = { stdio: 'pipe', ...identity };
    const cluster = new ThrowawayPostgres(binDir, dir, serverOptions);
    try {
      execFileSync(
        join(binDir, 'initdb'),
        ['-D', join(dir, 'data'), '-U', SUPERUSER, '--auth=trust', '-E', 'UTF8', '--no-locale'],
        serverOptions,
      );
      execFileSync(
        join(binDir, 'pg_ctl'),
        [
          '-D',
          join(dir, 'data'),
          '-o',
          `-k ${dir} -c listen_addresses=''`,
          '-l',
          join(dir, 'server.log'),
          '-w',
          'start',
        ],
        serverOptions,
      );
    } catch (error) {
      cluster.stop();
      throw error;
    }
    return cluster;
  }

  stop(): void {
    try {
      execFileSync(
        join(this.binDir, 'pg_ctl'),
        ['-D', join(this.dir, 'data'), '-m', 'immediate', 'stop'],
        this.serverOptions,
      );
    } catch {
      // Never started, or already gone.
    }
    rmSync(this.dir, { recursive: true, force: true });
  }

  /** Runs SQL in one transaction; returns the rows of the last statement, tab-separated. */
  query(database: string, sql: string): string[][] {
    const output = execFileSync(
      join(this.binDir, 'psql'),
      [
        '-h',
        this.dir,
        '-U',
        SUPERUSER,
        '-d',
        database,
        '-X',
        '-q',
        '-A',
        '-t',
        '-F',
        '\t',
        '-v',
        'ON_ERROR_STOP=1',
        '--single-transaction',
        '-f',
        '-',
      ],
      { input: sql, encoding: 'utf8', stdio: 'pipe' },
    );
    return output
      .split('\n')
      .filter((line) => line.length > 0)
      .map((line) => line.split('\t'));
  }

  createDatabase(database: string): void {
    execFileSync(
      join(this.binDir, 'psql'),
      [
        '-h',
        this.dir,
        '-U',
        SUPERUSER,
        '-d',
        'postgres',
        '-X',
        '-q',
        '-c',
        `CREATE DATABASE "${database}"`,
      ],
      { stdio: 'pipe' },
    );
  }

  /** Applies prisma/migrations in order, from the first up to and including `last`. */
  migrate(database: string, last: string): void {
    const migrations = readdirSync(MIGRATIONS_DIR)
      .filter((name) => /^\d{4}_/.test(name))
      .sort();
    if (!migrations.includes(last)) {
      throw new Error(`no migration named ${last}`);
    }
    for (const name of migrations.slice(0, migrations.indexOf(last) + 1)) {
      this.applyMigration(database, name);
    }
  }

  applyMigration(database: string, name: string): void {
    this.query(database, readFileSync(join(MIGRATIONS_DIR, name, 'migration.sql'), 'utf8'));
  }
}
