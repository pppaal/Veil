import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { checkClaims, parseLedger, sentencesOf } from '../claims-check.mjs';

const scratch = mkdtempSync(join(tmpdir(), 'veil-claims-test-'));
after(() => rmSync(scratch, { recursive: true, force: true }));

const README = [
  '# Demo',
  '',
  'Messages are end-to-end encrypted. The',
  'app is fast.',
  '',
  '| Capability | State |',
  '| --- | --- |',
  '| No backup | ✅ |',
  '',
].join('\n');

const LEDGER = `# A tiny ledger
claims:
  - id: e2e
    text: "Messages are end-to-end encrypted."
    sources:
      - file: README.md
        quote: Messages are end-to-end encrypted.
    evidence:
      - test: tests/crypto.test.mjs
        name: "encrypts on the device"
  - id: no-backup
    text: 'There is no backup.'
    sources:
      - file: README.md
        quote: "No backup | ✅"
    evidence:
      - gate: scripts/policy.mjs
`;

let trees = 0;
const tree = (overrides = {}) => {
  trees += 1;
  const root = join(scratch, `tree-${trees}`);
  const files = {
    'package.json': JSON.stringify({ scripts: { 'policy:check': 'node ./scripts/policy.mjs' } }),
    'README.md': README,
    'docs/claims.yaml': LEDGER,
    'tests/crypto.test.mjs': "test('encrypts on the device', () => {});\n",
    'scripts/policy.mjs': '',
    ...overrides,
  };
  for (const [path, contents] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), contents);
  }
  return root;
};

test('a ledger whose claims are quoted and backed passes', () => {
  assert.deepEqual(checkClaims(tree()), []);
});

test('missing evidence test fails', () => {
  const failures = checkClaims(
    tree({ 'tests/crypto.test.mjs': "test('something else', () => {});\n" }),
  );
  assert.deepEqual(failures, [
    'e2e: tests/crypto.test.mjs has no test named "encrypts on the device"',
  ]);
});

test('a claim without evidence fails', () => {
  const ledger = LEDGER.replace(
    /    evidence:\n      - gate: scripts\/policy.mjs\n/,
    '    evidence: none\n',
  );
  assert.match(
    checkClaims(tree({ 'docs/claims.yaml': ledger })).join('\n'),
    /no-backup: has no evidence/,
  );
});

test('a gate CI never runs is not evidence', () => {
  const failures = checkClaims(tree({ 'package.json': JSON.stringify({ scripts: {} }) }));
  assert.deepEqual(failures, [
    'no-backup: gate scripts/policy.mjs is not run by any package.json script',
  ]);
});

test('unledgered claim sentence fails', () => {
  const failures = checkClaims(
    tree({ 'README.md': `${README}\nYour data is never stored anywhere. Except here.\n` }),
  );
  assert.deepEqual(failures, ['README.md: unledgered claim "Your data is never stored anywhere."']);
});

test('a line that opens with an inline code span does not hide later claims', () => {
  const markdownLite = [
    '- Markdown lite: `*bold*`,',
    '  ```` ```fenced code blocks``` ````, auto-linked URLs',
    '',
    'Your data is never stored anywhere.',
    '',
  ].join('\n');
  const failures = checkClaims(tree({ 'README.md': `${README}\n${markdownLite}` }));
  assert.deepEqual(failures, ['README.md: unledgered claim "Your data is never stored anywhere."']);
});

test('fenced code is skipped up to a closing fence of its own kind and length', () => {
  const source = [
    'Intro.',
    '````md',
    '```',
    'Never stored, inside a longer fence.',
    '````',
    '~~~',
    'Deleted on fetch, inside a tilde fence.',
    '~~~',
    'Outro.',
  ].join('\n');
  assert.deepEqual(sentencesOf(source, 'README.md'), ['Intro.', 'Outro.']);
});

test('a fence that never closes hides nothing', () => {
  assert.deepEqual(sentencesOf('Intro.\n\n```\nNever stored.\n', 'README.md'), [
    'Intro.',
    'Never stored.',
  ]);
});

test('a quote its source no longer says fails', () => {
  const failures = checkClaims(
    tree({ 'README.md': README.replace('end-to-end encrypted', 'encrypted') }),
  );
  assert.deepEqual(failures, [
    'e2e: README.md no longer says "Messages are end-to-end encrypted."',
  ]);
});

test('sentences join wrapped lines, drop markup and keep table rows whole', () => {
  assert.deepEqual(sentencesOf(README, 'README.md'), [
    'Demo',
    'Messages are end-to-end encrypted.',
    'The app is fast.',
    'Capability | State',
    'No backup | ✅',
  ]);
  assert.deepEqual(
    sentencesOf('<ul><li>Sealed <b>sender</b> is &quot;planned&quot;.</li></ul>', 'x.html'),
    ['Sealed sender is "planned".'],
  );
});

test('the ledger parser reads the subset and rejects anything else', () => {
  assert.deepEqual(parseLedger(LEDGER).claims[1], {
    id: 'no-backup',
    text: 'There is no backup.',
    sources: [{ file: 'README.md', quote: 'No backup | ✅' }],
    evidence: [{ gate: 'scripts/policy.mjs' }],
  });
  assert.throws(() => parseLedger('claims: [a, b]\n'), /unsupported YAML syntax/);
  assert.throws(
    () => parseLedger('claims:\n  - id: a\n  id: b\n'),
    /unexpected indentation|duplicate/,
  );
});

test('the repository ledger passes', () => {
  const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
  assert.deepEqual(checkClaims(repoRoot), []);
});
