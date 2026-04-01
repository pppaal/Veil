import { readFileSync } from 'node:fs';

const failures = [];

const assertNoMatch = (file, pattern, message) => {
  const source = readFileSync(file, 'utf8');
  if (pattern.test(source)) {
    failures.push(`${message}: ${file}`);
  }
};

const assertMatch = (file, pattern, message) => {
  const source = readFileSync(file, 'utf8');
  if (!pattern.test(source)) {
    failures.push(`${message}: ${file}`);
  }
};

assertNoMatch(
  'apps/api/src/modules/push/push.service.ts',
  /\b(body|ciphertext|nonce)\b/,
  'Push payload must remain metadata-only',
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
  'apps/api/src/common/logger/app-logger.service.ts',
  /redactSensitiveFields/,
  'Logger must route metadata through redaction',
);

assertMatch(
  'apps/api/src/modules/attachments/attachments.service.ts',
  /headObject\(/,
  'Attachment completion must verify object storage state',
);

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(failure);
  }
  process.exit(1);
}

console.log('Policy checks passed.');
