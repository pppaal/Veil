// Architecture gate for the web client (apps/web-demo), the layering
// docs/web-architecture.md describes:
//   - app.js is a bootstrap of at most 300 lines, and no module under src/
//     is longer than 450;
//   - the lower layers (src/core, src/crypto, src/domain, src/platform)
//     import nothing from src/features, src/ui or src/app; src/features
//     nothing from src/ui or src/app; and the app's services nothing from
//     src/ui;
//   - the lower layers never reach for the DOM: no document, window or other
//     page globals. Only src/platform may touch indexedDB, navigator.locks
//     and the Web Storage objects it is handed, and globalThis is read for
//     crypto alone;
//   - relative imports resolve, and no module imports itself through a
//     cycle.
// A self-test runs every rule against seeded violations first, so the gate
// cannot pass by matching nothing.

import {
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, posix, relative, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const WEB_ROOT = 'apps/web-demo';
const BOOTSTRAP = 'app.js';
const MAX_BOOTSTRAP_LINES = 300;
const MAX_MODULE_LINES = 450;
const SKIPPED_DIRS = new Set(['node_modules']);

// Rule ids prefix every failure so the self-test can tell that a seeded
// violation was caught by the rule it targets, not by accident.
export const RULES = {
  bootstrapSize: 'bootstrap-size',
  moduleSize: 'module-size',
  layerImports: 'layer-imports',
  domFreeLayers: 'dom-free-layers',
  importResolves: 'import-resolves',
  noImportCycles: 'no-import-cycles',
};

const LOWER_LAYERS = ['src/core/', 'src/crypto/', 'src/domain/', 'src/platform/'];
const LAYER_BOUNDARIES = [
  { from: LOWER_LAYERS, forbidden: ['src/features/', 'src/ui/', 'src/app/'] },
  { from: ['src/features/'], forbidden: ['src/ui/', 'src/app/'] },
  { from: ['src/app/services/'], forbidden: ['src/ui/'] },
];

// Page globals the lower layers must not reference. The platform layer is
// where storage lives, so it alone may use the storage handles below.
const PAGE_GLOBALS = new Set([
  'document',
  'window',
  'navigator',
  'location',
  'requestAnimationFrame',
  'MutationObserver',
  'IntersectionObserver',
  'HTMLElement',
  'getComputedStyle',
  'indexedDB',
  'localStorage',
  'sessionStorage',
]);
const PLATFORM_STORAGE_GLOBALS = new Set(['indexedDB', 'localStorage', 'sessionStorage']);

const KEYWORDS_BEFORE_EXPRESSION = new Set([
  'return',
  'typeof',
  'instanceof',
  'in',
  'of',
  'new',
  'delete',
  'void',
  'throw',
  'case',
  'do',
  'else',
  'yield',
  'await',
]);

// Splits JavaScript into tokens: identifiers, punctuators and string
// literals (template literals as their expressions), with comments and
// regular expression literals dropped. Enough to read imports and global
// references, not a full parser.
export function tokenize(source) {
  const tokens = [];
  let i = 0;
  const previous = () => tokens.at(-1);
  const regexAllowed = () => {
    const last = previous();
    if (!last) return true;
    if (last.type === 'punct') return !/^[)\]]$/.test(last.value);
    if (last.type === 'ident') return KEYWORDS_BEFORE_EXPRESSION.has(last.value);
    return false;
  };

  function readQuoted(quote) {
    let value = '';
    i += 1;
    while (i < source.length && source[i] !== quote) {
      if (source[i] === '\\') i += 1;
      value += source[i];
      i += 1;
    }
    i += 1;
    return value;
  }

  function skipRegex() {
    let inClass = false;
    i += 1;
    while (i < source.length) {
      const char = source[i];
      if (char === '\\') i += 1;
      else if (char === '[') inClass = true;
      else if (char === ']') inClass = false;
      else if (char === '/' && !inClass) break;
      else if (char === '\n') break;
      i += 1;
    }
    i += 1;
    while (/[a-z]/i.test(source[i] ?? '')) i += 1;
  }

  // Lexes until the brace that closes a template expression, or the end.
  function lex(closingBrace) {
    let depth = 0;
    while (i < source.length) {
      const char = source[i];
      const next = source[i + 1];
      if (/\s/.test(char)) {
        i += 1;
      } else if (char === '/' && next === '/') {
        while (i < source.length && source[i] !== '\n') i += 1;
      } else if (char === '/' && next === '*') {
        const end = source.indexOf('*/', i + 2);
        i = end === -1 ? source.length : end + 2;
      } else if (char === "'" || char === '"') {
        tokens.push({ type: 'string', value: readQuoted(char) });
      } else if (char === '`') {
        i += 1;
        while (i < source.length && source[i] !== '`') {
          if (source[i] === '\\') {
            i += 2;
          } else if (source[i] === '$' && source[i + 1] === '{') {
            i += 2;
            lex(true);
          } else {
            i += 1;
          }
        }
        i += 1;
        tokens.push({ type: 'template' });
      } else if (char === '/' && regexAllowed()) {
        skipRegex();
        tokens.push({ type: 'regex' });
      } else if (/[A-Za-z_$]/.test(char)) {
        const start = i;
        while (/[\w$]/.test(source[i] ?? '')) i += 1;
        tokens.push({ type: 'ident', value: source.slice(start, i) });
      } else if (/[0-9]/.test(char)) {
        while (/[\w.]/.test(source[i] ?? '')) i += 1;
        tokens.push({ type: 'number' });
      } else {
        if (char === '{') depth += 1;
        if (char === '}') {
          if (closingBrace && depth === 0) {
            i += 1;
            return;
          }
          depth -= 1;
        }
        if (char === '.' && next === '.' && source[i + 2] === '.') {
          tokens.push({ type: 'punct', value: '...' });
          i += 3;
        } else {
          tokens.push({ type: 'punct', value: char });
          i += 1;
        }
      }
    }
  }

  lex(false);
  return tokens;
}

