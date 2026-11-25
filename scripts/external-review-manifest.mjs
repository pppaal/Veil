import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

import {
  AUDIT_CODE_PATHS,
  AUDIT_DOCS,
  PROTOCOL_REVIEW_QUESTION,
  assertAuditScope,
} from './audit-scope.mjs';

/** The review manifest for commitSha; the scope comes from scripts/audit-scope.mjs. */
export function buildManifest({ commitSha, generatedAt = new Date().toISOString() }) {
  return {
    generatedAt,
    commitSha,
    docs: [...AUDIT_DOCS],
    codePaths: [...AUDIT_CODE_PATHS],
    requiredArtifacts: [
      'artifacts/private-beta-release-evidence.json',
      'artifacts/private-beta-performance-template.json',
    ],
    explicitCaveats: [
      'Protocol v2 (X3DH + Double Ratchet + AES-256-GCM) is implemented on mobile (lib_crypto_adapter.dart) and web (apps/web-demo/src/crypto) and Sender Keys on mobile; none of it is externally audited yet.',
      'Push providers require separate privacy review before delivery is enabled.',
      'Production boot remains blocked until VEIL_AUDITED_CRYPTO_ATTESTED=true (set only after the external audit closes).',
    ],
    reviewQuestions: [
      'Does the architecture preserve no-recovery and device-bound identity?',
      'Do any logs, push payloads, temp files, or local cache paths expose plaintext?',
      'Is revoke/transfer expiry/stale-device handling strong enough for private beta?',
      PROTOCOL_REVIEW_QUESTION,
      'Is the crypto adapter boundary strict enough for audited replacement?',
    ],
  };
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  const repoRoot = process.cwd();
  assertAuditScope(repoRoot);
  const outputDir = resolve(repoRoot, 'artifacts');
  const outputPath = resolve(outputDir, 'external-security-review-manifest.json');
  const commitSha = execFileSync('git', ['rev-parse', 'HEAD'], {
    cwd: repoRoot,
    encoding: 'utf8',
  }).trim();

  mkdirSync(outputDir, { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(buildManifest({ commitSha }), null, 2)}\n`, 'utf8');
  console.log(`Wrote ${outputPath}`);
}
