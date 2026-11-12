// Claims-as-code: every public privacy or security claim VEIL makes is
// listed in docs/claims.yaml with the test or gate that backs it.
//
// The gate fails when
// - a claim has no evidence, or its evidence does not exist (a test file
//   without the named test or with skipped or focused tests, a gate script
//   that CI does not run);
// - a sentence in a public source (README, privacy policies, the site, store
//   listings and their drafts, the security roadmap) matches a claim pattern
//   but is not quoted
//   by any claim for that file, so new marketing copy cannot make a claim
//   nobody has to back;
// - a quoted sentence no longer appears in its file.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const LEDGER_PATH = 'docs/claims.yaml';

// Where public claims are made. Directories are walked for text files.
// docs/launch and docs/app-store-listing-metadata.md hold store listing drafts
// that are pasted into the stores; one once advertised "Signed backups". The
// two Korean guides are what README sends people to first; one once said a
// seized server yields only ciphertext.
export const CLAIM_SOURCES = [
  'README.md',
  'docs/app-store-listing-metadata.md',
  'docs/launch',
  'docs/privacy-policy-en.md',
  'docs/privacy-policy-ko.md',
  'docs/security-hardening-roadmap.md',
  'docs/tester-guide-ko.md',
  'docs/사용설명서.md',
  'site',
  'store',
];

// Phrases that make a privacy or security claim. The Korean entries cover the
// Korean policy and store listings, which make the same claims.
export const CLAIM_PATTERNS = [
  /never stored/i,
  /deleted on fetch/i,
  /end[- ]to[- ]end/i,
  /\bE2EE?\b/,
  // Any mention of a backup, as /백업/ below is for Korean: VEIL has none, so
  // a sentence naming one either denies it or advertises what does not exist.
  /\bbackups?\b/i,
  /\bno (?:account )?recovery/i,
  /hardware[- ]backed/i,
  /zero[- ]knowledge/i,
  /post[- ]quantum/i,
  /forward secrecy/i,
  /sealed[- ]sender/i,
  /key transparency/i,
  // What the server can read. Merely naming plaintext makes no claim
  // ("ciphertext length tracks plaintext length"); denying it does. A
  // disclosure of what stays readable is ledgered too, so it cannot quietly
  // disappear while the denial stays.
  /\b(?:no|never|not)\b.*\bplaintext\b/i,
  /\bplaintext\b.*\b(?:never|not)\b/i,
  /readable form/i,
  // Blanket statements about what is collected. "No data collection" and
  // "the consent screen lists every field" once sat in the store listing
  // while the server kept the contact graph and call records.
  /\bno data collection\b/i,
  /\blists every field\b/i,
  // What the ids are. The policy once called the server-assigned account and
  // device ids "anonymous" and "generated on the device".
  /\banonymous (?:user|account|device) id/i,
  /generated on the device/i,
  /익명 식별자/,
  /기기에서 생성된/,
  /데이터 수집이 없/,
  /종단간/,
  /저장되지 않/,
  /복구/,
  /백업/,
  /양자/,
  /전방향/,
  /하드웨어/,
  /평문/,
  /읽을 수 있는 형태/,
];

const TEXT_EXTENSIONS = /\.(md|txt|html)$/;

// --- A YAML subset: block mappings, block sequences and one-line scalars
// (plain, 'single' or "double" quoted). Anything else is a parse error, so the
// ledger cannot silently mean something other than what it says.