// Every module specifier a file names: static imports and re-exports, and
// dynamic imports of a string literal.
export function importSpecifiers(tokens) {
  const specifiers = [];
  tokens.forEach((token, index) => {
    const next = tokens[index + 1];
    if (token.type === 'ident' && token.value === 'from' && next?.type === 'string') {
      specifiers.push(next.value);
    } else if (
      token.type === 'ident' &&
      token.value === 'import' &&
      tokens[index - 1]?.value !== '.'
    ) {
      if (next?.type === 'string') specifiers.push(next.value);
      if (next?.value === '(' && tokens[index + 2]?.type === 'string')
        specifiers.push(tokens[index + 2].value);
    }
  });
  return specifiers;
}

// The page globals a file references: identifiers that are not a property
// access or an object key, each with the property read from it, if any.
function globalReferences(tokens) {
  const references = [];
  tokens.forEach((token, index) => {
    if (token.type !== 'ident') return;
    const before = tokens[index - 1];
    const after = tokens[index + 1];
    if (before?.value === '.' || after?.value === ':') return;
    const property =
      after?.value === '.' && tokens[index + 2]?.type === 'ident' ? tokens[index + 2].value : null;
    if (token.value === 'globalThis') {
      if (property && property !== 'crypto') references.push(`globalThis.${property}`);
    } else if (PAGE_GLOBALS.has(token.value)) {
      references.push({ name: token.value, property });
    }
  });
  return references;
}

function allowedInLayer(file, reference) {
  if (typeof reference === 'string') return false;
  if (!file.startsWith('src/platform/')) return false;
  if (PLATFORM_STORAGE_GLOBALS.has(reference.name)) return true;
  return reference.name === 'navigator' && reference.property === 'locks';
}

const countLines = (source) => (source.match(/\n/g) ?? []).length;

function listModules(webRoot) {
  const walk = (dir) =>
    readdirSync(dir).flatMap((entry) => {
      const path = join(dir, entry);
      if (statSync(path).isDirectory()) return SKIPPED_DIRS.has(entry) ? [] : walk(path);
      return /\.m?js$/.test(entry) ? [path] : [];
    });
  return walk(webRoot).map((path) => relative(webRoot, path).split(sep).join('/'));
}

function resolveImport(file, specifier, known) {
  if (!specifier.startsWith('.')) return { external: true };
  const target = posix.normalize(posix.join(posix.dirname(file), specifier));
  return known.has(target) ? { target } : { missing: target };
}

// Each import cycle once, as the chain of files that closes it.
function findCycles(graph) {
  const cycles = [];
  const state = new Map();
  const stack = [];
  const visit = (file) => {
    state.set(file, 'open');
    stack.push(file);
    for (const target of graph.get(file) ?? []) {
      if (state.get(target) === 'open') {
        cycles.push([...stack.slice(stack.indexOf(target)), target]);
      } else if (!state.has(target)) {
        visit(target);
      }
    }
    stack.pop();
    state.set(file, 'done');
  };
  for (const file of [...graph.keys()].sort()) if (!state.has(file)) visit(file);
  return cycles;
}

