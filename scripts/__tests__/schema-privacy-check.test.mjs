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
