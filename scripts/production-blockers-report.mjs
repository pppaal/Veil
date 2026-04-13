import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repoRoot = process.cwd();
const artifactsDir = resolve(repoRoot, 'artifacts');

const readJson = (filename) => {
  const path = resolve(artifactsDir, filename);
  if (!existsSync(path)) {
    return null;
  }
  return JSON.parse(readFileSync(path, 'utf8'));
};

const externalStatus = readJson('external-execution-status.json');
const releaseEvidence = readJson('private-beta-release-evidence.json');
const perfTemplate = readJson('private-beta-performance-template.json');
const reviewManifest = readJson('external-security-review-manifest.json');
const pushReadiness = readJson('push-provider-readiness.json');

const tracks = externalStatus?.tracks ?? {};
const blocked = Object.entries(tracks)
  .filter(([, value]) => value.status === 'blocked' || value.status === 'pending')
  .map(([key, value]) => ({
    key,
    status: value.status,
    reason: value.reason,
    docs: value.docs,
  }));

const result = {
  generatedAt: new Date().toISOString(),
  summary: {
    productionReady: false,
    blockedCount: blocked.length,
    releaseEvidencePresent: releaseEvidence != null,
    performanceTemplatePresent: perfTemplate != null,
    reviewManifestPresent: reviewManifest != null,
    pushReadinessPresent: pushReadiness != null,
  },
  blocked,
  nextActions: [
    'Select and approve the audited crypto library and mobile bridge.',
    'Design and validate Flutter native bridge for the chosen crypto library.',
    'Inject APNs and/or FCM credentials, then complete push privacy review.',
    'Run one-day real-device profiling on Android mid-range, flagship, and iPhone.',
    'Hand off the external review packet and begin remediation tracking.',
    'Implement audited crypto adapter behind the existing boundary.',
    'Complete crypto session state migration design and testing.',
  ],
};

mkdirSync(artifactsDir, { recursive: true });
writeFileSync(
  resolve(artifactsDir, 'production-blockers-report.json'),
  `${JSON.stringify(result, null, 2)}\n`,
  'utf8',
);

console.log(`Wrote ${resolve(artifactsDir, 'production-blockers-report.json')}`);
