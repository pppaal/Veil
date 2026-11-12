import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import {
  INVENTORY_PATH,
  PLAINTEXT_ALLOWLIST,
  RETENTION_SERVICE_PATH,
  SCHEMA_PATH,
  checkSchemaPrivacy,
  renderInventory,
} from '../schema-privacy-check.mjs';

const repoFile = (path) => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');

const SWEEPS = '// @retention-sweep Note\n';

const check = (schemaSource, retentionSource = SWEEPS, allowlist = {}) =>
  checkSchemaPrivacy({ schemaSource, retentionSource, allowlist }).failures;

const model = (fields) =>
  ['model Note {', ...fields.map((line) => `  ${line}`), '', '  @@map("notes")', '}', ''].join(
    '\n',
  );

const ID = ['/// @privacy(class=routing, retention=30d, visibleTo=self)', 'id String @id @db.Uuid'];

test('annotated schema with a swept TTL passes', () => {
  assert.deepEqual(
    check(
      model([
        ...ID,
        '/// @privacy(class=ciphertext, retention=30d, visibleTo=members)',
        'body String',
      ]),
    ),
    [],
  );
});

test('unannotated field fails', () => {
  const failures = check(model([...ID, 'createdAt DateTime @default(now())']));
  assert.equal(failures.length, 1);
  assert.match(failures[0], /Note\.createdAt .*unannotated field/);
});

test('an annotation must be well formed', () => {
  const failures = check(
    model([
      ...ID,
      '/// @privacy(class=secret, retention=soon, visibleTo=everyone)',
      'flag Boolean',
    ]),
  );
  assert.equal(failures.length, 3);
});

test('plaintext-named String without ciphertext fails', () => {
  for (const field of ['displayName String?', 'statusMessage String', 'caption String?']) {
    const failures = check(
      model([...ID, '/// @privacy(class=public, retention=30d, visibleTo=members)', field]),
    );
    assert.equal(failures.length, 1, field);
    assert.match(failures[0], /plaintext-named String field is not ciphertext/);
  }
});

test('identifiers named after content are not plaintext', () => {
  const failures = check(
    model([
      ...ID,
      '/// @privacy(class=routing, retention=30d, visibleTo=members)',
      'messageId String',
    ]),
  );
  assert.deepEqual(failures, []);
});

test('an allowlisted plaintext field passes, and a stale allowlist entry fails', () => {
  const schema = model([
    ...ID,
    '/// @privacy(class=public, retention=30d, visibleTo=members)',
    'name String',
  ]);
  assert.deepEqual(check(schema, SWEEPS, { 'Note.name': 'deferred' }), []);
  const stale = check(schema, SWEEPS, { 'Note.name': 'deferred', 'Note.title': 'gone' });
  assert.deepEqual(stale, [
    'allowlist entry Note.title no longer matches a stored plaintext-named field',
  ]);
});

test('TTL without sweep marker fails', () => {
  const failures = check(model(ID), '// nothing swept here\n');
  assert.equal(failures.length, 1);
  assert.match(failures[0], /Note: .*no "\/\/ @retention-sweep Note" marker/);
});

test('account-lifetime fields need no sweep', () => {
  const schema = model([
    '/// @privacy(class=routing, retention=account, visibleTo=self)',
    'id String @id @db.Uuid',
  ]);
  assert.deepEqual(check(schema, ''), []);
});

test('relation fields store nothing and need no annotation', () => {
  const schema = [
    model([...ID, '/// @privacy(class=routing, retention=30d, visibleTo=self)', 'userId String']),
    'model User {',
    '  /// @privacy(class=routing, retention=account, visibleTo=public)',
    '  id String @id',
    '  notes Note[]',
    '}',
    '',
  ].join('\n');
  assert.deepEqual(check(schema), []);
});

test('the repository schema passes and its inventory is current', () => {
  const { failures, models } = checkSchemaPrivacy({
    schemaSource: repoFile(SCHEMA_PATH),
    retentionSource: repoFile(RETENTION_SERVICE_PATH),
  });
  assert.deepEqual(failures, []);
  assert.equal(renderInventory(models), repoFile(INVENTORY_PATH));
});

