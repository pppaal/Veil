import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  ADAPTER_SOURCE,
  RULES,
  STALE_STATEMENTS,
  checkDocFacts,
  readProductionAdapterId,
} from '../doc-facts.mjs';

const scratch = mkdtempSync(join(tmpdir(), 'veil-doc-facts-test-'));
after(() => rmSync(scratch, { recursive: true, force: true }));

const CURRENT = 'lib-x3dh-x25519-aes256gcm-v4';
const RETIRED = 'lib-x25519-aes256gcm-v3';

// A tree every rule accepts: the code each STALE_STATEMENTS entry relies on,
// two API modules, and documents that state only what the code does.
const CLEAN = {
  [ADAPTER_SOURCE]: `class LibCryptoAdapter {\n  String get adapterId => '${CURRENT}';\n}\n`,
  'apps/mobile/lib/src/core/crypto/ratchet/session_cipher.dart':
    'final plaintext = MessagePadding.pad(payload.encode());\n',
  'apps/web-demo/src/crypto/session-cipher.js':
    'const plaintext = padMessage(encodeInnerPayload(payload));\n',
  'apps/mobile/lib/src/features/conversations/data/group_sender_key_coordinator.dart':
    'class GroupSenderKeyCoordinator {}\n',
  'apps/api/src/common/guards/cf-throttler.guard.ts': 'switch (this.config.clientIpSource) {\n}\n',
  'apps/web-demo/src/crypto/frame.js': "export const ENVELOPE_VERSION_V2 = 'veil-envelope-v2';\n",
  'apps/api/src/modules/auth/auth.module.ts': '',
  'apps/api/src/modules/users/users.module.ts': '',
  'README.md': [
    '# VEIL',
    '',
    `The production adapter is \`${CURRENT}\`. The API has 2 modules.`,
    '',
    'The production boot guard is never removed: the attestation satisfies it.',
    '',
  ].join('\n'),
  'docs/history.md': [
    `Protocol v2 replaced the retired \`${RETIRED}\` adapter.`,
    '',
    'An older review quoted `veil-envelope-v1` and',
    `\`${RETIRED}\` together.`,
    '',
    '| Name | v1 (as written against) | Proposal |',
    '| --- | --- | --- |',
    `| Adapter id | \`${RETIRED}\` | \`lib-mlkem768-x25519-aes256gcm-v3\` |`,
    '',
  ].join('\n'),
  'scripts/release.mjs': "const caveat = `adapter ${readProductionAdapterId('.')}`;\n",
};

let trees = 0;
const tree = (overrides = {}) => {
  trees += 1;
  const root = join(scratch, `tree-${trees}`);
  for (const [path, contents] of Object.entries({ ...CLEAN, ...overrides })) {
    if (contents === null) continue;
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), contents);
  }
  return root;
};

const failuresOf = (rule, overrides) =>
  checkDocFacts(tree(overrides)).filter((failure) => failure.startsWith(`[${rule}]`));

test('a tree whose documents match the code passes', () => {
  assert.deepEqual(checkDocFacts(tree()), []);
});

test('the production adapter id is read from LibCryptoAdapter', () => {
  assert.equal(readProductionAdapterId(tree()), CURRENT);
  assert.deepEqual(
    failuresOf(RULES.adapterId, { [ADAPTER_SOURCE]: 'class LibCryptoAdapter {}\n' }),
    [`[${RULES.adapterId}] ${ADAPTER_SOURCE} declares no adapterId`],
  );
});

test('the production adapter id is read through a string constant the getter returns', () => {
  // The shape a behaviour-preserving refactor of lib_crypto_adapter.dart gave
  // the getter: it returns a top-level constant instead of a literal.
  const viaConstant = {
    [ADAPTER_SOURCE]: [
      "/// [LibCryptoAdapter.adapterId]: VEIL's own X3DH and Double Ratchet.",
      `const String kLibCryptoAdapterId = '${CURRENT}';`,
      '',
      'class LibCryptoAdapter {',
      '  @override',
      '  String get adapterId => kLibCryptoAdapterId;',
      '}',
      '',
    ].join('\n'),
  };
  assert.equal(readProductionAdapterId(tree(viaConstant)), CURRENT);
  assert.deepEqual(checkDocFacts(tree(viaConstant)), []);
  // The constant still decides what counts as current.
  assert.equal(
    failuresOf(RULES.adapterId, {
      ...viaConstant,
      'docs/threat-model.md': `- the AEAD binds the header (mobile adapter \`${RETIRED}\`)\n`,
    }).length,
    1,
  );

  const unresolved = {
    [ADAPTER_SOURCE]: 'class LibCryptoAdapter {\n  String get adapterId => kElsewhere;\n}\n',
  };
  assert.throws(() => readProductionAdapterId(tree(unresolved)), /adapterId returns kElsewhere/);
  assert.deepEqual(failuresOf(RULES.adapterId, unresolved), [
    `[${RULES.adapterId}] ${ADAPTER_SOURCE}: adapterId returns kElsewhere, which the file does not declare as a string constant`,
  ]);
});

test('a retired adapter id named as the production one fails, in a document or a script', () => {
  const failures = failuresOf(RULES.adapterId, {
    'docs/threat-model.md': `- the AEAD binds the header (mobile adapter \`${RETIRED}\`)\n`,
    'scripts/release.mjs': `const caveat = 'Production crypto adapter (${RETIRED}) is wired';\n`,
  });
  assert.equal(failures.length, 2, failures.join('\n'));
  assert.match(failures[0], /docs\/threat-model\.md:1 names lib-x25519-aes256gcm-v3 as current/);
  assert.match(failures[1], /scripts\/release\.mjs:1 names lib-x25519-aes256gcm-v3 as current/);
});

