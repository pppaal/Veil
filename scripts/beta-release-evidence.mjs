import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repoRoot = process.cwd();
const outputDir = resolve(repoRoot, 'artifacts');
const outputPath = resolve(outputDir, 'private-beta-release-evidence.json');

const runGit = (args) =>
  execFileSync('git', args, {
    cwd: repoRoot,
    encoding: 'utf8',
  }).trim();

const dirty = runGit(['status', '--porcelain'])
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter(Boolean);

const evidence = {
  generatedAt: new Date().toISOString(),
  commitSha: runGit(['rev-parse', 'HEAD']),
  branch: runGit(['rev-parse', '--abbrev-ref', 'HEAD']),
  workingTreeClean: dirty.length === 0,
  workingTreeChanges: dirty,
  mobileReleaseIdentity: {
    androidApplicationId: 'io.veil.mobile',
    iosBundleIdentifier: 'io.veil.mobile',
  },
  pushProviderKinds: ['none', 'apns', 'fcm'],
  requiredVerification: [
    'pnpm beta:release:check',
    'pnpm beta:release:evidence',
    'manual device QA from docs/internal-alpha-test-checklist.md',
  ],
  referenceDocs: [
    'docs/private-beta-release-process.md',
    'docs/private-beta-readiness-report.md',
    'docs/external-security-review-packet.md',
    'docs/private-beta-performance-profile.md',
  ],
  explicitCaveats: [
    'Mock crypto remains active and is not production-safe.',
    'Push providers remain metadata-only seams until separate privacy review is complete.',
    'Production boot must remain blocked until audited crypto replaces the mock boundary.',
  ],
};

mkdirSync(outputDir, { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`, 'utf8');
console.log(`Wrote ${outputPath}`);
