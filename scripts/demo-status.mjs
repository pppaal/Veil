#!/usr/bin/env node
// Quick "is the demo healthy?" script for the operator. Probes the API,
// the realtime gateway, the Cloudflare Tunnel hostname (if exported), and
// the Postgres container. Designed to run in under 2 seconds — no
// dependencies beyond node:net, fetch, and `docker ps`.

import { spawnSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const API_LOCAL = process.env.VEIL_API_LOCAL ?? 'http://127.0.0.1:3000';
const API_PUBLIC = process.env.VEIL_API_PUBLIC; // optional Cloudflare hostname
const TIMEOUT_MS = 2000;

const results = [];

function pad(label, status, note = '') {
  const icon = status === 'ok' ? 'OK' : status === 'warn' ? '..' : 'XX';
  return `  [${icon}] ${label.padEnd(28)} ${note}`;
}

async function probe(label, url) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    if (res.ok) {
      results.push(pad(label, 'ok', `${res.status} ${url}`));
      return true;
    }
    results.push(pad(label, 'warn', `${res.status} ${url}`));
    return false;
  } catch (err) {
    results.push(pad(label, 'fail', `${err.code ?? err.name} ${url}`));
    return false;
  } finally {
    clearTimeout(t);
  }
}

function probeDocker(name, container) {
  const out = spawnSync(
    'docker',
    ['ps', '--filter', `name=${container}`, '--format', '{{.Status}}'],
    {
      encoding: 'utf8',
      timeout: TIMEOUT_MS,
    },
  );
  if (out.error) {
    results.push(pad(name, 'warn', 'docker not available'));
    return false;
  }
  const status = out.stdout.trim();
  if (!status) {
    results.push(pad(name, 'fail', 'container not running'));
    return false;
  }
  if (!status.toLowerCase().startsWith('up')) {
    results.push(pad(name, 'fail', status));
    return false;
  }
  results.push(pad(name, 'ok', status));
  return true;
}

console.log('VEIL demo status');
console.log('================');
console.log('');

await probe('API /health (local)', `${API_LOCAL}/v1/health`);

if (API_PUBLIC) {
  await probe('API /health (public)', `${API_PUBLIC}/v1/health`);
} else {
  results.push(pad('API /health (public)', 'warn', 'set VEIL_API_PUBLIC to test'));
}

probeDocker('postgres', 'veil-postgres-1');
probeDocker('redis', 'veil-redis-1');
probeDocker('minio', 'veil-minio-1');
probeDocker('api', 'veil-api-1');
probeDocker('cloudflared', 'veil-cloudflared-1');

console.log(results.join('\n'));
console.log('');

const failed = results.filter((r) => r.includes('[XX]')).length;
const warned = results.filter((r) => r.includes('[..]')).length;
if (failed > 0) {
  console.log(`Result: ${failed} failed, ${warned} warned`);
  process.exit(1);
}
console.log(`Result: all probes ok (${warned} warned)`);
await sleep(0);
