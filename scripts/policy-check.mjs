import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const failures = [];

const collectFiles = (target) => {
  const stats = statSync(target);
  if (stats.isFile()) {
    return [target];
  }

  return readdirSync(target, { withFileTypes: true }).flatMap((entry) => {
    const next = join(target, entry.name);
    if (entry.isDirectory()) {
      return collectFiles(next);
    }
    return [next];
  });
};

const assertNoMatch = (target, pattern, message) => {
  for (const file of collectFiles(target)) {
    const source = readFileSync(file, 'utf8');
    if (pattern.test(source)) {
      failures.push(`${message}: ${file}`);
    }
  }
};

const assertMatch = (target, pattern, message) => {
  let matched = false;
  for (const file of collectFiles(target)) {
    const source = readFileSync(file, 'utf8');
    if (pattern.test(source)) {
      matched = true;
      break;
    }
  }
  if (!matched) {
    failures.push(`${message}: ${target}`);
  }
};

assertNoMatch(
  'apps/api/src/modules/push/push.service.ts',
  /\b(body|ciphertext|nonce)\b/,
  'Push payload must remain metadata-only',
);

assertMatch(
  'apps/api/src/modules/push/push.service.ts',
  /PUSH_PROVIDER|PushProvider/,
  'Push service must remain behind a provider seam',
);

assertNoMatch(
  'apps/api/src/modules/realtime/realtime.gateway.ts',
  /origin:\s*['"`]\*['"`]/,
  'Realtime gateway must not allow wildcard CORS origins',
);

assertNoMatch(
  'apps/api/src/modules/auth/auth.controller.ts',
  /password\s*reset|recovery/i,
  'Auth module must not contain recovery or reset flows',
);

assertNoMatch(
  'apps/api/src/app.module.ts',
  /admin.*message|message.*viewer/i,
  'Backend must not add admin message viewers',
);

assertMatch(
  'apps/api/src/main.ts',
  /helmet\(/,
  'API bootstrap must enable security headers',
);

assertMatch(
  'apps/api/src/main.ts',
  /ApiExceptionFilter/,
  'API bootstrap must register the structured API exception filter',
);

assertMatch(
  'apps/api/src/common/logger/app-logger.service.ts',
  /redactSensitiveFields/,
  'Logger must route metadata through redaction',
);

assertMatch(
  'apps/api/src/modules/device-transfer/device-transfer.service.ts',
  /transfer-complete:/,
  'Device transfer completion must require a new-device possession proof',
);

assertMatch(
  'apps/api/src/modules/attachments/attachments.service.ts',
  /headObject\(/,
  'Attachment completion must verify object storage state',
);

assertNoMatch(
  'apps/mobile/lib',
  /\b(print|debugPrint)\s*\(/,
  'Mobile runtime must not emit ad-hoc console logging',
);

assertNoMatch(
  'apps/mobile/pubspec.yaml',
  /firebase_crashlytics|sentry_flutter/i,
  'Crash reporting SDKs must not be added without privacy review',
);

assertNoMatch(
  'apps/api/src/common/interceptors/logging.interceptor.ts',
  /\b(body|ciphertext|nonce|transferToken|signature)\b/,
  'API request logging must not reference sensitive payload fields',
);

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(failure);
  }
  process.exit(1);
}

console.log('Policy checks passed.');
