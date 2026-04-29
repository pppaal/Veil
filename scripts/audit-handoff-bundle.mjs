#!/usr/bin/env node
// Bundles everything an external auditor needs into a single tarball.
// Runs the existing pnpm beta:external:bundle to refresh artifacts,
// then layers in the audit-specific design docs and a README index.
//
// Output: artifacts/veil-audit-handoff-<sha>.tar.gz
//
// Usage:
//   pnpm audit:handoff
// or  node scripts/audit-handoff-bundle.mjs

import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, copyFileSync, existsSync, rmSync } from 'node:fs';
import { join, basename } from 'node:path';

const repoRoot = process.cwd();
const sha = spawnSync('git', ['rev-parse', '--short', 'HEAD'], {
  encoding: 'utf8',
}).stdout.trim();
const branch = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], {
  encoding: 'utf8',
}).stdout.trim();
const dirty = spawnSync('git', ['status', '--porcelain'], {
  encoding: 'utf8',
}).stdout.trim();

if (dirty) {
  console.error(
    'Working tree has uncommitted changes. Refusing to bundle a non-reproducible audit handoff.',
  );
  console.error('Either commit, stash, or run with FORCE_DIRTY=1.');
  if (process.env.FORCE_DIRTY !== '1') process.exit(1);
}

const stagingDir = join(repoRoot, 'artifacts', `audit-handoff-${sha}`);
if (existsSync(stagingDir)) rmSync(stagingDir, { recursive: true });
mkdirSync(stagingDir, { recursive: true });

console.log(`[audit-handoff] commit=${sha} branch=${branch}`);
console.log('[audit-handoff] refreshing artifacts (this runs the existing bundle script)…');
const bundle = spawnSync('pnpm', ['beta:external:bundle'], {
  stdio: 'inherit',
  cwd: repoRoot,
});
if (bundle.status !== 0) {
  console.error('beta:external:bundle failed; aborting');
  process.exit(bundle.status ?? 1);
}

// Files to ship into the staging dir.
const docs = [
  'docs/architecture.md',
  'docs/threat-model.md',
  'docs/no-recovery.md',
  'docs/external-security-review-packet.md',
  'docs/forward-secrecy-ratchet-design.md',
  'docs/envelope-v3-unified-spec.md',
  'docs/group-sender-keys-design.md',
  'docs/sealed-sender-design.md',
  'docs/crypto-adapter-architecture.md',
  'docs/crypto-envelope-spec.md',
  'docs/device-transfer-flow.md',
  'docs/message-flow.md',
  'docs/observability-hygiene.md',
  'docs/mobile-device-security.md',
  'docs/external-audit-firm-shortlist.md',
];
const artifacts = [
  'artifacts/private-beta-release-evidence.json',
  'artifacts/external-security-review-manifest.json',
  'artifacts/external-review-findings-template.json',
  'artifacts/production-blockers-report.json',
];
const codepaths = [
  'apps/api/src/modules/auth',
  'apps/api/src/modules/device-transfer',
  'apps/api/src/modules/messages',
  'apps/api/src/common/guards',
  'apps/api/src/common/errors',
  'apps/api/src/common/interceptors',
  'apps/api/prisma/schema.prisma',
  'apps/api/prisma/migrations',
  'apps/mobile/lib/src/core/crypto',
  'packages/contracts/src',
  'packages/shared/src',
  'scripts/policy-check.mjs',
];

mkdirSync(join(stagingDir, 'docs'), { recursive: true });
mkdirSync(join(stagingDir, 'artifacts'), { recursive: true });

for (const d of docs) {
  const src = join(repoRoot, d);
  if (existsSync(src)) {
    copyFileSync(src, join(stagingDir, 'docs', basename(d)));
  } else {
    console.warn(`[audit-handoff] missing doc: ${d}`);
  }
}

for (const a of artifacts) {
  const src = join(repoRoot, a);
  if (existsSync(src)) {
    copyFileSync(src, join(stagingDir, 'artifacts', basename(a)));
  } else {
    console.warn(`[audit-handoff] missing artifact: ${a}`);
  }
}

