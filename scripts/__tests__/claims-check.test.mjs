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

test('a test in a skipped or focused block is not evidence', () => {
  for (const marker of ['describe.skip', 'describe.only', 'xdescribe']) {
    const failures = checkClaims(
      tree({
        'tests/crypto.test.mjs': `${marker}('crypto', () => {\n  test('encrypts on the device', () => {});\n});\n`,
      }),
    );
    assert.deepEqual(failures, [
      'e2e: tests/crypto.test.mjs skips or focuses tests, so "encrypts on the device" may not run',
    ]);
  }
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

test('denying plaintext or disclosing readable data is a claim, mentioning plaintext is not', () => {
  const copy = [
    'Ciphertext length tracks plaintext length.',
    'The server never sees plaintext.',
    'Plaintext does not leave the device.',
    'Group names are stored in readable form.',
    '서버는 평문을 볼 수 없습니다.',
  ].join('\n\n');
  const failures = checkClaims(tree({ 'README.md': `${README}\n${copy}\n` }));
  assert.deepEqual(failures, [
    'README.md: unledgered claim "The server never sees plaintext."',
    'README.md: unledgered claim "Plaintext does not leave the device."',
    'README.md: unledgered claim "Group names are stored in readable form."',
    'README.md: unledgered claim "서버는 평문을 볼 수 없습니다."',
  ]);
});

test('saying the server holds only ciphertext is a claim', () => {
  const copy = [
    'DB 를 열면 메시지는 ciphertext 만 보입니다.',
    '서버는 메시지 내용을 암호문으로만 저장합니다.',
    '서버는 암호문만 중계합니다.',
    'Photos are held only as ciphertext.',
    'Ciphertext-only relay.',
    'Message payloads are transited as ciphertext only.',
    'Ciphertext length tracks the message length.',
  ].join('\n\n');
  const failures = checkClaims(tree({ 'README.md': `${README}\n${copy}\n` }));
  assert.deepEqual(failures, [
    'README.md: unledgered claim "DB 를 열면 메시지는 ciphertext 만 보입니다."',
    'README.md: unledgered claim "서버는 메시지 내용을 암호문으로만 저장합니다."',
    'README.md: unledgered claim "서버는 암호문만 중계합니다."',
    'README.md: unledgered claim "Photos are held only as ciphertext."',
    'README.md: unledgered claim "Ciphertext-only relay."',
    'README.md: unledgered claim "Message payloads are transited as ciphertext only."',
  ]);
});

test('a blanket statement about collection is a claim', () => {
  const copy = [
    'People who want a messenger with no ads and no data collection.',
    'Minimal data collection. The in-app consent screen lists every field.',
    '광고와 데이터 수집이 없는 메신저를 원하는 분.',
    'Minimal data collection.',
  ].join('\n\n');
  const failures = checkClaims(tree({ 'README.md': `${README}\n${copy}\n` }));
  assert.deepEqual(failures, [
    'README.md: unledgered claim "People who want a messenger with no ads and no data collection."',
    'README.md: unledgered claim "The in-app consent screen lists every field."',
    'README.md: unledgered claim "광고와 데이터 수집이 없는 메신저를 원하는 분."',
  ]);
});

test('calling the server-assigned ids anonymous or device-generated is a claim', () => {
  const copy = [
    'An anonymous user ID and device ID generated on the device.',
    '기기에서 생성된 익명 식별자(User ID, Device ID)',
    'A random account ID and device ID that the server assigns when you register, linked to your handle.',
    'An anonymous secure messenger.',
  ].join('\n\n');
  const failures = checkClaims(tree({ 'README.md': `${README}\n${copy}\n` }));
  assert.deepEqual(failures, [
    'README.md: unledgered claim "An anonymous user ID and device ID generated on the device."',
    'README.md: unledgered claim "기기에서 생성된 익명 식별자(User ID, Device ID)"',
  ]);
});

test('offering multi-device use is a claim', () => {
  // The Play listing once offered "multi-device access" while a transfer signs
  // the old device out and an account runs on one device at a time.
  const copy = [
    'For multi-device access, use the built-in encrypted device transfer.',
    'Use it on a multi device setup.',
    '다중 기기 동기화를 원하시면 기기 전송 기능을 사용해 주세요.',
    'VEIL runs on one device at a time.',
  ].join('\n\n');
  const failures = checkClaims(tree({ 'store/play/full-en.txt': `${copy}\n` }));
  assert.deepEqual(failures, [
    'store/play/full-en.txt: unledgered claim "For multi-device access, use the built-in encrypted device transfer."',
    'store/play/full-en.txt: unledgered claim "Use it on a multi device setup."',
    'store/play/full-en.txt: unledgered claim "다중 기기 동기화를 원하시면 기기 전송 기능을 사용해 주세요."',
  ]);
});

test('a store listing draft that advertises a backup is an unledgered claim', () => {
  // The App Store listing draft once offered "Signed backups" while VEIL has
  // none; the drafts in docs/launch are pasted into the stores.
  const draft = [
    '- **Signed backups.** Your local history can be sealed under a passphrase',
    '  you control.',
    '- Encrypted local backups you seal under a passphrase you control.',
    '',
  ].join('\n');
  const failures = checkClaims(
    tree({
      'docs/launch/app-store-listing.md': draft,
      'docs/app-store-listing-metadata.md': 'Restore from backup on a new phone.\n',
    }),
  );
  assert.deepEqual(failures, [
    'docs/app-store-listing-metadata.md: unledgered claim "Restore from backup on a new phone."',
    'docs/launch/app-store-listing.md: unledgered claim "Signed backups."',
    'docs/launch/app-store-listing.md: unledgered claim "Encrypted local backups you seal under a passphrase you control."',
  ]);
});

test('claims in HTML text attributes are scanned without splitting the element text', () => {
  const html = [
    '<meta name="description" content="Messages are never stored.">',
    '<p>Read <abbr title="end-to-end encryption">E2E</abbr> notes.</p>',
    '<img alt=\'Zero-knowledge vault\' src="x.png">',
  ].join('\n');
  assert.deepEqual(sentencesOf(html, 'site/index.html'), [
    'Read E2E notes.',
    'Messages are never stored.',
    'end-to-end encryption',
    'Zero-knowledge vault',
  ]);
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
