import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repoRoot = process.cwd();
const outputDir = resolve(repoRoot, 'artifacts');
const outputPath = resolve(outputDir, 'private-beta-performance-template.json');

const template = {
  generatedAt: new Date().toISOString(),
  scenarios: [
    'conversation-list-large-cache',
    'long-history-pagination',
    'search-result-jump-repeat',
    'attachment-queue-pressure',
    'adaptive-layout-desktop-tablet',
  ],
  targetDevices: [
    'android-mid-range',
    'android-flagship',
    'iphone-recent',
    'desktop-or-tablet-layout',
  ],
  metrics: [
    'cold_start_to_interactive_ms',
    'conversation_search_latency_ms',
    'archive_search_latency_ms',
    'history_append_latency_ms',
    'scroll_frame_time_p95_ms',
    'attachment_retry_completion_ms',
  ],
  notes: '',
  results: [],
};

mkdirSync(outputDir, { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(template, null, 2)}\n`, 'utf8');
console.log(`Wrote ${outputPath}`);