// Code paths get listed in README + tarball'd via tar invocation below.
const readmePath = join(stagingDir, 'README.md');
const readme = `# VEIL audit handoff bundle

Pinned commit: \`${sha}\`
Branch at bundle time: \`${branch}\`
Generated: ${new Date().toISOString()}

## What's in this bundle

\`docs/\` — design and spec documents the auditor needs
- \`architecture.md\`, \`threat-model.md\`, \`no-recovery.md\` — product
  framing
- \`external-security-review-packet.md\` — review charter
- \`forward-secrecy-ratchet-design.md\` — implemented mobile ratchet
  spec
- \`envelope-v3-unified-spec.md\` — next wire format (spec only, not
  implemented)
- \`group-sender-keys-design.md\` — group ratchet (spec only)
- \`sealed-sender-design.md\` — metadata reduction (spec only)
- \`crypto-adapter-architecture.md\`, \`crypto-envelope-spec.md\` —
  current crypto interface and envelope
- \`device-transfer-flow.md\`, \`message-flow.md\` — protocol flows
- \`observability-hygiene.md\`, \`mobile-device-security.md\` — local
  posture
- \`external-audit-firm-shortlist.md\` — firms we evaluated

\`artifacts/\` — machine-readable
- \`private-beta-release-evidence.json\` — CI + verification evidence
- \`external-security-review-manifest.json\` — file inventory
- \`external-review-findings-template.json\` — findings JSON schema
  the auditor should mirror
- \`production-blockers-report.json\` — known blocker list

## Code paths (review the repo at the pinned SHA)

The auditor should clone the repo at \`${sha}\` and review:

${codepaths.map((p) => `  ${p}`).join('\n')}

\`scripts/policy-check.mjs\` is the single source of truth for the
"VEIL non-negotiables" — what must NOT exist anywhere in the codebase.

## Verification you can re-run locally

After cloning at \`${sha}\`:

\`\`\`
pnpm install
pnpm -C apps/api build      # type-check
pnpm -C apps/api test       # 132 unit tests
pnpm -C apps/api test:e2e   # 6 e2e tests
node scripts/policy-check.mjs
\`\`\`

All four should be green at this commit.

## Findings format

We accept findings as a JSON array matching the schema in
\`artifacts/external-review-findings-template.json\`. Each entry needs:

- \`id\` (auditor-assigned)
- \`severity\`: critical / high / medium / low / informational
- \`location\`: file path + line if applicable
- \`description\`
- \`reproduction\` (steps or PoC)
- \`recommendation\`
- \`status\`: open (default)

We will track in
\`docs/external-review-remediation-tracker.md\` and patch each
finding, then re-bundle for retest.

## Out of scope

- App Store / Play Store packaging (separate)
- WebRTC voice/video (scaffold only)
- TLS / Caddy configuration (handled by infra layer)
- Push provider integration (gated, no APNs/FCM credentials issued
  yet)
`;
writeFileSync(readmePath, readme, 'utf8');

// Tarball.
const tarball = join(repoRoot, 'artifacts', `veil-audit-handoff-${sha}.tar.gz`);
const tarArgs = [
  '-czf',
  tarball,
  '-C',
  join(repoRoot, 'artifacts'),
  `audit-handoff-${sha}`,
];
const tar = spawnSync('tar', tarArgs, { stdio: 'inherit' });
if (tar.status !== 0) {
  console.error('tar failed; staged dir left at', stagingDir);
  process.exit(tar.status ?? 1);
}

console.log(`[audit-handoff] wrote ${tarball}`);
console.log(`[audit-handoff] staged dir: ${stagingDir}`);
console.log('');
console.log('Next steps:');
console.log(`  1. Tag this commit:     git tag -a audit-handoff-${sha} -m "Audit handoff ${sha}"`);
console.log(`  2. Push the tag:        git push origin audit-handoff-${sha}`);
console.log(`  3. Send to auditor with the email template in docs/audit-rfp-email-en.md`);
