// Static policy gate for the web client (scripts/policy-check.mjs covers the
// API and mobile). It scans every shipped script and fails on the patterns
// behind past web-demo security defects.

import { describe, expect, it } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const SCANNED = ['app.js', 's.js', 'src', 'lib', 'i18n'];

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
    id: 'extractable-identity-key',
    description: 'Ed25519/X25519 keys must be generated with extractable = false',
    pattern: /generateKey\(\s*(?:\{[^}]*?['"`](?:Ed|X)25519['"`][^}]*\}|[\w$]*25519[\w$]*)\s*,\s*true\b/,
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
    if (rule.exempt?.(file)) continue;
    const match = rule.pattern.exec(source);
    if (match) {
      const line = source.slice(0, match.index).split('\n').length;
      violations.push(`${rule.id} ${file}:${line} — ${rule.description}`);
    }
  }
  return violations;
}

const SEEDED_VIOLATIONS = {
  'jwk-export': "const jwk = await crypto.subtle.exportKey('jwk', keys.edPrivKey);",
  'pkcs8-export': 'const der = await crypto.subtle.exportKey("pkcs8", me.xPrivKey);',
  'extractable-identity-key': "const ed = await crypto.subtle.generateKey(\n  { name: 'Ed25519' },\n  true,\n  ['sign', 'verify'],\n);",
  'window-veil-global': 'if (isDevHost) {\n  window.__veil = state;\n}',
  'plaintext-field': "await idbPut('outbound', { clientMessageId, envelope, plaintext: text });",
  'html-sink': 'span.innerHTML = renderMessageInline(msg._text);',
};

describe('web policy', () => {
  it('passes on the final tree', () => {
    const files = scannedFiles();
    expect(files).toEqual(expect.arrayContaining(['app.js', 's.js', 'lib/markdown.js', 'src/crypto/identity.js']));
    const violations = files.flatMap((file) => findViolations(file, readFileSync(join(ROOT, file), 'utf8')));
    expect(violations).toEqual([]);
  });

  it.each(Object.entries(SEEDED_VIOLATIONS))('fails on a seeded %s violation', (ruleId, snippet) => {
    const violations = findViolations('app.js', `// seeded\n${snippet}\n`);
    expect(violations.some((violation) => violation.startsWith(`${ruleId} app.js:`))).toBe(true);
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
      "const pkcs8 = await subtle.exportKey('pkcs8', key);",
    ];
    for (const snippet of safe.slice(0, -1)) expect(findViolations('app.js', snippet)).toEqual([]);
    expect(findViolations('src/crypto/identity.js', safe.at(-1))).toEqual([]);
  });
});
