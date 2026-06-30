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
    'pnpm demo:up && curl -fsS http://127.0.0.1:3000/demo/index.html >/dev/null',
    'manual device QA from docs/internal-alpha-test-checklist.md',
  ],
  referenceDocs: [
    'docs/private-beta-release-process.md',
    'docs/private-beta-readiness-report.md',
    'docs/external-security-review-packet.md',
    'docs/private-beta-performance-profile.md',
  ],
  explicitCaveats: [
    'Production crypto adapter (X25519 + AES-256-GCM + Double Ratchet, lib-x25519-aes256gcm-v3) is wired by default; external audit attestation is still required before VEIL_AUDITED_CRYPTO_ATTESTED=true is set.',
    'Push providers remain metadata-only seams; APNs/FCM credentials and a privacy review are required before VEIL_PUSH_ENABLE_DELIVERY can be flipped on.',
    'Production boot remains blocked until VEIL_AUDITED_CRYPTO_ATTESTED=true is set, which is gated on completing the external crypto audit.',
  ],
};

mkdirSync(outputDir, { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`, 'utf8');
console.log(`Wrote ${outputPath}`);
