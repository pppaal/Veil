#!/usr/bin/env node
// Bundles everything an external auditor needs into a single tarball.
// Runs the existing pnpm beta:external:bundle to refresh artifacts,
// then layers in the audit-specific design docs and a README index.
// The documents and code paths come from scripts/audit-scope.mjs, which the
// review manifest reads too; a path missing from the tree stops the bundle.
//
// Output: artifacts/veil-audit-handoff-<sha>.tar.gz
//
// Usage:
//   pnpm audit:handoff
// or  node scripts/audit-handoff-bundle.mjs

import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, copyFileSync, existsSync, rmSync } from 'node:fs';
import { join, basename } from 'node:path';
import { pathToFileURL } from 'node:url';

import { AUDIT_CODE_PATHS, AUDIT_DOCS, assertAuditScope } from './audit-scope.mjs';

const artifacts = [
  'artifacts/private-beta-release-evidence.json',
  'artifacts/external-security-review-manifest.json',
  'artifacts/external-review-findings-template.json',
  'artifacts/production-blockers-report.json',
];

/** The README.md that indexes the bundle for the auditor. */
export function handoffReadme({ sha, branch, generatedAt = new Date().toISOString() }) {
  return `# VEIL audit handoff bundle

Pinned commit: \`${sha}\`
Branch at bundle time: \`${branch}\`
Generated: ${generatedAt}

## What's in this bundle

\`docs/\` — design and spec documents the auditor needs
${AUDIT_DOCS.map((doc) => `- \`${basename(doc)}\``).join('\n')}

Status of the crypto documents:
- \`crypto-envelope-spec.md\` — **normative**. Protocol v2
  (\`veil-envelope-v2\`): X3DH with signed and one-time prekeys that
  authenticates both parties, then a Double Ratchet with AES-256-GCM.
  Implemented on both clients, mobile (\`apps/mobile/lib/src/core/crypto\`)
  and web (\`apps/web-demo/src/crypto\`), and pinned byte for byte by
  \`packages/shared/test-vectors/crypto-kat.json\`, which an independent
  node:crypto implementation (\`scripts/crypto-test-vectors.mjs\`) and both
  clients reproduce.
- \`crypto-surfaces.md\` — where each cryptographic operation happens, on
  both clients and the relay.
- \`group-sender-keys-design.md\` — Sender Keys for groups: implemented on
  mobile, pre-audit. The web client does not take part in groups under
  protocol v2.
- \`envelope-v3-unified-spec.md\` — superseded and never implemented; kept
  as history only.
- \`sealed-sender-design.md\` — under revision; not implemented.

\`artifacts/\` — machine-readable
- \`private-beta-release-evidence.json\` — CI + verification evidence
- \`external-security-review-manifest.json\` — review scope, file inventory
  and review questions
- \`external-review-findings-template.json\` — findings JSON schema
  the auditor should mirror
- \`production-blockers-report.json\` — known blocker list

## Code paths (review the repo at the pinned SHA)

The auditor should clone the repo at \`${sha}\` and review:

${AUDIT_CODE_PATHS.map((path) => `  ${path}`).join('\n')}

\`scripts/policy-check.mjs\` is the single source of truth for the
"VEIL non-negotiables" — what must NOT exist anywhere in the codebase.

## Verification you can re-run locally

After cloning at \`${sha}\`:

\`\`\`
pnpm install
pnpm -C apps/api build                 # type-check
pnpm -C apps/api test                  # API unit tests
pnpm -C apps/api test:e2e              # API e2e tests
pnpm -C apps/web-demo test             # web client, protocol v2 included
(cd apps/mobile && flutter test)       # mobile client, protocol v2 and Sender Keys
node scripts/crypto-test-vectors.mjs --check
node scripts/policy-check.mjs
\`\`\`

All of them should be green at this commit.

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
}

function main() {
  const repoRoot = process.cwd();
  try {
    assertAuditScope(repoRoot);
  } catch (error) {
    console.error(`[audit-handoff] ${error.message}`);
    process.exit(1);
  }

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

  mkdirSync(join(stagingDir, 'docs'), { recursive: true });
  mkdirSync(join(stagingDir, 'artifacts'), { recursive: true });

  // assertAuditScope has checked that every document exists.
  for (const doc of AUDIT_DOCS) {
    copyFileSync(join(repoRoot, doc), join(stagingDir, 'docs', basename(doc)));
  }

  for (const a of artifacts) {
    const src = join(repoRoot, a);
    if (existsSync(src)) {
      copyFileSync(src, join(stagingDir, 'artifacts', basename(a)));
    } else {
      console.warn(`[audit-handoff] missing artifact: ${a}`);
    }
  }

  // Code paths are listed in the README; the auditor reviews them in a clone.
  writeFileSync(join(stagingDir, 'README.md'), handoffReadme({ sha, branch }), 'utf8');

  const tarball = join(repoRoot, 'artifacts', `veil-audit-handoff-${sha}.tar.gz`);
  const tarArgs = ['-czf', tarball, '-C', join(repoRoot, 'artifacts'), `audit-handoff-${sha}`];
  const tar = spawnSync('tar', tarArgs, { stdio: 'inherit' });
  if (tar.status !== 0) {
    console.error('tar failed; staged dir left at', stagingDir);
    process.exit(tar.status ?? 1);
  }

  console.log(`[audit-handoff] wrote ${tarball}`);
  console.log(`[audit-handoff] staged dir: ${stagingDir}`);
  console.log('');
  console.log('Next steps:');
  console.log(
    `  1. Tag this commit:     git tag -a audit-handoff-${sha} -m "Audit handoff ${sha}"`,
  );
  console.log(`  2. Push the tag:        git push origin audit-handoff-${sha}`);
  console.log(`  3. Send to auditor with the email template in docs/audit-rfp-email-en.md`);
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  main();
}
