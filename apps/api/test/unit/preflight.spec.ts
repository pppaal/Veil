import { execFileSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { preflight } from '../../src/preflight';

const ENTRYPOINT = join(__dirname, '../../docker-entrypoint.sh');

// What a development stack hands the API: enough for envSchema, nothing for
// the production gate.
const DEVELOPMENT_ENV = {
  VEIL_ENV: 'development',
  VEIL_DATABASE_URL: 'postgresql://veil:veil@localhost:5432/veil',
  VEIL_JWT_SECRET: 'preflight-spec-secret-0123456789abcdef',
  VEIL_S3_ENDPOINT: 'http://localhost:9000',
  VEIL_S3_REGION: 'us-east-1',
  VEIL_S3_ACCESS_KEY: 'minioadmin',
  VEIL_S3_SECRET_KEY: 'minioadmin',
  VEIL_S3_BUCKET: 'veil-encrypted',
};

describe('preflight', () => {
  const saved = { ...process.env };

  afterEach(() => {
    for (const key of Object.keys(process.env)) {
      if (!(key in saved)) delete process.env[key];
    }
    Object.assign(process.env, saved);
  });

  it('passes a development environment', async () => {
    Object.assign(process.env, DEVELOPMENT_ENV);

    await expect(preflight()).resolves.toBeUndefined();
  });

  it('refuses production before the crypto audit is attested, like the API boot', async () => {
    Object.assign(process.env, DEVELOPMENT_ENV, { VEIL_ENV: 'production' });

    await expect(preflight()).rejects.toThrow(
      /VEIL production boot blocked:[\s\S]*VEIL_AUDITED_CRYPTO_ATTESTED/,
    );
  });

  it('refuses an environment the schema rejects', async () => {
    Object.assign(process.env, DEVELOPMENT_ENV, { VEIL_JWT_SECRET: 'short' });

    await expect(preflight()).rejects.toThrow(/VEIL_JWT_SECRET/);
  });
});

// The entrypoint itself, with node, prisma and pnpm replaced by stubs that
// record their calls, so the order is checked as the shell runs it.
describe('docker-entrypoint.sh', () => {
  let dir: string;

  const run = (preflightExit: number): { status: number; calls: string[] } => {
    dir = mkdtempSync(join(tmpdir(), 'veil-entrypoint-'));
    const log = join(dir, 'calls.log');
    writeFileSync(log, '');
    const stub = (path: string, name: string, exit = 0) => {
      writeFileSync(path, `#!/bin/sh\necho "${name} $*" >> "${log}"\nexit ${exit}\n`);
      chmodSync(path, 0o755);
    };
    mkdirSync(join(dir, 'bin'));
    mkdirSync(join(dir, 'node_modules/.bin'), { recursive: true });
    stub(join(dir, 'bin/node'), 'node', preflightExit);
    stub(join(dir, 'bin/pnpm'), 'pnpm');
    stub(join(dir, 'node_modules/.bin/prisma'), 'prisma');
    let status = 0;
    try {
      execFileSync('sh', [ENTRYPOINT], {
        cwd: dir,
        env: { PATH: `${join(dir, 'bin')}:/usr/bin:/bin` },
        stdio: 'pipe',
      });
    } catch (error) {
      status = (error as { status: number }).status;
    }
    const calls = readFileSync(log, 'utf8').split('\n').filter(Boolean);
    return { status, calls };
  };

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it('runs no migration when the preflight refuses the configuration', () => {
    const { status, calls } = run(1);

    expect(status).not.toBe(0);
    expect(calls).toEqual(['node dist/preflight.js']);
  });

  it('runs the preflight, then the migrations, then the API', () => {
    const { status, calls } = run(0);

    expect(status).toBe(0);
    expect(calls).toEqual([
      'node dist/preflight.js',
      'prisma migrate deploy --schema prisma/schema.prisma',
      'pnpm start',
    ]);
  });
});
