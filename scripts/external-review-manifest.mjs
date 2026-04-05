import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repoRoot = process.cwd();
const outputDir = resolve(repoRoot, 'artifacts');
const outputPath = resolve(outputDir, 'external-security-review-manifest.json');

const runGit = (args) =>
  execFileSync('git', args, {
    cwd: repoRoot,
    encoding: 'utf8',
  }).trim();

const manifest = {
  generatedAt: new Date().toISOString(),
  commitSha: runGit(['rev-parse', 'HEAD']),
  docs: [
    'docs/no-recovery.md',
    'docs/trusted-device-graph.md',
    'docs/architecture.md',
    'docs/threat-model.md',
    'docs/message-flow.md',
    'docs/device-transfer-flow.md',
    'docs/attachment-flow.md',
    'docs/mobile-device-security.md',
    'docs/observability-hygiene.md',
    'docs/crypto-adapter-architecture.md',
    'docs/mock-crypto-replacement.md',
    'docs/private-beta-audit.md',
    'docs/private-beta-readiness-report.md',
    'docs/production-deployment.md',
  ],
  requiredArtifacts: [
    'artifacts/private-beta-release-evidence.json',
    'artifacts/private-beta-performance-template.json',
  ],
  explicitCaveats: [
    'Mock crypto remains active.',
    'Push providers require separate privacy review before delivery is enabled.',
    'Production boot remains blocked.',
  ],
  reviewQuestions: [
    'Does the architecture preserve no-recovery and device-bound identity?',
    'Do any logs, push payloads, temp files, or local cache paths expose plaintext?',
    'Is revoke/transfer expiry/stale-device handling strong enough for private beta?',
    'Is the crypto adapter boundary strict enough for audited replacement?',
  ],
};

mkdirSync(outputDir, { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
console.log(`Wrote ${outputPath}`);
