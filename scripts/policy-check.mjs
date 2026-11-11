import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const API_SRC = 'apps/api/src';
const PRISMA_SCHEMA = 'apps/api/prisma/schema.prisma';
const CONTRACTS_SRC = 'packages/contracts/src';
const MOBILE_BACKUP_DIR = 'apps/mobile/lib/src/core/backup';
const APP_MODULE = 'apps/api/src/app.module.ts';
const ENV_SCHEMA = 'apps/api/src/common/config/env.schema.ts';
const LOGGING_INTERCEPTOR = 'apps/api/src/common/interceptors/logging.interceptor.ts';
const EXCEPTION_FILTER = 'apps/api/src/common/filters/api-exception.filter.ts';
const CADDYFILE = 'infra/caddy/Caddyfile';

// Rule ids prefix every failure so the self-test can tell that a seeded
// violation was caught by the rule it targets, not by accident.
const RULES = {
  noRecoveryRoutes: 'no-recovery-routes',
  noRecoveryModules: 'no-recovery-modules',
  noRecoveryModels: 'no-recovery-models',
  noRecoveryContracts: 'no-recovery-contracts',
  noMobileBackup: 'no-mobile-backup',
  noPasswordReset: 'no-password-reset',
  strictEnvBooleans: 'strict-env-booleans',
  noRawUrlLogging: 'no-raw-url-logging',
  authBeforeThrottle: 'auth-before-throttle',
  caddyStripsClientIp: 'caddy-strips-client-ip',
};

