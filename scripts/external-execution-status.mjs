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

const releaseEvidence = readJson('private-beta-release-evidence.json');
const perfTemplate = readJson('private-beta-performance-template.json');
const reviewManifest = readJson('external-security-review-manifest.json');
const pushReadiness = readJson('push-provider-readiness.json');
const reviewFindingsTemplate = readJson('external-review-findings-template.json');
const productionBlockers = readJson('production-blockers-report.json');

const hasPerfResults =
  Array.isArray(perfTemplate?.results) && perfTemplate.results.length > 0;
const hasReviewManifest = reviewManifest != null;
const hasReleaseEvidence = releaseEvidence != null;
const hasReviewFindingsTemplate = reviewFindingsTemplate != null;
const pushReady =
  pushReadiness != null &&
  pushReadiness.readiness?.apns?.credentialsPresent === true &&
  pushReadiness.readiness?.fcm?.credentialsPresent === true;

const tracks = {
  auditedCrypto: {
    status: 'pending',
    reason:
      'Repo boundary is prepared, but an audited adapter and mobile bridge are not integrated.',
    docs: [
      'docs/audited-crypto-library-decision.md',
      'docs/audited-crypto-adapter-execution.md',
    ],
  },
  pushPrivacyReview: {
    status: pushReady ? 'ready_for_review' : 'blocked',
    reason: pushReady
      ? 'Credential material appears present; privacy review can proceed.'
      : 'APNs/FCM credential material is still missing or incomplete.',
    docs: ['docs/push-privacy-review-checklist.md'],
  },
  realDevicePerformance: {
    status: hasPerfResults ? 'in_progress_or_complete' : 'blocked',
    reason: hasPerfResults
      ? 'Performance template contains recorded results.'
      : 'Performance template exists, but no real-device results are recorded yet.',
    docs: [
      'docs/real-device-performance-execution.md',
      'docs/real-device-performance-results-template.md',
    ],
  },
  externalSecurityReview: {
    status:
      hasReviewManifest && hasReleaseEvidence && hasReviewFindingsTemplate
        ? 'ready_for_handoff'
        : 'blocked',
    reason:
      hasReviewManifest && hasReleaseEvidence && hasReviewFindingsTemplate
        ? 'Review manifest, release evidence, and remediation template exist; handoff is structurally ready.'
        : 'Required review artifacts are missing.',
    docs: [
      'docs/external-security-review-packet.md',
      'docs/external-review-remediation-tracker.md',
    ],
  },
};

const blockedTracks = Object.entries(tracks)
  .filter(([, value]) => value.status === 'blocked' || value.status === 'pending')
  .map(([key]) => key);

const result = {
  generatedAt: new Date().toISOString(),
  summary: {
    releaseEvidencePresent: hasReleaseEvidence,
    perfTemplatePresent: perfTemplate != null,
    perfResultsRecorded: hasPerfResults,
    reviewManifestPresent: hasReviewManifest,
    reviewFindingsTemplatePresent: hasReviewFindingsTemplate,
    pushReadinessArtifactPresent: pushReadiness != null,
    productionBlockersPresent: productionBlockers != null,
    productionReady: false,
    blockedTracks,
  },
  tracks,
};

mkdirSync(artifactsDir, { recursive: true });
writeFileSync(
  resolve(artifactsDir, 'external-execution-status.json'),
  `${JSON.stringify(result, null, 2)}\n`,
  'utf8',
);

console.log(`Wrote ${resolve(artifactsDir, 'external-execution-status.json')}`);
