import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { handoffReadme } from '../audit-handoff-bundle.mjs';
import {
  AUDIT_CODE_PATHS,
  AUDIT_DOCS,
  PROTOCOL_REVIEW_QUESTION,
  assertAuditScope,
  missingAuditPaths,
  securityInScopePaths,
  uncoveredSecurityPaths,
} from '../audit-scope.mjs';
import { buildManifest } from '../external-review-manifest.mjs';

const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
const scratch = mkdtempSync(join(tmpdir(), 'veil-audit-scope-test-'));
after(() => rmSync(scratch, { recursive: true, force: true }));

test('every audit-scope document and code path exists', () => {
  assert.deepEqual(missingAuditPaths(repoRoot), []);
  assert.doesNotThrow(() => assertAuditScope(repoRoot));
});

test('a path missing from the tree is a hard error', () => {
  const root = join(scratch, 'missing');
  mkdirSync(root, { recursive: true });
  assert.throws(() => assertAuditScope(root), /docs\/crypto-envelope-spec\.md/);
});

test('every in-scope path of SECURITY.md is covered by an audit code path', () => {
  const inScope = securityInScopePaths(readFileSync(join(repoRoot, 'SECURITY.md'), 'utf8'));
  assert.ok(inScope.includes('apps/web-demo/src/crypto'), inScope.join(', '));
  assert.deepEqual(uncoveredSecurityPaths(repoRoot), []);
});

test('an in-scope path no code path covers is reported', () => {
  const root = join(scratch, 'uncovered');
  mkdirSync(root, { recursive: true });
  writeFileSync(
    join(root, 'SECURITY.md'),
    [
      'In scope:',
      '',
      '- Flaws in `apps/web-demo/src/crypto/` and `apps/web-demo/src/ui/`',
      '- Auth bypass (`apps/api/src/modules/auth`)',
      '',
      'Out of scope:',
      '',
      '- `apps/web-demo/src/legacy/`',
      '',
    ].join('\n'),
  );
  assert.deepEqual(uncoveredSecurityPaths(root), ['apps/web-demo/src/ui']);
  writeFileSync(join(root, 'SECURITY.md'), 'No scope list here.\n');
  assert.throws(() => uncoveredSecurityPaths(root), /In scope/);
});

test('the scope reaches both protocol-v2 clients, the trust layer and the key directory', () => {
  for (const path of [
    'apps/web-demo/src/crypto',
    'apps/web-demo/src/app/messaging-stack.js',
    'apps/web-demo/src/domain/peer-bindings.js',
    'apps/mobile/lib/src/core/crypto',
    'apps/mobile/lib/src/features/conversations/data/messenger',
    'apps/mobile/lib/src/features/conversations/data/group_sender_key_coordinator.dart',
    'apps/api/src/modules/prekeys',
    'apps/api/src/modules/groups',
    'packages/shared/test-vectors',
    'scripts/crypto-test-vectors.mjs',
  ]) {
    assert.ok(AUDIT_CODE_PATHS.includes(path), path);
  }
  for (const doc of [
    'docs/crypto-envelope-spec.md',
    'docs/group-sender-keys-design.md',
    'docs/security/crypto-surfaces.md',
  ]) {
    assert.ok(AUDIT_DOCS.includes(doc), doc);
  }
});

test('the manifest carries the scope and asks about protocol v2', () => {
  const manifest = buildManifest({ commitSha: 'abc123', generatedAt: 'now' });
  assert.deepEqual(manifest.docs, AUDIT_DOCS);
  assert.deepEqual(manifest.codePaths, AUDIT_CODE_PATHS);
  assert.ok(manifest.reviewQuestions.includes(PROTOCOL_REVIEW_QUESTION));
  assert.match(PROTOCOL_REVIEW_QUESTION, /crypto-envelope-spec\.md/);
});

test('the handoff README describes the crypto as it ships, with no hard-coded test counts', () => {
  const readme = handoffReadme({ sha: 'abc123', branch: 'main', generatedAt: 'now' });
  for (const path of AUDIT_CODE_PATHS) {
    assert.ok(readme.includes(`  ${path}\n`), path);
  }
  assert.match(readme, /crypto-envelope-spec\.md` — \*\*normative\*\*/);
  assert.match(readme, /envelope-v3-unified-spec\.md` — superseded and never implemented/);
  assert.match(
    readme,
    /group-sender-keys-design\.md` — Sender Keys for groups: implemented on\s+mobile/,
  );
  assert.doesNotMatch(readme, /spec only/);
  assert.doesNotMatch(readme, /\b\d+ (?:unit|e2e) tests\b/);
  assert.match(readme, /node scripts\/crypto-test-vectors\.mjs --check/);
  assert.match(readme, /pnpm -C apps\/web-demo test/);
  assert.match(readme, /flutter test/);
});

// The audit is what may unlock a production boot; the documents that set its
// scope must not describe the crypto from before protocol v2.
test('the outward audit documents no longer describe the pre-v2 crypto', () => {
  const read = (path) => readFileSync(join(repoRoot, path), 'utf8');
  const rfp = read('docs/audit-rfp-email-en.md');
  assert.doesNotMatch(rfp, /no DH ratchet yet/);
  assert.doesNotMatch(rfp, /Sender Keys[^.\n]*not implemented/);
  assert.match(rfp, /crypto-envelope-spec\.md/);
  const otf = read('docs/otf-application-template.md');
  assert.doesNotMatch(otf, /three pending designs/);
  const packet = read('docs/external-security-review-packet.md');
  assert.match(packet, /crypto-envelope-spec\.md/);
  assert.match(packet, /VEIL_CLIENT_IP_SOURCE/);
  assert.doesNotMatch(packet, /Tracker preference order: `cf-connecting-ip`, then/);
  const surfaces = read('docs/security/crypto-surfaces.md');
  for (const gone of [
    'backup_envelope.dart',
    'session_state_migration.dart',
    'PBKDF2-SHA256 (600k)',
  ]) {
    assert.ok(!surfaces.includes(gone), gone);
  }
  for (const present of [
    'x3dh/x3dh_handshake.dart',
    'ratchet/session_cipher.dart',
    'attachment/attachment_cipher_v2.dart',
    'group_sender_keys.dart',
    'apps/web-demo/src/crypto/x3dh.js',
    'apps/web-demo/src/crypto/pins.js',
    'identity_trust.dart',
  ]) {
    assert.ok(surfaces.includes(present), present);
  }
  // Every repository path the catalog names exists.
  const named = [...surfaces.matchAll(/`((?:apps|packages|scripts)\/[^`\s]+)`/g)].map((m) => m[1]);
  assert.ok(named.length > 10);
  for (const path of named) {
    assert.ok(existsSync(join(repoRoot, path)), path);
  }
});
