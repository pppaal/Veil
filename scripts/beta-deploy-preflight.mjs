import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repoRoot = process.cwd();
const args = process.argv.slice(2);

const envFileArgIndex = args.findIndex((value) => value === '--env-file');
const requestedEnvFile =
  envFileArgIndex >= 0 ? args[envFileArgIndex + 1] : undefined;

const candidateFiles = [
  requestedEnvFile,
  resolve(repoRoot, 'apps/api/.env'),
  resolve(repoRoot, '.env'),
].filter(Boolean);

const env = { ...process.env };
let loadedEnvFile = null;

for (const candidate of candidateFiles) {
  if (!candidate) {
    continue;
  }
  const resolved = resolve(repoRoot, candidate);
  if (!existsSync(resolved)) {
    continue;
  }
  loadedEnvFile = resolved;
  const source = readFileSync(resolved, 'utf8');
  for (const line of source.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }
    const separatorIndex = trimmed.indexOf('=');
    if (separatorIndex < 0) {
      continue;
    }
    const key = trimmed.slice(0, separatorIndex).trim();
    const value = trimmed.slice(separatorIndex + 1).trim();
    if (!(key in env)) {
      env[key] = value;
    }
  }
  break;
}

const failures = [];
const warnings = [];

const requireNonEmpty = (key, description) => {
  if (!env[key]?.trim()) {
    failures.push(`${key}: ${description}`);
  }
};

requireNonEmpty('VEIL_ENV', 'Environment mode must be set.');
requireNonEmpty('VEIL_DATABASE_URL', 'Database URL is required.');
requireNonEmpty('VEIL_JWT_SECRET', 'JWT secret is required.');
requireNonEmpty('VEIL_S3_ENDPOINT', 'Object storage endpoint is required.');
requireNonEmpty('VEIL_S3_BUCKET', 'Object storage bucket is required.');
requireNonEmpty('VEIL_ALLOWED_ORIGINS', 'Allowed origins must be configured.');

if (env.VEIL_ENV === 'production') {
  failures.push('VEIL_ENV: Production boot must remain blocked until audited crypto is integrated.');
}

if (
  env.VEIL_JWT_SECRET &&
  /replace-me|replace-this-for-alpha|test-secret/i.test(env.VEIL_JWT_SECRET)
) {
  failures.push('VEIL_JWT_SECRET: Placeholder JWT secret must not be used for deployable private beta.');
}

const pushProvider = env.VEIL_PUSH_PROVIDER ?? 'none';
const pushDeliveryEnabled = /^true$/i.test(env.VEIL_PUSH_ENABLE_DELIVERY ?? 'false');

if (pushDeliveryEnabled && pushProvider === 'none') {
  failures.push('VEIL_PUSH_ENABLE_DELIVERY: Cannot enable delivery while VEIL_PUSH_PROVIDER=none.');
}

if (pushProvider === 'apns') {
  requireNonEmpty('VEIL_APNS_BUNDLE_ID', 'APNs bundle id is required when APNs is selected.');
  requireNonEmpty('VEIL_APNS_TEAM_ID', 'APNs team id is required when APNs is selected.');
  requireNonEmpty('VEIL_APNS_KEY_ID', 'APNs key id is required when APNs is selected.');
  requireNonEmpty('VEIL_APNS_PRIVATE_KEY_PEM', 'APNs private key is required when APNs is selected.');
}

if (pushProvider === 'fcm') {
  requireNonEmpty('VEIL_FCM_PROJECT_ID', 'FCM project id is required when FCM is selected.');
  requireNonEmpty('VEIL_FCM_SERVICE_ACCOUNT_JSON', 'FCM service account JSON is required when FCM is selected.');
}

if (!pushDeliveryEnabled) {
  warnings.push('Push delivery is disabled. Runtime will remain metadata-only but no provider delivery will occur.');
}

const result = {
  generatedAt: new Date().toISOString(),
  loadedEnvFile,
  ok: failures.length === 0,
  failures,
  warnings,
  summary: {
    env: env.VEIL_ENV ?? null,
    pushProvider,
    pushDeliveryEnabled,
    allowedOriginsConfigured: Boolean(env.VEIL_ALLOWED_ORIGINS?.trim()),
    s3PublicEndpointConfigured: Boolean(env.VEIL_S3_PUBLIC_ENDPOINT?.trim()),
  },
};

const artifactsDir = resolve(repoRoot, 'artifacts');
mkdirSync(artifactsDir, { recursive: true });
writeFileSync(
  resolve(artifactsDir, 'private-beta-deploy-preflight.json'),
  `${JSON.stringify(result, null, 2)}\n`,
  'utf8',
);

if (!result.ok) {
  for (const failure of failures) {
    console.error(failure);
  }
  process.exit(1);
}

for (const warning of warnings) {
  console.warn(warning);
}
console.log('Private beta deploy preflight passed.');
