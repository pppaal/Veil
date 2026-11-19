import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  APPLE_ANSWERS,
  PLAY_ANSWERS,
  SCHEMA,
  checkStoreLabels,
  parseAppleAnswers,
  parsePlayAnswers,
} from '../store-label-check.mjs';

const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
const real = (path) => readFileSync(join(repoRoot, path), 'utf8');

const scratch = mkdtempSync(join(tmpdir(), 'veil-store-label-test-'));
after(() => rmSync(scratch, { recursive: true, force: true }));

let trees = 0;
// The repository's own answers and schema, plus the documents a test adds.
const tree = (overrides = {}) => {
  trees += 1;
  const root = join(scratch, `tree-${trees}`);
  const files = {
    [APPLE_ANSWERS]: real(APPLE_ANSWERS),
    [PLAY_ANSWERS]: real(PLAY_ANSWERS),
    [SCHEMA]: real(SCHEMA),
    ...overrides,
  };
  for (const [path, contents] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), contents);
  }
  return root;
};

test('the repository passes', () => {
  assert.deepEqual(checkStoreLabels(repoRoot), []);
});

test('the answers files parse into what they declare', () => {
  const apple = parseAppleAnswers(real(APPLE_ANSWERS));
  for (const name of ['Contacts', 'User ID', 'Device ID', 'Other User Content']) {
    assert.ok(apple.collected.has(name), `App Store answers declare ${name}`);
  }
  for (const name of ['Contact Info', 'Crash Data', 'Location', 'Usage Data']) {
    assert.ok(apple.notCollected.has(name), `App Store answers do not declare ${name}`);
  }
  const play = parsePlayAnswers(real(PLAY_ANSWERS));
  for (const name of [
    'Contacts',
    'User IDs',
    'Device or other IDs',
    'Other user-generated content',
    'Other in-app messages',
  ]) {
    assert.ok(play.collected.has(name), `Play answers declare ${name}`);
  }
  for (const name of ['Crash logs', 'Name', 'Precise location']) {
    assert.ok(play.notCollected.has(name), `Play answers do not declare ${name}`);
  }
});

// The launch docs as round 2 of the wave-2 review found them.
const STALE_APP_STORE_LISTING = `# App Store Listing — Draft

## Privacy nutrition label

### Data Not Collected

This is the truth for Veil. Every category below maps to "Data Not
Collected" in App Store Connect's privacy questionnaire, assuming the
crash reporter is off or configured as "Not linked to identity."

- Contact Info — not collected
- Contacts — not collected (no address-book sync by design)
- User Content — encrypted on the user's device; the server never has
  access to plaintext, therefore not "collected" per Apple's definition
- Identifiers — **handle only**, no IDFA, no IDFV linked to identity
- Diagnostics — crash logs only, not linked to identity, user-togglable

### Tracking
`;

const STALE_PLAY_LISTING = `# Google Play Listing — Draft

| Category          | Collected? | Shared? | Purpose      | Optional? | Notes |
|-------------------|-----------|---------|--------------|-----------|-------|
| User IDs          | Yes       | No      | Functionality| No        | server-generated userId + deviceId |
| Contacts          | No        | —       | —            | —         | no address-book sync by design |
| Device/other IDs  | No        | —       | —            | —         | no IDFA/AAID collected |
`;

const STALE_METADATA = `## Privacy "nutrition label" (App Store Connect) — answer precisely

- **Data NOT collected:** message content, contacts, precise location, browsing
  history.
`;

const STALE_RUNBOOK = `6. Data safety form → mirror the declarations in [\`store/appstore/app-privacy-answers.md\`](../store/appstore/app-privacy-answers.md). Key calls:
   - Data collected: User ID, Device ID (both "App functionality", not tracking).
`;

const STALE_GO_LIVE = `- **Data safety form** → mirror \`store/appstore/app-privacy-answers.md\`
  (User ID + Device ID, "App functionality", no tracking, no ads, no
  third-party analytics).
`;

test('the stale launch docs fail, each for what it got wrong', () => {
  const failures = checkStoreLabels(
    tree({
      'docs/launch/app-store-listing.md': STALE_APP_STORE_LISTING,
      'docs/launch/play-store-listing.md': STALE_PLAY_LISTING,
      'docs/app-store-listing-metadata.md': STALE_METADATA,
      'docs/launch-runbook.md': STALE_RUNBOOK,
      'docs/go-live-today.md': STALE_GO_LIVE,
    }),
  );
  const expected = [
    'docs/app-store-listing-metadata.md: says "Contacts" is not collected',
    'docs/go-live-today.md: summarises the label with the identifiers but without Contacts and the linked user content',
    'docs/launch-runbook.md: summarises the label with the identifiers but without Contacts and the linked user content',
    'docs/launch/app-store-listing.md: frames the label as "Data Not Collected" throughout',
    'docs/launch/app-store-listing.md: says "Contacts" is not collected',
    'docs/launch/app-store-listing.md: says "User Content" is not collected',
    'docs/launch/app-store-listing.md:12: lists "Contacts" as not collected',
    'docs/launch/app-store-listing.md:13: lists "User Content" as not collected',
    'docs/launch/app-store-listing.md:15: lists "Identifiers" as not collected',
    'docs/launch/play-store-listing.md:6: lists "Contacts" as not collected',
    'docs/launch/play-store-listing.md:7: lists "Device or other IDs" as not collected',
  ];
  for (const prefix of expected) {
    assert.ok(
      failures.some((failure) => failure.startsWith(prefix)),
      `expected a failure starting "${prefix}" in:\n${failures.join('\n')}`,
    );
  }
  assert.equal(failures.length, expected.length, failures.join('\n'));
});