const parseScalar = (raw, lineNumber) => {
  const value = raw.trim();
  if (value.startsWith('"')) {
    if (!/^"(?:[^"\\]|\\.)*"$/.test(value)) {
      throw new Error(`${LEDGER_PATH}:${lineNumber}: unterminated double-quoted string`);
    }
    return JSON.parse(value);
  }
  if (value.startsWith("'")) {
    if (!/^'(?:[^']|'')*'$/.test(value)) {
      throw new Error(`${LEDGER_PATH}:${lineNumber}: unterminated single-quoted string`);
    }
    return value.slice(1, -1).replace(/''/g, "'");
  }
  if (/^[[{|>&*!%@`]/.test(value)) {
    throw new Error(`${LEDGER_PATH}:${lineNumber}: unsupported YAML syntax "${value}"`);
  }
  return value;
};

const stripComment = (line) => {
  let quote = null;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (quote) {
      if (char === '\\' && quote === '"') index += 1;
      else if (char === quote) quote = null;
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === '#' && (index === 0 || /\s/.test(line[index - 1]))) {
      return line.slice(0, index);
    }
  }
  return line;
};

export function parseLedger(source) {
  const lines = source
    .split('\n')
    .map((text, index) => ({ text: stripComment(text).replace(/\s+$/, ''), number: index + 1 }))
    .filter((line) => line.text.trim() !== '')
    .map((line) => ({ ...line, indent: line.text.length - line.text.trimStart().length }));
  let position = 0;

  const keyValue = (text, number) => {
    const match = /^([A-Za-z_][\w-]*):(?:\s+(.*))?$/.exec(text);
    if (!match) throw new Error(`${LEDGER_PATH}:${number}: expected "key: value"`);
    return [match[1], match[2]];
  };

  const parseBlock = (indent) => {
    const first = lines[position];
    return first.text.trimStart().startsWith('- ') || first.text.trim() === '-'
      ? parseSequence(indent)
      : parseMapping(indent);
  };

  const parseValue = (rest, parentIndent, number) => {
    if (rest !== undefined && rest !== '') return parseScalar(rest, number);
    const next = lines[position];
    if (!next || next.indent <= parentIndent) {
      throw new Error(`${LEDGER_PATH}:${number}: missing value`);
    }
    return parseBlock(next.indent);
  };

  const parseMapping = (indent, initial = {}) => {
    const mapping = initial;
    while (position < lines.length && lines[position].indent === indent) {
      const { text, number } = lines[position];
      if (text.trimStart().startsWith('- ')) break;
      const [key, rest] = keyValue(text.trim(), number);
      if (key in mapping) throw new Error(`${LEDGER_PATH}:${number}: duplicate key "${key}"`);
      position += 1;
      mapping[key] = parseValue(rest, indent, number);
    }
    return mapping;
  };

  const parseSequence = (indent) => {
    const items = [];
    while (position < lines.length && lines[position].indent === indent) {
      const { text, number } = lines[position];
      const content = text.trimStart();
      if (!content.startsWith('-')) break;
      const item = content.slice(1).trimStart();
      position += 1;
      if (item === '') {
        items.push(parseBlock(lines[position].indent));
      } else if (/^[A-Za-z_][\w-]*:(\s|$)/.test(item)) {
        const [key, rest] = keyValue(item, number);
        const itemIndent = indent + (content.length - item.length);
        items.push(parseMapping(itemIndent, { [key]: parseValue(rest, itemIndent, number) }));
      } else {
        items.push(parseScalar(item, number));
      }
    }
    return items;
  };

  if (lines.length === 0) return {};
  const document = parseBlock(lines[0].indent);
  if (position < lines.length) {
    throw new Error(`${LEDGER_PATH}:${lines[position].number}: unexpected indentation`);
  }
  return document;
}

// --- Sentences of a public source, normalised so that a ledger quote and
// the text it quotes compare equal regardless of markup and line wrapping.

const decodeEntities = (text) =>
  text
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&');

// Attribute text a reader or a search engine sees: image alternatives,
// tooltips, accessible labels and <meta> descriptions.
const TEXT_ATTRIBUTE = /(?<![\w-])(?:alt|title|aria-label|content)\s*=\s*(?:"([^"]*)"|'([^']*)')/gi;

/**
 * Element text with block elements as paragraph breaks, followed by the text
 * attributes, each as a paragraph of its own so that it neither splits nor
 * joins the sentence of the element that carries it.
 */
const htmlToText = (html) => {
  const markup = html
    .replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '');
  const attributes = (markup.match(/<[a-z][^>]*>/gi) ?? []).flatMap((tag) =>
    [...tag.matchAll(TEXT_ATTRIBUTE)].map(
      ([, doubleQuoted, singleQuoted]) => doubleQuoted ?? singleQuoted,
    ),
  );
  const body = markup
    .replace(
      /<\/?(p|li|ul|ol|h[1-6]|div|section|header|footer|br|tr|td|th|table)\b[^>]*>/gi,
      '\n\n',
    )
    .replace(/<[^>]+>/g, '');
  return decodeEntities([body, ...attributes].join('\n\n'));
};

export const normalizeSentence = (text) =>
  text
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\*\*|__|`/g, '')
    .replace(/^\s*(?:[-*•>]|#+|\d+\.)\s+/, '')
    .replace(/^\|\s*|\s*\|$/g, '')
    .replace(/\s+/g, ' ')
    .trim();

// Lines that begin a new unit instead of continuing a wrapped paragraph:
// list items, headings and quotes. Store-listing section headers ("■ Why
// VEIL", "[Subtitle]") are units of their own.
const STARTS_UNIT = /^\s*(?:[-*•>]\s|#+\s|\d+\.\s)/;
const SECTION_HEADER = /^\s*(?:■.*|\[[^\]]*\])\s*$/;
const TABLE_ROW = /^\s*\|/;

// CommonMark code fences: at most three spaces of indent, then a run of three
// or more backticks or tildes. A backtick fence's info string cannot contain
// a backtick, which is what tells a fence from a line that merely opens with
// an inline code span such as `` ```code``` ``. A fence indented further, as
// in a nested list item, is not recognised, so its lines are scanned: the
// check errs towards reading too much, never too little.
const FENCE_OPENING = /^ {0,3}(`{3,}|~{3,})(.*)$/;
const FENCE_CLOSING = /^ {0,3}(`{3,}|~{3,})[ \t]*$/;

/**
 * Indices of the lines that are fenced code, delimiters included. A fence
 * closes only on a run of its own character at least as long as the run that
 * opened it. A fence that never closes hides nothing: CommonMark would render
 * the rest of the file as code, but skipping it would let one stray fence take
 * every later sentence out of the claims check.
 */
function fencedLineIndices(lines) {
  const fenced = new Set();
  let opening = null;
  lines.forEach((line, index) => {
    if (opening === null) {
      const match = FENCE_OPENING.exec(line);
      const [run, info] = match ? [match[1], match[2]] : [];
      if (match && !(run.startsWith('`') && info.includes('`'))) {
        opening = { index, char: run[0], length: run.length };
      }
      return;
    }
    const closing = FENCE_CLOSING.exec(line);
    if (closing && closing[1][0] === opening.char && closing[1].length >= opening.length) {
      for (let fencedIndex = opening.index; fencedIndex <= index; fencedIndex += 1) {
        fenced.add(fencedIndex);
      }
      opening = null;
    }
  });
  return fenced;
}

/**
 * Claim-sized units of a source: paragraphs and list items split into
 * sentences, table rows kept whole (a row states one capability), fenced
 * code skipped.
 */
export function sentencesOf(source, path) {
  const text = path.endsWith('.html') ? htmlToText(source) : source;
  const lines = text.split('\n');
  const fenced = fencedLineIndices(lines);
  const units = [];
  let current = [];
  const flush = () => {
    if (current.length > 0) units.push({ text: current.join(' '), split: true });
    current = [];
  };
  for (const [index, line] of lines.entries()) {
    if (fenced.has(index)) {
      flush();
    } else if (line.trim() === '') {
      flush();
    } else if (TABLE_ROW.test(line)) {
      flush();
      if (!/^\s*\|[\s|:-]*$/.test(line)) units.push({ text: line, split: false });
    } else if (SECTION_HEADER.test(line)) {
      flush();
      units.push({ text: line, split: false });
    } else {
      if (STARTS_UNIT.test(line)) flush();
      current.push(line.trim());
    }
  }
  flush();
  return units
    .flatMap(({ text: unit, split }) =>
      split ? normalizeSentence(unit).split(/(?<=[.!?。])\s+(?=\S)/) : [unit],
    )
    .map(normalizeSentence)
    .filter(Boolean);
}

const isClaim = (sentence) => CLAIM_PATTERNS.some((pattern) => pattern.test(sentence));

// --- Evidence

const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const declaresTest = (source, name) =>
  new RegExp(`\\b(?:it|test)\\(\\s*(['"\`])${escapeRegExp(name)}\\1`).test(source);

// A test that does not run backs nothing. A skipped or focused block can stop
// the named test from running without touching its line, so any such marker
// in the file disqualifies the whole file as evidence.
const SKIPS_TESTS =
  /\b(?:describe|context|suite|it|test)\.(?:skip|only|todo)\b|\bx(?:describe|it|test)\(|\bf(?:describe|it)\(/;

function evidenceProblems(rootDir, evidence, ciScripts) {
  if (evidence.test !== undefined) {
    if (typeof evidence.name !== 'string' || evidence.name === '') {
      return [`test evidence ${evidence.test} names no test`];
    }
    const file = join(rootDir, evidence.test);
    if (!existsSync(file)) return [`test file ${evidence.test} does not exist`];
    const source = readFileSync(file, 'utf8');
    if (!declaresTest(source, evidence.name)) {
      return [`${evidence.test} has no test named "${evidence.name}"`];
    }
    return SKIPS_TESTS.test(source)
      ? [`${evidence.test} skips or focuses tests, so "${evidence.name}" may not run`]
      : [];
  }
  if (evidence.gate !== undefined) {
    if (!existsSync(join(rootDir, evidence.gate))) return [`gate ${evidence.gate} does not exist`];
    return ciScripts.some((script) => script.includes(evidence.gate))
      ? []
      : [`gate ${evidence.gate} is not run by any package.json script`];
  }
  return [`evidence must name a test (with name) or a gate: ${JSON.stringify(evidence)}`];
}

const filesUnder = (rootDir, target) => {
  const absolute = join(rootDir, target);
  if (!existsSync(absolute)) return [];
  if (statSync(absolute).isFile()) return [target];
  return readdirSync(absolute, { withFileTypes: true }).flatMap((entry) =>
    filesUnder(rootDir, join(target, entry.name)),
  );
};

export function checkClaims(rootDir, { sources = CLAIM_SOURCES } = {}) {
  const failures = [];
  const display = (path) => path.split(sep).join('/');
  let ledger;
  try {
    ledger = parseLedger(readFileSync(join(rootDir, LEDGER_PATH), 'utf8'));
  } catch (error) {
    return [error.message];
  }
  const claims = Array.isArray(ledger?.claims) ? ledger.claims : [];
  if (claims.length === 0) failures.push(`${LEDGER_PATH} lists no claims`);

  const packageJson = JSON.parse(readFileSync(join(rootDir, 'package.json'), 'utf8'));
  const ciScripts = Object.values(packageJson.scripts ?? {});

  const sourceFiles = sources
    .flatMap((source) => filesUnder(rootDir, source))
    .map(display)
    .filter((path) => TEXT_EXTENSIONS.test(path));
  const sentencesByFile = new Map(
    sourceFiles.map((path) => [path, sentencesOf(readFileSync(join(rootDir, path), 'utf8'), path)]),
  );

  const quoted = new Set();
  const ids = new Set();
  for (const claim of claims) {
    const label = claim?.id ?? '(claim without id)';
    if (typeof claim?.id !== 'string' || !/^[a-z0-9][a-z0-9-]*$/.test(claim.id)) {
      failures.push(`${label}: id must be kebab-case`);
    } else if (ids.has(claim.id)) {
      failures.push(`${label}: duplicate id`);
    }
    ids.add(claim?.id);
    if (typeof claim?.text !== 'string' || claim.text.trim() === '') {
      failures.push(`${label}: missing text`);
    }

    const claimSources = Array.isArray(claim?.sources) ? claim.sources : [];
    if (claimSources.length === 0) failures.push(`${label}: lists no sources`);
    for (const source of claimSources) {
      const sentences = sentencesByFile.get(source?.file);
      if (!sentences) {
        failures.push(`${label}: ${source?.file} is not a scanned claim source`);
        continue;
      }
      const quote = normalizeSentence(String(source.quote ?? ''));
      if (!sentences.includes(quote)) {
        failures.push(`${label}: ${source.file} no longer says "${quote}"`);
      }
      quoted.add(`${source.file}\u0000${quote}`);
    }

    const evidence = Array.isArray(claim?.evidence) ? claim.evidence : [];
    if (evidence.length === 0) failures.push(`${label}: has no evidence`);
    for (const item of evidence) {
      for (const problem of evidenceProblems(rootDir, item ?? {}, ciScripts)) {
        failures.push(`${label}: ${problem}`);
      }
    }
  }

  for (const [path, sentences] of sentencesByFile) {
    for (const sentence of sentences) {
      if (isClaim(sentence) && !quoted.has(`${path}\u0000${sentence}`)) {
        failures.push(`${path}: unledgered claim "${sentence}"`);
      }
    }
  }
  return failures;
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  const rootDir = fileURLToPath(new URL('..', import.meta.url));
  const failures = checkClaims(rootDir);
  if (failures.length > 0) {
    console.error('Claims check failed:');
    for (const failure of failures) console.error(`  ${failure}`);
    process.exit(1);
  }
  console.log('Claims check passed.');
}
