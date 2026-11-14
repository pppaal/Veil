// Facts the documents state about the code, checked against the code.
//
// The check fails when
// - a document or a top-level script names a LibCryptoAdapter id other than
//   the one lib_crypto_adapter.dart returns, unless that line or the one
//   before it calls the id retired, legacy, pre-v2 or proposed, or ties it to
//   the legacy envelope veil-envelope-v1 (a table row is read with its header
//   row instead). The
//   threat model, the deployment docs and the release evidence handed to
//   auditors all once named the retired v1 adapter as the production one;
// - a document proposes removing, lifting or relaxing the production boot
//   guard, or forbids that only until some condition holds. A production
//   server refuses to boot until the external crypto audit is attested: the
//   attestation satisfies the guard, and nothing removes it;
// - a document repeats a statement the code contradicts (STALE_STATEMENTS).
//   Each entry names the code that makes its statements false, and an entry
//   whose code is gone fails too, so the list cannot outlive the code;
// - README.md, the launch runbook, the OTF application template or the
//   security roadmap states how many tests, files, specs or migrations there
//   are (every such count in them had gone stale, down to the roadmap's
//   "`@Throttle`, 29 files" in a table headed "measured"), or a module count
//   apps/api/src/modules does not have.
//
// scripts/__tests__/doc-facts.test.mjs runs this check on the repository, so
// `pnpm scripts:test`, part of `pnpm ci:api`, enforces it.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { sentencesOf } from './claims-check.mjs';

export const ADAPTER_SOURCE = 'apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart';
export const API_MODULES = 'apps/api/src/modules';

// Documents, walked recursively for text files.
export const DOC_SOURCES = ['README.md', 'SECURITY.md', 'docs', 'site', 'store'];
// The release, evidence and audit scripts at the top of scripts/ (not its
// tests, whose fixtures name retired ids on purpose).
export const SCRIPTS_DIR = 'scripts';
// Documents that describe the tree as it is now.
export const COUNT_SOURCES = [
  'README.md',
  'docs/launch-runbook.md',
  'docs/otf-application-template.md',
  'docs/security-hardening-roadmap.md',
];

// Rule ids prefix every failure so a test can tell which rule caught it.
export const RULES = {
  adapterId: 'current-adapter-id',
  bootGuard: 'boot-guard-stays',
  staleStatement: 'code-contradicts',
  counts: 'no-stale-counts',
};

const TEXT_EXTENSIONS = /\.(md|txt|html)$/;

// --- current-adapter-id

const ADAPTER_ID = /\blib-(?:[a-z0-9]+-)*aes256gcm-v\d+\b/g;
const HISTORICAL =
  /\b(?:retired|legacy|pre-v2|proposed|proposal|as written against)\b|\bveil-envelope-v1\b/i;

// The getter returns either a string literal or a constant declared in the
// same file: `String get adapterId => 'lib-…';` or
// `String get adapterId => kLibCryptoAdapterId;` with
// `const String kLibCryptoAdapterId = 'lib-…';`.
const ADAPTER_ID_GETTER = /\bString get adapterId =>\s*(?:'([^']+)'|([A-Za-z_]\w*))\s*;/;
const stringConstant = (name) => new RegExp(`\\bconst (?:String )?${name} = '([^']+)'`);

/** The id `LibCryptoAdapter.adapterId` returns. */
export function readProductionAdapterId(rootDir) {
  const source = readFileSync(join(rootDir, ADAPTER_SOURCE), 'utf8');
  const getter = ADAPTER_ID_GETTER.exec(source);
  if (!getter) throw new Error(`${ADAPTER_SOURCE} declares no adapterId`);
  if (getter[1] !== undefined) return getter[1];
  const name = getter[2];
  const constant = stringConstant(name).exec(source);
  if (!constant) {
    throw new Error(
      `${ADAPTER_SOURCE}: adapterId returns ${name}, which the file does not declare as a string constant`,
    );
  }
  return constant[1];
}

const TABLE_ROW = /^\s*\|/;