export function runArchitectureChecks(rootDir) {
  const webRoot = join(rootDir, WEB_ROOT);
  const failures = [];
  const files = listModules(webRoot);
  const known = new Set(files);
  const graph = new Map();

  for (const file of files) {
    const source = readFileSync(join(webRoot, file), 'utf8');
    const lines = countLines(source);
    if (file === BOOTSTRAP && lines > MAX_BOOTSTRAP_LINES) {
      failures.push(
        `[${RULES.bootstrapSize}] ${file} has ${lines} lines (at most ${MAX_BOOTSTRAP_LINES})`,
      );
    }
    if (file.startsWith('src/') && file.endsWith('.js') && lines > MAX_MODULE_LINES) {
      failures.push(
        `[${RULES.moduleSize}] ${file} has ${lines} lines (at most ${MAX_MODULE_LINES})`,
      );
    }

    const tokens = tokenize(source);
    const targets = [];
    for (const specifier of importSpecifiers(tokens)) {
      const resolved = resolveImport(file, specifier, known);
      if (resolved.missing)
        failures.push(
          `[${RULES.importResolves}] ${file} imports ${specifier}, which does not exist`,
        );
      if (!resolved.target) continue;
      targets.push(resolved.target);
      for (const boundary of LAYER_BOUNDARIES) {
        if (!boundary.from.some((layer) => file.startsWith(layer))) continue;
        const crossed = boundary.forbidden.find((layer) => resolved.target.startsWith(layer));
        if (crossed)
          failures.push(
            `[${RULES.layerImports}] ${file} imports ${resolved.target} from ${crossed}`,
          );
      }
    }
    graph.set(file, targets);

    if (LOWER_LAYERS.some((layer) => file.startsWith(layer))) {
      for (const reference of globalReferences(tokens)) {
        if (allowedInLayer(file, reference)) continue;
        const name = typeof reference === 'string' ? reference : reference.name;
        failures.push(`[${RULES.domFreeLayers}] ${file} references ${name}`);
      }
    }
  }

  for (const cycle of findCycles(graph)) {
    failures.push(`[${RULES.noImportCycles}] ${cycle.join(' -> ')}`);
  }
  return failures;
}

const lines = (count, line) => `${Array.from({ length: count }, () => line).join('\n')}\n`;

// A tree that satisfies every rule, including the shapes the rules must not
// mistake for violations: page globals in comments, strings and property
// names, globalThis.crypto, and the platform layer's storage handles.
export const CLEAN_FIXTURE = {
  [`${WEB_ROOT}/app.js`]: [
    "import { createStore } from './src/app/store.js';",
    "import { mountView } from './src/ui/view.js';",
    'mountView(createStore());',
    '',
  ].join('\n'),
  [`${WEB_ROOT}/src/app/store.js`]: 'export const createStore = () => ({ document: null });\n',
  [`${WEB_ROOT}/src/app/services/sync.js`]:
    "import { digest } from '../../crypto/digest.js';\nexport const sync = () => digest();\n",
  [`${WEB_ROOT}/src/ui/view.js`]: [
    "import { sync } from '../app/services/sync.js';",
    'export const mountView = () => document.body.append(String(sync()));',
    '',
  ].join('\n'),
  [`${WEB_ROOT}/src/crypto/digest.js`]: [
    '// Never reads window or document.',
    "const label = 'document.title';",
    'const pattern = /window\\.\\w+/u;',
    'export const digest = () => globalThis.crypto.getRandomValues(new Uint8Array(4)) && label && pattern;',
    'export const ratio = (a, b) => a / b / 2;',
    '',
  ].join('\n'),
  [`${WEB_ROOT}/src/domain/model.js`]: [
    "import { digest } from '../crypto/digest.js';",
    'export const model = (options) => ({ window: options.window, digest: digest() });',
    'export const view = `${model.name} in ${String(digest)}`;',
    '',
  ].join('\n'),
  [`${WEB_ROOT}/src/platform/storage.js`]: [
    'export const open = () => indexedDB.open("x");',
    'export const lock = (name, task) => navigator.locks.request(name, task);',
    'export const clear = ({ localStorage, sessionStorage }) => [localStorage, sessionStorage];',
    '',
  ].join('\n'),
  [`${WEB_ROOT}/src/features/feature.js`]:
    "import { model } from '../domain/model.js';\nexport const feature = () => import('../platform/storage.js').then(model);\n",
  [`${WEB_ROOT}/src/ui/long.js`]: lines(MAX_MODULE_LINES, '// within the limit'),
};

