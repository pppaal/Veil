import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repoRoot = process.cwd();
const artifactsDir = resolve(repoRoot, 'artifacts');

const result = {
  generatedAt: new Date().toISOString(),
  purpose: 'Template for recording external security review findings and remediation state.',
  findingStatusLegend: ['open', 'in_progress', 'fixed', 'accepted_risk', 'closed'],
  severityLegend: ['critical', 'high', 'medium', 'low', 'informational'],
  findings: [],
};

mkdirSync(artifactsDir, { recursive: true });
writeFileSync(
  resolve(artifactsDir, 'external-review-findings-template.json'),
  `${JSON.stringify(result, null, 2)}\n`,
  'utf8',
);

console.log(`Wrote ${resolve(artifactsDir, 'external-review-findings-template.json')}`);