// The inventory is what a seizure yields. It once said a seized server holds
// these fields "as they are now, not as they were before a deletion", which is
// false: Postgres leaves deleted rows, burned one-time links among them, in its
// write-ahead log and freed table pages until it reuses the space. The
// inventory and metadata-retention.md must say so, and the real-Postgres spec
// they cite must still exist to show it.
const RESIDUE_SPEC = 'apps/api/test/unit/database-residue-postgres.spec.ts';
const RESIDUE_TEST =
  "keeps a burned one-time link's ciphertext in the write-ahead log and the table file after DELETE, VACUUM and CHECKPOINT";

test('the inventory and the retention document say deleted rows can stay on the database volume', () => {
  const flat = (text) => text.replace(/\s+/g, ' ');
  const intro = flat(renderInventory([]).split('## Classes')[0]);
  assert.doesNotMatch(intro, /as they are now|not as they were|holds only the current/i);
  assert.match(intro, /keeps no database dumps or snapshots/);
  assert.match(intro, /burned one-time links among them, in write-ahead-log segments/);
  assert.match(intro, /seized database volume can therefore also hold rows that were deleted/);

  const retention = repoFile('docs/metadata-retention.md');
  const start = retention.indexOf('### No database backups');
  assert.notEqual(start, -1, 'metadata-retention.md has no "No database backups" section');
  const section = flat(retention.slice(start, retention.indexOf('\n### ', start + 1)));
  assert.match(section, /does not mean a seized volume holds only the current rows/);
  assert.match(section, /deleted rows in its write-ahead-log segments/);
  assert.ok(section.includes(RESIDUE_SPEC), `the section must cite ${RESIDUE_SPEC}`);
  assert.ok(
    repoFile(RESIDUE_SPEC).includes(`it("${RESIDUE_TEST}"`),
    `${RESIDUE_SPEC} lost its test`,
  );
});

// The Redis key table is the public record of what the ephemeral store keeps
// and for how long. It once ended up under "Database and container logs",
// after two sections were inserted between it and its intro, so the intro's
// "the keys below" and the rows' "the snapshot caveat above" pointed at the
// wrong text. The table must sit in the Redis section, and only there.
const REDIS_SECTION = '### Short-lived keys in the ephemeral store (Redis)';
const REDIS_TABLE_HEADER = '| Key | Kept for | What it links |';
const REDIS_KEY_ROWS = [
  'veil:thr:*',
  'budget:*',
  'auth:challenge:*',
  'auth:refresh:*',
  'auth:rotated:*',
  'auth:blacklist:*',
  'group:keydist:*',
  'transfer:claim:*',
];

test('the retention document keeps the Redis key table in the Redis section', () => {
  const retention = repoFile('docs/metadata-retention.md');
  const start = retention.indexOf(REDIS_SECTION);
  assert.notEqual(start, -1, `metadata-retention.md has no "${REDIS_SECTION}" section`);
  const bodyStart = start + REDIS_SECTION.length;
  const next = retention.slice(bodyStart).search(/\n#{1,3} /);
  const section = next === -1 ? retention.slice(start) : retention.slice(start, bodyStart + next);

  assert.ok(section.includes(REDIS_TABLE_HEADER), 'the Redis section lost its key table');
  assert.equal(
    retention.split(REDIS_TABLE_HEADER).length,
    2,
    'the Redis key table must appear once, in the Redis section',
  );
  for (const key of REDIS_KEY_ROWS) {
    assert.ok(section.includes(`| \`${key}\``), `the Redis section's table has no row for ${key}`);
  }
});

// README, the privacy policies and docs/claims.yaml name these fields as the
// only user-written text the server stores readable; growing the list must
// change this test and that copy together.
test('the allowlist holds only group and channel names and descriptions and device labels', () => {
  assert.deepEqual(Object.keys(PLAINTEXT_ALLOWLIST).sort(), [
    'ChannelMeta.description',
    'ChannelMeta.name',
    'Device.deviceName',
    'GroupMeta.description',
    'GroupMeta.name',
  ]);
});