export const SEEDED_VIOLATIONS = [
  {
    rule: RULES.bootstrapSize,
    files: { [`${WEB_ROOT}/app.js`]: lines(MAX_BOOTSTRAP_LINES + 1, '// bootstrap') },
  },
  {
    rule: RULES.moduleSize,
    files: { [`${WEB_ROOT}/src/ui/long.js`]: lines(MAX_MODULE_LINES + 1, '// too long') },
  },
  {
    rule: RULES.layerImports,
    files: {
      [`${WEB_ROOT}/src/crypto/digest.js`]:
        "import '../ui/view.js';\nexport const digest = () => 1;\n",
    },
  },
  {
    rule: RULES.layerImports,
    files: {
      [`${WEB_ROOT}/src/domain/model.js`]:
        "export { createStore as model } from '../app/store.js';\n",
    },
  },
  {
    rule: RULES.layerImports,
    files: {
      [`${WEB_ROOT}/src/platform/storage.js`]:
        "export const open = () => import('../features/feature.js');\n",
    },
  },
  {
    rule: RULES.layerImports,
    files: {
      [`${WEB_ROOT}/src/features/feature.js`]:
        "import { mountView } from '../ui/view.js';\nexport const feature = mountView;\n",
    },
  },
  {
    rule: RULES.layerImports,
    files: {
      [`${WEB_ROOT}/src/app/services/sync.js`]:
        "import { mountView } from '../../ui/view.js';\nexport const sync = mountView;\n",
    },
  },
  {
    rule: RULES.domFreeLayers,
    files: { [`${WEB_ROOT}/src/domain/model.js`]: 'export const model = () => document.title;\n' },
  },
  {
    rule: RULES.domFreeLayers,
    files: { [`${WEB_ROOT}/src/crypto/digest.js`]: 'export const digest = () => window.crypto;\n' },
  },
  {
    rule: RULES.domFreeLayers,
    files: {
      [`${WEB_ROOT}/src/core/agent.js`]: 'export const agent = () => navigator.userAgent;\n',
    },
  },
  {
    rule: RULES.domFreeLayers,
    files: {
      [`${WEB_ROOT}/src/platform/storage.js`]:
        'export const copy = (text) => navigator.clipboard.writeText(text);\n',
    },
  },
  {
    rule: RULES.domFreeLayers,
    files: {
      [`${WEB_ROOT}/src/crypto/digest.js`]: 'export const digest = () => indexedDB.open("keys");\n',
    },
  },
  {
    rule: RULES.domFreeLayers,
    files: {
      [`${WEB_ROOT}/src/domain/model.js`]: 'export const model = () => globalThis.document;\n',
    },
  },
  {
    rule: RULES.domFreeLayers,
    files: {
      [`${WEB_ROOT}/src/domain/model.js`]:
        'export const model = () => requestAnimationFrame(() => {});\n',
    },
  },
  {
    rule: RULES.importResolves,
    files: {
      [`${WEB_ROOT}/src/ui/view.js`]:
        "import './missing.js';\nexport const mountView = () => {};\n",
    },
  },
  {
    rule: RULES.noImportCycles,
    files: {
      [`${WEB_ROOT}/src/ui/view.js`]:
        "import { other } from './other.js';\nexport const mountView = other;\n",
      [`${WEB_ROOT}/src/ui/other.js`]:
        "import { mountView } from './view.js';\nexport const other = () => mountView;\n",
    },
  },
  {
    rule: RULES.noImportCycles,
    files: {
      [`${WEB_ROOT}/src/app/store.js`]:
        "export const createStore = () => import('../../app.js');\n",
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
  const scratch = mkdtempSync(join(tmpdir(), 'veil-web-architecture-self-test-'));
  try {
    const cleanRoot = join(scratch, 'clean');
    writeTree(cleanRoot, CLEAN_FIXTURE);
    const cleanFailures = runArchitectureChecks(cleanRoot);
    if (cleanFailures.length > 0)
      problems.push(`clean fixture failed: ${cleanFailures.join('; ')}`);

    SEEDED_VIOLATIONS.forEach((violation, index) => {
      const root = join(scratch, `violation-${index}`);
      writeTree(root, { ...CLEAN_FIXTURE, ...violation.files });
      const failures = runArchitectureChecks(root);
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
    console.error('Web architecture check self-test failed:');
    for (const problem of selfTestProblems) console.error(`  ${problem}`);
    process.exit(1);
  }

  const repoRoot = fileURLToPath(new URL('..', import.meta.url));
  const failures = runArchitectureChecks(repoRoot);
  if (failures.length > 0) {
    for (const failure of failures) console.error(failure);
    process.exit(1);
  }

  console.log(
    `Web architecture self-test passed (${SEEDED_VIOLATIONS.length} seeded violations caught).`,
  );
  console.log('Web architecture checks passed.');
}
