import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repoRoot = process.cwd();
const args = process.argv.slice(2);

const readArg = (flag) => {
  const index = args.findIndex((value) => value === flag);
  return index >= 0 ? args[index + 1] : undefined;
};

const requestedEnvFile = readArg('--env-file');
const requestedProvider = readArg('--provider');

const candidateFiles = [
  requestedEnvFile,
  resolve(repoRoot, 'apps/api/.env'),
  resolve(repoRoot, '.env'),
].filter(Boolean);

const env = { ...process.env };
let loadedEnvFile = null;

for (const candidate of candidateFiles) {
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

const isTruthy = (value) => /^true$/i.test(value ?? 'false');
const isFilled = (key) => Boolean(env[key]?.trim());

const currentProvider = env.VEIL_PUSH_PROVIDER ?? 'none';
const deliveryEnabled = isTruthy(env.VEIL_PUSH_ENABLE_DELIVERY);

const providers = {
  apns: {
    requiredKeys: [
      'VEIL_APNS_BUNDLE_ID',
      'VEIL_APNS_TEAM_ID',
      'VEIL_APNS_KEY_ID',
      'VEIL_APNS_PRIVATE_KEY_PEM',
    ],
  },
  fcm: {
    requiredKeys: [
      'VEIL_FCM_PROJECT_ID',
      'VEIL_FCM_SERVICE_ACCOUNT_JSON',
    ],
  },
};

const buildProviderResult = (provider) => {
  const requiredKeys = providers[provider].requiredKeys;
  const missing = requiredKeys.filter((key) => !isFilled(key));
  return {
    provider,
    credentialsPresent: missing.length === 0,
    missing,
    selectedInEnv: currentProvider === provider,
    deliveryEnabledForEnv: currentProvider === provider && deliveryEnabled,
  };
};

const apns = buildProviderResult('apns');
const fcm = buildProviderResult('fcm');

const failures = [];
if (requestedProvider && !['apns', 'fcm'].includes(requestedProvider)) {
  failures.push(`Unsupported provider '${requestedProvider}'. Use 'apns' or 'fcm'.`);
}

if (requestedProvider === 'apns' && !apns.credentialsPresent) {
  failures.push(
    `APNs provider is not ready. Missing: ${apns.missing.join(', ')}`,
  );
}

if (requestedProvider === 'fcm' && !fcm.credentialsPresent) {
  failures.push(
    `FCM provider is not ready. Missing: ${fcm.missing.join(', ')}`,
  );
}

const result = {
  generatedAt: new Date().toISOString(),
  loadedEnvFile,
  requestedProvider: requestedProvider ?? null,
  envSummary: {
    pushProvider: currentProvider,
    pushDeliveryEnabled: deliveryEnabled,
  },
  readiness: {
    apns,
    fcm,
  },
  ok: failures.length === 0,
  failures,
};

const artifactsDir = resolve(repoRoot, 'artifacts');
mkdirSync(artifactsDir, { recursive: true });
writeFileSync(
  resolve(artifactsDir, 'push-provider-readiness.json'),
  `${JSON.stringify(result, null, 2)}\n`,
  'utf8',
);

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(failure);
  }
  process.exit(1);
}

console.log('Push provider readiness check completed.');
