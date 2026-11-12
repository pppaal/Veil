import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';

import { CLEAN_FIXTURE, runPolicyChecks, runSelfTest, writeTree } from '../policy-check.mjs';

const scratch = mkdtempSync(join(tmpdir(), 'veil-policy-test-'));
after(() => rmSync(scratch, { recursive: true, force: true }));

let trees = 0;
const failuresFor = (files) => {
  trees += 1;
  const root = join(scratch, `tree-${trees}`);
  writeTree(root, { ...CLEAN_FIXTURE, ...files });
  return runPolicyChecks(root);
};

const SCHEMA = 'apps/api/prisma/schema.prisma';

test('the clean fixture passes', () => {
  assert.deepEqual(failuresFor({}), []);
});

test('recovery model in schema fails', () => {
  const failures = failuresFor({
    [SCHEMA]: `${CLEAN_FIXTURE[SCHEMA]}model RecoveryBlob {\n  userId String @id\n}\n`,
  });
  assert.equal(failures.length, 1);
  assert.match(failures[0], /^\[no-recovery-models\]/);
});

test('a backup table behind an innocent model name fails', () => {
  const failures = failuresFor({
    [SCHEMA]: `${CLEAN_FIXTURE[SCHEMA]}model Vault {\n  id String @id\n\n  @@map("identity_backups")\n}\n`,
  });
  assert.match(failures.join('\n'), /\[no-recovery-models\]/);
});

test('recovery contract types fail', () => {
  const failures = failuresFor({
    'packages/contracts/src/index.ts': 'export interface RecoveryBackupResponse {}\n',
  });
  assert.match(failures.join('\n'), /\[no-recovery-contracts\]/);
});

test('recovery contract values and lowercase names fail too', () => {
  for (const source of [
    "export const RECOVERY_FORMAT = 'sealed-v1';\n",
    'export type keyBackupState = string;\n',
    'export function sealRecovery() {}\n',
  ]) {
    const failures = failuresFor({ 'packages/contracts/src/index.ts': source });
    assert.match(failures.join('\n'), /\[no-recovery-contracts\]/, source);
  }
});

test('a mobile backup module fails', () => {
  const failures = failuresFor({
    'apps/mobile/lib/src/core/backup/backup_envelope.dart': 'class BackupEnvelope {}\n',
  });
  assert.match(failures.join('\n'), /\[no-mobile-backup\]/);
});

test('a database dump anywhere in the deployment fails', () => {
  for (const files of [
    { 'docker-compose.backup.yml': 'services:\n  backup:\n    command: pg_dumpall -U veil\n' },
    { 'infra/cron/nightly.sh': 'pg_dump -h postgres veil > /backups/veil.sql\n' },
    { 'infra/docker/compose.yml': 'command: ["wal-g", "backup-push", "/data"]\n' },
  ]) {
    assert.match(failuresFor(files).join('\n'), /\[no-database-dumps\]/, Object.keys(files)[0]);
  }
});

test('CORS configured anywhere but corsOptions() fails', () => {
  const MAIN = 'apps/api/src/main.ts';
  for (const files of [
    { [MAIN]: CLEAN_FIXTURE[MAIN].replace('app.enableCors(corsOptions(config));\n', '') },
    {
      [MAIN]: CLEAN_FIXTURE[MAIN].replace(
        'corsOptions(config)',
        '{ origin: allowedOrigins, credentials: false }',
      ),
    },
    { [MAIN]: CLEAN_FIXTURE[MAIN].replace('{ bufferLogs: true }', '{ cors: { origin: true } }') },
    { 'apps/api/src/modules/realtime/realtime.gateway.ts': '@WebSocketGateway({ cors: true })\n' },
  ]) {
    const failures = failuresFor(files);
    assert.match(failures.join('\n'), /\[cors-through-shared-options\]/, JSON.stringify(files));
  }
  // Turning CORS off is not configuring it.
  assert.deepEqual(
    failuresFor({
      'apps/api/src/modules/realtime/realtime.gateway.ts': '@WebSocketGateway({ cors: false })\n',
    }),
    [],
  );
});

test('every seeded violation is caught by its own rule', () => {
  assert.deepEqual(runSelfTest(), []);
});

test('Caddy stripping /demo or replacing the viewer headers fails', () => {
  const CADDYFILE = 'infra/caddy/Caddyfile';
  const withHeader = (line) =>
    CLEAN_FIXTURE[CADDYFILE].replace('site {\n', `site {\n\theader {\n\t\t${line}\n\t}\n`);
  for (const caddyfile of [
    CLEAN_FIXTURE[CADDYFILE].replace('\treverse_proxy api:3000 {', '\thandle_path /demo* {'),
    withHeader('Referrer-Policy "strict-origin-when-cross-origin"'),
    withHeader('>Referrer-Policy "origin"'),
    withHeader('+Cache-Control "public, max-age=60"'),
    withHeader('Content-Security-Policy "default-src \'self\'"'),
  ]) {
    assert.match(
      failuresFor({ [CADDYFILE]: caddyfile }).join('\n'),
      /\[caddy-keeps-viewer-headers\]/,
      caddyfile,
    );
  }
  // A default that applies only where the API set none, and the prefix kept.
  assert.deepEqual(
    failuresFor({
      [CADDYFILE]: withHeader('?Referrer-Policy "strict-origin-when-cross-origin"').replace(
        '\treverse_proxy api:3000 {',
        '\thandle /demo* {\n\t}\n\treverse_proxy api:3000 {',
      ),
    }),
    [],
  );
});