test('a table row is read with its own header row, not with the line before it', () => {
  const failures = failuresOf(RULES.adapterId, {
    'docs/table.md': [
      'The retired id appears in the table below.',
      '| Name | Value |',
      '| --- | --- |',
      `| Adapter id | \`${RETIRED}\` |`,
      '',
    ].join('\n'),
  });
  assert.equal(failures.length, 1, failures.join('\n'));
  assert.match(failures[0], /docs\/table\.md:4/);
});

test('a document that removes or relaxes the production boot guard fails', () => {
  const statements = [
    'Remove the production boot guard only after the mock adapters are fully replaced.',
    'Do not remove the production boot guard until the audit completes.',
    'The production boot guard can be reevaluated.',
  ];
  for (const statement of statements) {
    assert.equal(
      failuresOf(RULES.bootGuard, { 'docs/production.md': `- ${statement}\n` }).length,
      1,
      statement,
    );
  }
  for (const prohibition of [
    'Never bypass the production boot guard.',
    'Never disable the production boot guard, even when testing.',
  ]) {
    assert.deepEqual(
      failuresOf(RULES.bootGuard, { 'docs/production.md': `- ${prohibition}\n` }),
      [],
      prohibition,
    );
  }
  // "even" widens only the condition word right after it.
  assert.equal(
    failuresOf(RULES.bootGuard, {
      'docs/production.md':
        '- Do not remove the production boot guard, even when testing, until the audit completes.\n',
    }).length,
    1,
  );
});

test('each stale statement fails while its code stands', () => {
  const statements = {
    'message-padding-absent':
      '| **Message-length padding** | ⚠️ **absent in prod** | ciphertext length ≈ plaintext length |',
    'sender-keys-design-only':
      '- [Group Sender Keys Design](docs/group-sender-keys-design.md) — design only',
    'throttler-header-fallback':
      '- Custom `CfThrottlerGuard` prefers `cf-connecting-ip`, falls back to `deviceId`',
    'web-protocol-in-superseded-spec':
      '- Web demo: its protocol status is tracked in `docs/envelope-v3-unified-spec.md`.',
  };
  assert.deepEqual(Object.keys(statements).sort(), STALE_STATEMENTS.map(({ id }) => id).sort());
  for (const [id, statement] of Object.entries(statements)) {
    const failures = failuresOf(RULES.staleStatement, { 'docs/status.md': `${statement}\n` });
    assert.ok(failures.length >= 1, `${id}: ${statement}`);
    assert.ok(
      failures.every((failure) => failure.includes(`] ${id}: docs/status.md says`)),
      failures.join('\n'),
    );
  }
});

test('an entry whose code is gone fails instead of guarding nothing', () => {
  assert.deepEqual(
    failuresOf(RULES.staleStatement, {
      'apps/web-demo/src/crypto/session-cipher.js': 'const plaintext = encode(payload);\n',
    }),
    [
      `[${RULES.staleStatement}] message-padding-absent: apps/web-demo/src/crypto/session-cipher.js ` +
        'no longer shows that both clients pad every message to a size bucket before AES-GCM; ' +
        'update STALE_STATEMENTS in scripts/doc-facts.mjs',
    ],
  );
  assert.equal(
    failuresOf(RULES.staleStatement, { 'apps/web-demo/src/crypto/frame.js': null }).length,
    1,
  );
});

test('hard-coded test and migration counts fail, and a module count must match the tree', () => {
  const counts = [
    '| `apps/api/` | NestJS backend — Jest suites, 18 Prisma migrations |',
    '| `apps/mobile/` | Flutter app, 32 test files |',
    '| `apps/web-demo/` | 47 Vitest unit + 4 Playwright e2e specs |',
  ];
  for (const line of counts) {
    assert.equal(failuresOf(RULES.counts, { 'README.md': `${line}\n` }).length, 1, line);
  }
  assert.equal(
    failuresOf(RULES.counts, {
      'docs/launch-runbook.md': '- [ ] `flutter test` is green (78/78 currently).\n',
    }).length,
    1,
  );
  // The security roadmap's "measured" table once counted grep hits.
  const roadmap = [
    '| Capability | State | Evidence |',
    '| --- | --- | --- |',
    '| TLS pinning | ✅ present | `buildPinnedHttpClient`, 5 files |',
    '| Disappearing / view-once messages | ✅ present | 100 files |',
    '| Rate limiting / abuse throttle | ✅ present | `@Throttle`, 29 files |',
    '| Safety numbers (manual key verification) | ✅ present | `safety_numbers.dart` — 60-digit |',
    '',
  ].join('\n');
  const roadmapFailures = failuresOf(RULES.counts, {
    'docs/security-hardening-roadmap.md': roadmap,
  });
  assert.equal(roadmapFailures.length, 3, roadmapFailures.join('\n'));
  for (const failure of roadmapFailures) {
    assert.match(failure, /docs\/security-hardening-roadmap\.md hard-codes a .* count/);
  }
  assert.deepEqual(failuresOf(RULES.counts, { 'README.md': 'The API has 3 modules.\n' }), [
    `[${RULES.counts}] README.md says 3 modules; apps/api/src/modules has 2`,
  ]);
});

test('the repository passes', () => {
  const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
  assert.deepEqual(checkDocFacts(repoRoot), []);
});
