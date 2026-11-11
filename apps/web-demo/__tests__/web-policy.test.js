// Static policy gate for the web client (scripts/policy-check.mjs covers the
// API and mobile). It scans every shipped script and fails on the patterns
// behind past web-demo security defects.

import { describe, expect, it } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const SCANNED = ['app.js', 's.js', 'src', 'lib', 'i18n'];

// The modules that hold or derive key material and session state.
const CRYPTO_STATE_FILES = /^src\/(?:crypto\/|platform\/(?:content-store|session-store|kv|idb)\.js$)/;

const RULES = [
  {
    id: 'jwk-export',
    description: "keys must not be exported as JWK (exportKey('jwk', ...))",
    pattern: /exportKey\(\s*['"`]jwk['"`]/,
  },
  {
    id: 'pkcs8-export',
    description: 'private keys are exported only to seal legacy extractable keys in src/crypto/identity.js',
    pattern: /exportKey\(\s*['"`]pkcs8['"`]/,
    exempt: (file) => file === 'src/crypto/identity.js',
  },
  {
    id: 'extractable-key',
    description: 'keys are generated, imported, derived and unwrapped with extractable = false',
    pattern: /\b(?:generateKey|importKey|deriveKey|unwrapKey)\s*\([^;]*?,\s*true\s*[,)]/,
  },
  {
    id: 'window-veil-global',
    description: 'no window.__veil global (it exposed keys and tokens)',
    pattern: /\b(?:window|globalThis|self)\s*\.\s*__veil\s*=(?!=)/,
  },
  {
    id: 'plaintext-field',
    description: "no object field named 'plaintext' (stored records must never carry decrypted text)",
    pattern: /(?:(?:^[ \t]*|[{,]\s*)['"`]?_?plaintext['"`]?[ \t]*:|\._?plaintext\s*=(?!=))/m,
  },
  {
    id: 'html-sink',
    description: 'messages and UI are built with DOM nodes; no HTML string sinks',
    pattern: /(?:\.(?:innerHTML|outerHTML)\s*\+?=(?!=)|\binsertAdjacentHTML\s*\(|\bdocument\.write(?:ln)?\s*\(|\bcreateContextualFragment\s*\()/,
  },
  {
    id: 'v1dev-write',
    description: "'veil-envelope-v1-dev' is read-only: only src/crypto/legacy-v1dev.js names it, and nothing labels an envelope with it",
    pattern: /veil-envelope-v1-dev|\bDEV_ENVELOPE_VERSION\b|\bversion\s*:\s*LEGACY_V1DEV_VERSION\b/,
    exempt: (file) => file === 'src/crypto/legacy-v1dev.js',
  },
  {
    id: 'failure-count-refetch',
    description: 'decryption failures are never counted toward refetching keys: a server that can make messages fail must not be able to swap keys that way',
    pattern: /\b\w*(?:fail|decrypt)\w*(?:count|counter|streak|attempts|tries)\b|\brefetch\w*\s*\(/i,
  },
  {
    id: 'crypto-module-storage',
    description: 'crypto modules keep their state in IndexedDB (non-extractable CryptoKeys, sealed bytes), never in Web Storage',
    pattern: /\b(?:localStorage|sessionStorage)\b/,
    applies: (file) => CRYPTO_STATE_FILES.test(file),
  },
  {
    id: 'crypto-state-web-storage',
    description: 'no key, session, pin or identity state is written to localStorage or sessionStorage',
    pattern: /\b(?:localStorage|sessionStorage)\s*\.\s*setItem\s*\(\s*[^,]*(?:session|ratchet|prekey|identity|pin|secret|crypt|kek|private)/i,
  },
];

function scannedFiles() {
  const walk = (path) => (statSync(path).isDirectory()
    ? readdirSync(path).flatMap((entry) => walk(join(path, entry)))
    : [path]);
  return SCANNED.flatMap((entry) => walk(join(ROOT, entry)))
    .filter((path) => path.endsWith('.js'))
    .map((path) => relative(ROOT, path).split('\\').join('/'));
}

function findViolations(file, source) {
  const violations = [];
  for (const rule of RULES) {
    if (rule.exempt?.(file) || (rule.applies && !rule.applies(file))) continue;
    const match = rule.pattern.exec(source);
    if (match) {
      const line = source.slice(0, match.index).split('\n').length;
      violations.push(`${rule.id} ${file}:${line} — ${rule.description}`);
    }
  }
  return violations;
}

const SEEDED_VIOLATIONS = {
  'jwk-export': ['app.js', "const jwk = await crypto.subtle.exportKey('jwk', keys.edPrivKey);"],
  'pkcs8-export': ['app.js', 'const der = await crypto.subtle.exportKey("pkcs8", me.xPrivKey);'],
  'extractable-key': ['app.js', "const ed = await crypto.subtle.generateKey(\n  { name: 'Ed25519' },\n  true,\n  ['sign', 'verify'],\n);"],
  'window-veil-global': ['app.js', 'if (isDevHost) {\n  window.__veil = state;\n}'],
  'plaintext-field': ['app.js', "await idbPut('outbound', { clientMessageId, envelope, plaintext: text });"],
  'html-sink': ['app.js', 'span.innerHTML = renderMessageInline(msg._text);'],
  'v1dev-write': ['app.js', "const envelope = { version: 'veil-envelope-v1-dev', ciphertext, nonce };"],
  'failure-count-refetch': ['src/crypto/pins.js', 'if (++decryptFailureCount > 3) lookups.delete(userId);'],
  'crypto-module-storage': ['src/crypto/session-repo.js', "localStorage.getItem('veil-ratchet');"],
  'crypto-state-web-storage': ['app.js', "localStorage.setItem('veil-session-keys', JSON.stringify(keys));"],
};

describe('web policy', () => {
  it('passes on the final tree', () => {
    const files = scannedFiles();
    expect(files).toEqual(expect.arrayContaining([
      'app.js',
      's.js',
      'lib/markdown.js',
      'src/crypto/identity.js',
      'src/crypto/legacy-v1dev.js',
      'src/crypto/session-cipher.js',
    ]));
    const violations = files.flatMap((file) => findViolations(file, readFileSync(join(ROOT, file), 'utf8')));
    expect(violations).toEqual([]);
  });

  it.each(Object.entries(SEEDED_VIOLATIONS))('fails on a seeded %s violation', (ruleId, [file, snippet]) => {
    const violations = findViolations(file, `// seeded\n${snippet}\n`);
    expect(violations.some((violation) => violation.startsWith(`${ruleId} ${file}:`))).toBe(true);
  });

  it('catches the variants earlier builds actually shipped', () => {
    const shipped = [
      "edPrivJwk: await crypto.subtle.exportKey('jwk', keys.edPrivKey),",
      "const x = await crypto.subtle.generateKey({ name: 'X25519' }, true, ['deriveBits']);",
      "    _plaintext: '🖼 이미지',",
      'cap.innerHTML = renderMessageInline(text);',
      'node.insertAdjacentHTML("beforeend", html);',
      'globalThis.__veil = state;',
      'entry.plaintext = text;',
      "const envelope = { version: DEV_ENVELOPE_VERSION, conversationId: conv.id };",
      "export const DEV_ENVELOPE_VERSION = 'veil-envelope-v1-dev';",
      "const aesKey = await subtle.importKey('raw', key, { name: 'AES-GCM' }, true, ['encrypt']);",
    ];
    for (const snippet of shipped) expect(findViolations('app.js', snippet)).not.toEqual([]);
  });

  it('does not flag the safe forms', () => {
    const safe = [
      "const ed = await subtle.generateKey(ED25519, false, ['sign', 'verify']);",
      "const raw = await subtle.exportKey('raw', ed.publicKey);",
      'const decrypt = payload === undefined ? a : b;',
      "if (window.__veil === undefined) return;",
      'node.textContent = text;',
      "const key = await subtle.importKey('raw', keyBytes, AES_GCM, false, ['encrypt']);\nconst sent = true;",
      "try { localStorage.setItem(BETA_BANNER_KEY, '1'); } catch {}",
      "const attempts = (item.attempts ?? 0) + 1;",
    ];
    for (const snippet of safe) expect(findViolations('app.js', snippet)).toEqual([]);
    expect(findViolations('src/crypto/identity.js', "const pkcs8 = await subtle.exportKey('pkcs8', key);")).toEqual([]);
    expect(findViolations('src/crypto/legacy-v1dev.js', "const LEGACY_V1DEV_VERSION = 'veil-envelope-v1-dev';")).toEqual([]);
    expect(findViolations('src/platform/wipe.js', 'await attempt(() => removePrefixedKeys(localStorage));')).toEqual([]);
  });
});