test('statements that do not contradict the answers pass', () => {
  const doc = [
    '# Notes',
    '',
    '- **Contacts**: collected (the phone address book is not collected).',
    '- Contacts are collected; crash data is not collected.',
    '- Advertising identifiers (IDFA/AAID) are not collected.',
    '',
    'The service does **not** collect:',
    '',
    '- Phone numbers, email addresses, or real names.',
    "- Your phone's address book or call log, or location data.",
    '',
    '## Data Not Collected',
    '',
    '- Health & Fitness',
    '- Crash Data (no crash-reporting SDK ships)',
    '',
    'Data collected: User ID, Device ID, Contacts (the in-app contact list) and',
    'Other User Content (group and channel names and descriptions).',
    '',
  ].join('\n');
  assert.deepEqual(checkStoreLabels(tree({ 'docs/notes.md': doc })), []);
});

test('a list under a "not collected" lead-in fails, in Markdown and HTML', () => {
  const markdown = ['The service does not collect:', '', '- Contacts', ''].join('\n');
  const html = [
    '<p>다음 항목은 <strong>수집하지 않습니다</strong>.</p>',
    '<ul>',
    '  <li>휴대폰 번호, 이메일 주소</li>',
    '  <li>연락처</li>',
    '</ul>',
  ].join('\n');
  assert.deepEqual(
    checkStoreLabels(tree({ 'docs/policy.md': markdown, 'site/index.html': html })),
    [
      'docs/policy.md:3: lists "Contacts" as not collected, but the store answers declare it collected',
      'site/index.html:4: lists "Contacts" as not collected, but the store answers declare it collected',
    ],
  );
});

test('answers that leave out what the server stores fail', () => {
  const apple = real(APPLE_ANSWERS)
    .replace(/### Contacts\n[\s\S]*?(?=\n### )/, '')
    .replace('### Data Not Collected\n', '### Data Not Collected\n- Contacts\n');
  assert.notEqual(apple, real(APPLE_ANSWERS));
  const failures = checkStoreLabels(tree({ [APPLE_ANSWERS]: apple }));
  assert.deepEqual(failures, [
    `${APPLE_ANSWERS}: the server stores the in-app contact list (a social graph) (model UserContact), so "Contacts" must be declared collected (it is not collected)`,
    `${APPLE_ANSWERS}: the server stores call records (call history) (model CallRecord), so "Contacts" must be declared collected (it is not collected)`,
    'the stores disagree: App Store "Contacts" is not collected, Play "Contacts" is collected',
  ]);
});

test('Play answers that leave out push tokens or readable names fail', () => {
  const play = real(PLAY_ANSWERS)
    .replace(/^\| Device or other IDs \| Yes \|/m, '| Device or other IDs | No |')
    .replace(/^\| Other user-generated content \|.*\n/m, '');
  const failures = checkStoreLabels(tree({ [PLAY_ANSWERS]: play }));
  assert.deepEqual(failures, [
    `${PLAY_ANSWERS}: the server stores device ids (model Device), so "Device or other IDs" must be declared collected (it is not collected)`,
    `${PLAY_ANSWERS}: the server stores device push tokens (Device.pushToken), so "Device or other IDs" must be declared collected (it is not collected)`,
    `${PLAY_ANSWERS}: the server stores readable group names and descriptions (GroupMeta.name), so "Other user-generated content" must be declared collected (it is unanswered)`,
    `${PLAY_ANSWERS}: the server stores readable channel names and descriptions (ChannelMeta.name), so "Other user-generated content" must be declared collected (it is unanswered)`,
    `${PLAY_ANSWERS}: the server stores readable device labels (Device.deviceName), so "Other user-generated content" must be declared collected (it is unanswered)`,
    'the stores disagree: App Store "Device ID" is collected, Play "Device or other IDs" is not collected',
  ]);
});

test('a missing answers file fails', () => {
  const root = tree();
  rmSync(join(root, PLAY_ANSWERS));
  assert.deepEqual(checkStoreLabels(root), [`${PLAY_ANSWERS} does not exist`]);
});