/**
 * What a line that names an adapter id is read with: a table row with its
 * table's header row, any other line with the line before it (prose wraps).
 */
const adapterIdContext = (lines, index) => {
  if (!TABLE_ROW.test(lines[index])) return `${lines[index - 1] ?? ''}\n${lines[index]}`;
  let start = index;
  while (start > 0 && TABLE_ROW.test(lines[start - 1])) start -= 1;
  return `${lines[start]}\n${lines[index]}`;
};

// --- boot-guard-stays

const BOOT_GUARD = /\b(?:boot|startup) (?:guard|gate)\b/i;
const REMOVAL =
  /\b(?:remov|lift|disabl|drop|relax|loosen|bypass|re-?evaluat|reconsider)\w*|\b(?:turn|switch)\w* off\b/i;
const PROHIBITION = /\b(?:do not|don't|never|must not|may not|cannot|can't)\b/i;
// "even when testing" widens a prohibition instead of ending it.
const CONDITION = /(?<!\beven )\b(?:until|unless|only after|once|after|before|when)\b/i;

// --- code-contradicts

/**
 * Statements the code makes false. `code` must still match, or the entry
 * fails as stale; `statements` must match no sentence of any document.
 */
export const STALE_STATEMENTS = [
  {
    id: 'message-padding-absent',
    fact: 'both clients pad every message to a size bucket before AES-GCM',
    code: [
      {
        file: 'apps/mobile/lib/src/core/crypto/ratchet/session_cipher.dart',
        pattern: /\bMessagePadding\.pad\(/,
      },
      { file: 'apps/web-demo/src/crypto/session-cipher.js', pattern: /\bpadMessage\(/ },
    ],
    statements: [
      /\bpadding\b.*\b(?:absent|missing|confirmed gap|not (?:yet )?(?:implemented|shipped))\b/i,
      /\bciphertext length (?:≈|~|tracks|equals|matches)\s*(?:the )?plaintext length\b/i,
    ],
  },
  {
    id: 'sender-keys-design-only',
    fact: 'new mobile groups use Sender Keys',
    code: [
      {
        file: 'apps/mobile/lib/src/features/conversations/data/group_sender_key_coordinator.dart',
        pattern: /\bclass GroupSenderKeyCoordinator\b/,
      },
    ],
    statements: [/\bsender keys?\b.*\bdesign only\b/i],
  },
  {
    id: 'throttler-header-fallback',
    fact:
      'CfThrottlerGuard keys a signed-in request by its device id and reads a client ' +
      'address only from the one source VEIL_CLIENT_IP_SOURCE names',
    code: [
      {
        file: 'apps/api/src/common/guards/cf-throttler.guard.ts',
        pattern: /\bswitch \(this\.config\.clientIpSource\)/,
      },
    ],
    statements: [/\bCfThrottlerGuard\b.*\b(?:prefers|falls? back)\b/i],
  },
  {
    id: 'web-protocol-in-superseded-spec',
    fact: 'the web client speaks protocol v2; envelope-v3-unified-spec.md was never implemented',
    code: [
      {
        file: 'apps/web-demo/src/crypto/frame.js',
        pattern: /\bENVELOPE_VERSION_V2 = 'veil-envelope-v2'/,
      },
    ],
    statements: [/\bprotocol status\b.*\benvelope-v3-unified-spec\b/i],
  },
];

// --- no-stale-counts

const COUNTED =
  /\b\d[\d,]*(?:\s*\/\s*\d[\d,]*)?\s+(?:(?:Prisma\s+)?migrations|(?:\w+\s+)?files|(?:unit\s+|e2e\s+)?tests|Vitest\b|(?:Playwright\s+)?(?:e2e\s+)?specs)\b|\(\d+\/\d+ currently\)/i;
const MODULE_COUNT = /\b(\d+) modules\b/g;

// --- the check

const filesUnder = (rootDir, target) => {
  const absolute = join(rootDir, target);
  if (!existsSync(absolute)) return [];
  if (statSync(absolute).isFile()) return [target];
  return readdirSync(absolute, { withFileTypes: true }).flatMap((entry) =>
    filesUnder(rootDir, join(target, entry.name)),
  );
};

export function checkDocFacts(rootDir) {
  const failures = [];
  const display = (path) => path.split(sep).join('/');
  const read = (path) => readFileSync(join(rootDir, path), 'utf8');

  const documents = DOC_SOURCES.flatMap((source) => filesUnder(rootDir, source))
    .map(display)
    .filter((path) => TEXT_EXTENSIONS.test(path));
  const scripts = existsSync(join(rootDir, SCRIPTS_DIR))
    ? readdirSync(join(rootDir, SCRIPTS_DIR))
        .filter((name) => name.endsWith('.mjs'))
        .map((name) => `${SCRIPTS_DIR}/${name}`)
    : [];
  const sentences = new Map(documents.map((path) => [path, sentencesOf(read(path), path)]));

  let current = null;
  try {
    current = readProductionAdapterId(rootDir);
  } catch (error) {
    failures.push(`[${RULES.adapterId}] ${error.message}`);
  }
  if (current !== null) {
    for (const path of [...documents, ...scripts]) {
      const lines = read(path).split('\n');
      lines.forEach((line, index) => {
        for (const [id] of line.matchAll(ADAPTER_ID)) {
          if (id === current) continue;
          if (HISTORICAL.test(adapterIdContext(lines, index))) continue;
          failures.push(
            `[${RULES.adapterId}] ${path}:${index + 1} names ${id} as current; ` +
              `the production adapter is ${current} (call an older id retired or legacy)`,
          );
        }
      });
    }
  }

  for (const [path, units] of sentences) {
    for (const sentence of units) {
      const forbidsOutright = PROHIBITION.test(sentence) && !CONDITION.test(sentence);
      if (BOOT_GUARD.test(sentence) && REMOVAL.test(sentence) && !forbidsOutright) {
        failures.push(
          `[${RULES.bootGuard}] ${path}: the production boot guard is never removed; ` +
            `attestation satisfies it: "${sentence}"`,
        );
      }
    }
  }

  for (const entry of STALE_STATEMENTS) {
    const gone = entry.code.filter(
      ({ file, pattern }) => !existsSync(join(rootDir, file)) || !pattern.test(read(file)),
    );
    if (gone.length > 0) {
      for (const { file } of gone) {
        failures.push(
          `[${RULES.staleStatement}] ${entry.id}: ${file} no longer shows that ${entry.fact}; ` +
            'update STALE_STATEMENTS in scripts/doc-facts.mjs',
        );
      }
      continue;
    }
    for (const [path, units] of sentences) {
      for (const sentence of units) {
        if (entry.statements.some((pattern) => pattern.test(sentence))) {
          failures.push(
            `[${RULES.staleStatement}] ${entry.id}: ${path} says "${sentence}", ` +
              `but ${entry.fact}`,
          );
        }
      }
    }
  }

  const modulesDir = join(rootDir, API_MODULES);
  const moduleCount = existsSync(modulesDir)
    ? readdirSync(modulesDir, { withFileTypes: true }).filter((entry) => entry.isDirectory()).length
    : 0;
  for (const path of COUNT_SOURCES) {
    for (const sentence of sentences.get(path) ?? []) {
      if (COUNTED.test(sentence)) {
        failures.push(
          `[${RULES.counts}] ${path} hard-codes a test, file or migration count, which goes stale: ` +
            `"${sentence}"`,
        );
      }
      for (const [, count] of sentence.matchAll(MODULE_COUNT)) {
        if (Number(count) !== moduleCount) {
          failures.push(
            `[${RULES.counts}] ${path} says ${count} modules; ${API_MODULES} has ${moduleCount}`,
          );
        }
      }
    }
  }

  return failures;
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  const rootDir = fileURLToPath(new URL('..', import.meta.url));
  const failures = checkDocFacts(rootDir);
  if (failures.length > 0) {
    console.error('Doc facts check failed:');
    for (const failure of failures) console.error(`  ${failure}`);
    process.exit(1);
  }
  console.log('Doc facts check passed.');
}