// The body of every reverse_proxy directive (empty when it has no block).
// Brace-balanced, because placeholders such as {remote_host} nest inside it.
const reverseProxyBlocks = (caddyfile) =>
  [...caddyfile.matchAll(/^[ \t]*reverse_proxy\b[^\n{]*(\{)?/gm)].map((match) => {
    if (!match[1]) {
      return '';
    }
    const start = match.index + match[0].length;
    let depth = 1;
    let end = start;
    while (end < caddyfile.length && depth > 0) {
      if (caddyfile[end] === '{') depth += 1;
      if (caddyfile[end] === '}') depth -= 1;
      end += 1;
    }
    return caddyfile.slice(start, end - 1);
  });

export function runPolicyChecks(rootDir) {
  const failures = [];
  const display = (file) => relative(rootDir, file).split(sep).join('/');

  // A missing target is a failure, never a silent pass: renaming a file must
  // not switch its rule off.
  const collectFiles = (target) => {
    const absolute = join(rootDir, target);
    if (!existsSync(absolute)) {
      failures.push(`Policy target is missing: ${target}`);
      return [];
    }
    const walk = (path) =>
      statSync(path).isFile()
        ? [path]
        : readdirSync(path, { withFileTypes: true }).flatMap((entry) =>
            walk(join(path, entry.name)),
          );
    return walk(absolute);
  };

  const readTarget = (target) => {
    const [file] = collectFiles(target);
    return file ? readFileSync(file, 'utf8') : null;
  };

  const assertNoMatch = (target, pattern, message) => {
    for (const file of collectFiles(target)) {
      const source = readFileSync(file, 'utf8');
      if (pattern.test(source)) {
        failures.push(`${message}: ${display(file)}`);
      }
    }
  };

  const assertMatch = (target, pattern, message) => {
    const matched = collectFiles(target).some((file) => pattern.test(readFileSync(file, 'utf8')));
    if (!matched) {
      failures.push(`${message}: ${target}`);
    }
  };

  const directoriesUnder = (target) => {
    const absolute = join(rootDir, target);
    if (!existsSync(absolute)) {
      return [];
    }
    return readdirSync(absolute, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .flatMap((entry) => {
        const child = join(target, entry.name);
        return [child, ...directoriesUnder(child)];
      });
  };

  assertNoMatch(
    'apps/api/src/modules/push',
    /\b(messageBody|plaintext|bodyText|body_text|message_text|ciphertext|nonce)\b/i,
    'Push payloads must not reference plaintext or envelope fields',
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
    APP_MODULE,
    /admin.*message|message.*viewer/i,
    'Backend must not add admin message viewers',
  );

  assertMatch('apps/api/src/main.ts', /helmet\(/, 'API bootstrap must enable security headers');

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
    LOGGING_INTERCEPTOR,
    /\b(body|ciphertext|nonce|transferToken|signature)\b/,
    'API request logging must not reference sensitive payload fields',
  );

  // No backup, no recovery: neither a route nor a module may offer one,
  // anywhere in the API (not just the auth controller).
  assertNoMatch(
    API_SRC,
    /@(?:Controller|Get|Post|Put|Patch|Delete)\(\s*[^)]*(?:recovery|backup)/i,
    `[${RULES.noRecoveryRoutes}] API routes must not offer recovery or backup`,
  );

  for (const directory of directoriesUnder(API_SRC)) {
    if (/(^|\/)modules\/(recovery|backup)$/.test(directory)) {
      failures.push(
        `[${RULES.noRecoveryModules}] API must not contain a recovery or backup module: ${directory}`,
      );
    }
  }

  // Nor may the schema keep a place to store one, the contracts describe
  // one, or the mobile app grow the code that would seal one.
  assertNoMatch(
    PRISMA_SCHEMA,
    /^\s*model\s+\w*(?:Recovery|Backup)\w*\s*\{|@@map\(\s*"[^"]*(?:recovery|backup)[^"]*"\s*\)/im,
    `[${RULES.noRecoveryModels}] The schema must not hold recovery or backup models`,
  );

  // Any declared name counts, type or value and in any case, so a runtime
  // constant such as RECOVERY_FORMAT cannot stand in for a removed type.
  assertNoMatch(
    CONTRACTS_SRC,
    /\b(?:interface|type|class|enum|const|let|var|function)\s+\w*(?:recovery|backup)\w*/i,
    `[${RULES.noRecoveryContracts}] Contracts must not describe recovery or backup payloads`,
  );

  if (existsSync(join(rootDir, MOBILE_BACKUP_DIR))) {
    failures.push(
      `[${RULES.noMobileBackup}] Mobile must not contain a backup module: ${MOBILE_BACKUP_DIR}`,
    );
  }

  assertNoMatch(
    API_SRC,
    /password\s*reset/i,
    `[${RULES.noPasswordReset}] API must not contain a password reset flow`,
  );

  // Boolean coercion turns the string 'false' into true, which once opened
  // the production crypto-audit gate.
  assertNoMatch(
    ENV_SCHEMA,
    /z\.coerce\.boolean\(/,
    `[${RULES.strictEnvBooleans}] Environment booleans must use envBoolean, not boolean coercion`,
  );

  for (const target of [LOGGING_INTERCEPTOR, EXCEPTION_FILTER]) {
    assertNoMatch(
      target,
      /\b(?:request|req)\.url\b/,
      `[${RULES.noRawUrlLogging}] Request telemetry must log the route template, never the raw URL`,
    );
  }

  const appModule = readTarget(APP_MODULE);
  if (appModule !== null) {
    const appGuards = [...appModule.matchAll(/\{[^{}]*\bAPP_GUARD\b[^{}]*\}/g)].map(
      ([provider]) => /useClass:\s*(\w+)/.exec(provider)?.[1],
    );
    const auth = appGuards.indexOf('JwtAuthGuard');
    const throttle = appGuards.indexOf('CfThrottlerGuard');
    if (auth === -1 || throttle === -1 || auth > throttle) {
      failures.push(
        `[${RULES.authBeforeThrottle}] JwtAuthGuard's APP_GUARD must be registered before CfThrottlerGuard's: ${APP_MODULE}`,
      );
    }
  }

  // Caddy must overwrite client-supplied forwarding headers on every proxied
  // request and keep client addresses out of its access log.
  const caddyfile = readTarget(CADDYFILE);
  if (caddyfile !== null) {
    const proxies = reverseProxyBlocks(caddyfile);
    const unstripped = proxies.filter((block) => !/header_up\s+-CF-Connecting-IP\b/.test(block));
    if (proxies.length === 0 || unstripped.length > 0) {
      failures.push(
        `[${RULES.caddyStripsClientIp}] Every reverse_proxy must strip CF-Connecting-IP (header_up -CF-Connecting-IP): ${CADDYFILE}`,
      );
    }
    if (!/request>remote_ip\s+delete/.test(caddyfile)) {
      failures.push(
        `[${RULES.caddyStripsClientIp}] Caddy access log must delete request>remote_ip: ${CADDYFILE}`,
      );
    }
  }

  return failures;
}

// A tree that satisfies every rule. Each seeded violation below changes one
// file of it.
export const CLEAN_FIXTURE = {
  'apps/api/src/modules/push/push.service.ts':
    'export const PUSH_PROVIDER = Symbol("PUSH_PROVIDER");\n',
  'apps/api/src/modules/realtime/realtime.gateway.ts':
    'export const cors = { origin: allowedOrigins };\n',
  'apps/api/src/modules/auth/auth.controller.ts':
    "@Controller('auth')\nexport class AuthController {}\n",
  [APP_MODULE]: [
    'providers: [',
    '  { provide: APP_GUARD, useClass: JwtAuthGuard },',
    '  { provide: APP_GUARD, useClass: CfThrottlerGuard },',
    ']',
    '',
  ].join('\n'),
  'apps/api/src/main.ts':
    'app.use(helmet());\napp.useGlobalFilters(new ApiExceptionFilter(logger));\n',
  'apps/api/src/common/logger/app-logger.service.ts': 'redactSensitiveFields(meta);\n',
  'apps/api/src/modules/device-transfer/device-transfer.service.ts':
    "const proof = 'transfer-complete:';\n",
  'apps/api/src/modules/attachments/attachments.service.ts': 'await storage.headObject(key);\n',
  'apps/mobile/lib/main.dart': 'void main() {}\n',
  [PRISMA_SCHEMA]: 'model User {\n  id String @id\n\n  @@map("users")\n}\n',
  [`${CONTRACTS_SRC}/index.ts`]: 'export interface RegisterRequest {\n  handle: string;\n}\n',
  'apps/mobile/pubspec.yaml': 'name: veil\n',
  [LOGGING_INTERCEPTOR]: "logger.info('request.completed', { route: routeTemplate(request) });\n",
  [EXCEPTION_FILTER]: "logger.warn('request.rejected', { route: routeTemplate(request) });\n",
  [ENV_SCHEMA]: 'VEIL_ENABLE_SWAGGER: envBoolean(false),\n',
  [CADDYFILE]: [
    'site {',
    '\treverse_proxy api:3000 {',
    '\t\theader_up -CF-Connecting-IP',
    '\t\theader_up X-Forwarded-For {remote_host}',
    '\t}',
    '\tlog {',
    '\t\tformat filter {',
    '\t\t\tfields {',
    '\t\t\t\trequest>remote_ip delete',
    '\t\t\t}',
    '\t\t}',
    '\t}',
    '}',
    '',
  ].join('\n'),
};

const SEEDED_VIOLATIONS = [
  {
    rule: RULES.noRecoveryRoutes,
    files: {
      'apps/api/src/modules/vault/vault.controller.ts':
        "@Controller('vault')\nclass V { @Put('backup') put() {} }\n",
    },
  },
  {
    rule: RULES.noRecoveryRoutes,
    files: {
      'apps/api/src/modules/keys/keys.controller.ts':
        "@Controller('recovery/keys')\nexport class K {}\n",
    },
  },
  {
    rule: RULES.noRecoveryModules,
    files: { 'apps/api/src/modules/recovery/recovery.module.ts': 'export class SealedModule {}\n' },
  },
  {
    rule: RULES.noRecoveryModules,
    files: { 'apps/api/src/modules/backup/index.ts': 'export {};\n' },
  },
  {
    rule: RULES.noRecoveryModels,
    files: {
      [PRISMA_SCHEMA]: `${CLEAN_FIXTURE[PRISMA_SCHEMA]}model RecoveryBlob {\n  userId String @id\n}\n`,
    },
  },
  {
    rule: RULES.noRecoveryModels,
    files: {
      [PRISMA_SCHEMA]: `${CLEAN_FIXTURE[PRISMA_SCHEMA]}model Vault {\n  id String @id\n\n  @@map("key_backups")\n}\n`,
    },
  },
  {
    rule: RULES.noRecoveryContracts,
    files: {
      [`${CONTRACTS_SRC}/index.ts`]:
        'export interface UpsertRecoveryBackupRequest {\n  ciphertext: string;\n}\n',
    },
  },
  {
    rule: RULES.noRecoveryContracts,
    files: {
      [`${CONTRACTS_SRC}/vault.ts`]: "export const RECOVERY_FORMAT = 'sealed-v1';\n",
    },
  },
  {
    rule: RULES.noMobileBackup,
    files: { [`${MOBILE_BACKUP_DIR}/backup_envelope.dart`]: 'class BackupEnvelope {}\n' },
  },
  {
    rule: RULES.noPasswordReset,
    files: { 'apps/api/src/modules/account/account.service.ts': 'async startPasswordReset() {}\n' },
  },
  {
    rule: RULES.strictEnvBooleans,
    files: { [ENV_SCHEMA]: 'VEIL_AUDITED_CRYPTO_ATTESTED: z.coerce.boolean().default(false),\n' },
  },
  {
    rule: RULES.noRawUrlLogging,
    files: { [LOGGING_INTERCEPTOR]: "logger.info('request.completed', { path: request.url });\n" },
  },
  {
    rule: RULES.noRawUrlLogging,
    files: { [EXCEPTION_FILTER]: "logger.warn('request.rejected', { path: req.url });\n" },
  },
  {
    rule: RULES.authBeforeThrottle,
    files: {
      [APP_MODULE]: [
        'providers: [',
        '  { provide: APP_GUARD, useClass: CfThrottlerGuard },',
        '  { provide: APP_GUARD, useClass: JwtAuthGuard },',
        ']',
        '',
      ].join('\n'),
    },
  },
  {
    rule: RULES.caddyStripsClientIp,
    files: {
      [CADDYFILE]: CLEAN_FIXTURE[CADDYFILE].replace('\t\theader_up -CF-Connecting-IP\n', ''),
    },
  },
  {
    rule: RULES.caddyStripsClientIp,
    files: {
      [CADDYFILE]: `${CLEAN_FIXTURE[CADDYFILE]}s3 {\n\treverse_proxy minio:9000\n}\n`,
    },
  },
  {
    rule: RULES.caddyStripsClientIp,
    files: {
      [CADDYFILE]: CLEAN_FIXTURE[CADDYFILE].replace(
        'request>remote_ip delete',
        'request>headers delete',
      ),
    },
  },
];

export const writeTree = (rootDir, files) => {
  for (const [path, contents] of Object.entries(files)) {
    const absolute = join(rootDir, path);
    mkdirSync(dirname(absolute), { recursive: true });
    writeFileSync(absolute, contents);
  }
};

// Proves the gate can still fail: every seeded violation must be reported by
// the rule it targets, and the clean tree must pass.
export function runSelfTest() {
  const problems = [];
  const scratch = mkdtempSync(join(tmpdir(), 'veil-policy-self-test-'));
  try {
    const cleanRoot = join(scratch, 'clean');
    writeTree(cleanRoot, CLEAN_FIXTURE);
    const cleanFailures = runPolicyChecks(cleanRoot);
    if (cleanFailures.length > 0) {
      problems.push(`clean fixture failed: ${cleanFailures.join('; ')}`);
    }

    SEEDED_VIOLATIONS.forEach((violation, index) => {
      const root = join(scratch, `violation-${index}`);
      writeTree(root, { ...CLEAN_FIXTURE, ...violation.files });
      const failures = runPolicyChecks(root);
      if (!failures.some((failure) => failure.startsWith(`[${violation.rule}]`))) {
        problems.push(
          `seeded ${violation.rule} violation (${Object.keys(violation.files).join(', ')}) passed`,
        );
      }
    });
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
  return problems;
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  const selfTestProblems = runSelfTest();
  if (selfTestProblems.length > 0) {
    console.error('Policy check self-test failed:');
    for (const problem of selfTestProblems) {
      console.error(`  ${problem}`);
    }
    process.exit(1);
  }

  const repoRoot = fileURLToPath(new URL('..', import.meta.url));
  const failures = runPolicyChecks(repoRoot);
  if (failures.length > 0) {
    for (const failure of failures) {
      console.error(failure);
    }
    process.exit(1);
  }

  console.log(`Policy self-test passed (${SEEDED_VIOLATIONS.length} seeded violations caught).`);
  console.log('Policy checks passed.');
}
