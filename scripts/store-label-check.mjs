// Store privacy labels are declared once per store:
// - store/appstore/app-privacy-answers.md: the App Store "App Privacy" answers;
// - store/play/data-safety-answers.md: the Google Play "Data safety" answers.
//
// The gate fails when
// - the server stores data that the answers do not declare as collected
//   (the in-app contact list, call records, readable group and channel names,
//   device labels, push tokens, ids), read from apps/api/prisma/schema.prisma;
// - the two answers files disagree about a data type both stores ask about;
// - any other document (docs/, store/, site/, README.md) says a type the
//   answers declare as collected is not collected (in a sentence, in a list
//   under a "not collected" heading or lead-in, or in a table's "Collected"
//   column), frames the label as "Data Not Collected" throughout, or gives a
//   label summary that names the identifiers but leaves out Contacts or the
//   linked user content.
//
// Launch docs once told operators to declare Contacts as not collected while
// the server kept the contact graph and call records. claims-check does not
// read those docs, and a store label is an instruction to an operator rather
// than a public claim, so this gate reads every document instead.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { sentencesOf } from './claims-check.mjs';

export const APPLE_ANSWERS = 'store/appstore/app-privacy-answers.md';
export const PLAY_ANSWERS = 'store/play/data-safety-answers.md';
export const SCHEMA = 'apps/api/prisma/schema.prisma';

// Documents that may restate a store label. Directories are walked.
export const SCANNED = ['README.md', 'docs', 'site', 'store'];
const TEXT_EXTENSIONS = /\.(md|txt|html)$/;

// What the server stores, and the label each store needs for it. `field`
// narrows a model to one of its fields.
export const REQUIRED_DECLARATIONS = [
  { model: 'User', stored: 'account ids and handles', apple: 'User ID', play: 'User IDs' },
  { model: 'Device', stored: 'device ids', apple: 'Device ID', play: 'Device or other IDs' },
  {
    model: 'Device',
    field: 'pushToken',
    stored: 'device push tokens',
    apple: 'Device ID',
    play: 'Device or other IDs',
  },
  {
    model: 'UserContact',
    stored: 'the in-app contact list (a social graph)',
    apple: 'Contacts',
    play: 'Contacts',
  },
  {
    model: 'CallRecord',
    stored: 'call records (call history)',
    apple: 'Contacts',
    play: 'Contacts',
  },
  {
    model: 'GroupMeta',
    field: 'name',
    stored: 'readable group names and descriptions',
    apple: 'Other User Content',
    play: 'Other user-generated content',
  },
  {
    model: 'ChannelMeta',
    field: 'name',
    stored: 'readable channel names and descriptions',
    apple: 'Other User Content',
    play: 'Other user-generated content',
  },
  {
    model: 'Device',
    field: 'deviceName',
    stored: 'readable device labels',
    apple: 'Other User Content',
    play: 'Other user-generated content',
  },
  {
    model: 'Message',
    stored: 'message ciphertext',
    apple: 'Other User Content',
    play: 'Other in-app messages',
  },
];

// Types both stores ask about, as [App Store type, Play type]. Both files must
// answer each one, and answer it the same way.
export const CROSS_STORE = [
  ['Contacts', 'Contacts'],
  ['User ID', 'User IDs'],
  ['Device ID', 'Device or other IDs'],
  ['Contact Info', 'Name'],
  ['Contact Info', 'Email address'],
  ['Contact Info', 'Phone number'],
  ['Contact Info', 'Address'],
  ['Location', 'Approximate location'],
  ['Location', 'Precise location'],
  ['Browsing History', 'Web browsing history'],
  ['Search History', 'In-app search history'],
  ['Usage Data', 'App interactions'],
  ['Purchases', 'Purchase history'],
  ['Crash Data', 'Crash logs'],
  ['Performance Data', 'Other app performance data'],
  ['Other Diagnostic Data', 'Diagnostics'],
];

// Other spellings of a declared type that documents use.
const ALIASES = {
  Contacts: [/연락처/],
  'Device or other IDs': [/\bdevice\s*(?:\/|or)\s*other\s*ids?\b/i],
};

// Saying something is not collected.
const NEGATION =
  /\bnot\s+collected\b|\bdoes\s+not\s+collect\b|\bdo\s+not\s+collect\b|\bdo(?:es)?n['’]t\s+collect\b|\bnever\s+collect|수집하지\s*않/i;
// Framing the whole label as "Data Not Collected".
const BLANKET = [
  /\b(?:every|all)\b[^.]*\bdata not collected\b/i,
  /\bmaps?\s+to\s+data not collected\b/i,
];
// A sentence that summarises a store label.
const SUMMARY_CONTEXT =
  /\bdata collected\b|\bdata safety\b|\bapp privacy\b|\bnutrition label\b|\bprivacy label\b/i;
const NAMES_IDENTIFIERS = /\b(?:user|device)\s+ids?\b/i;
const NAMES_CONTACTS = /\bcontacts\b|연락처/i;
const NAMES_LINKED_CONTENT =
  /\bother user content\b|\buser[- ]generated content\b|\bgroup and channel names\b/i;

const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Emphasis, code spans and quotes do not change what a sentence says.
const plain = (text) => text.replace(/[*_`"“”]/g, '');

/** The App Store answers: which types and categories are collected. */
export function parseAppleAnswers(source) {
  const collected = new Set();
  const notCollected = new Set();
  const categoryCollected = new Map();
  let category = null;
  for (const raw of source.split('\n')) {
    const line = raw.trim();
    const heading = /^(#{2,6})\s+(.+?)\s*$/.exec(line);
    if (heading) {
      category = heading[1].length >= 3 ? heading[2] : null;
      continue;
    }
    if (category === null || !line.startsWith('- ')) continue;
    const item = line.slice(2).trim();
    if (/^data not collected$/i.test(category)) {
      notCollected.add(item.replace(/\s*\(.*\)$/, ''));
      continue;
    }
    const typed = /^\*\*([^*]+)\*\*(?:\s*\([^)]*\))?:\s*(not collected|collected)\b/i.exec(item);
    if (typed) {
      const isCollected = typed[2].toLowerCase() === 'collected';
      (isCollected ? collected : notCollected).add(typed[1].trim());
      categoryCollected.set(category, (categoryCollected.get(category) ?? false) || isCollected);
      continue;
    }
    const whole = /^Collected:\s*\*\*(Yes|No)\*\*/i.exec(item);
    if (whole) {
      const isCollected = whole[1].toLowerCase() === 'yes';
      categoryCollected.set(category, (categoryCollected.get(category) ?? false) || isCollected);
    }
  }
  const categories = new Set();
  for (const [name, isCollected] of categoryCollected) {
    if (!collected.has(name) && !notCollected.has(name)) categories.add(name);
    (isCollected ? collected : notCollected).add(name);
  }
  return { collected, notCollected, categories };
}

/** The Play answers: the "Data type" and "Collected" columns of their tables. */
export function parsePlayAnswers(source) {
  const collected = new Set();
  const notCollected = new Set();
  let columns = null;
  for (const raw of source.split('\n')) {
    const line = raw.trim();
    if (!line.startsWith('|')) {
      columns = null;
      continue;
    }
    const cells = line
      .replace(/^\||\|$/g, '')
      .split('|')
      .map((cell) => plain(cell).trim());
    if (cells.every((cell) => /^:?-+:?$/.test(cell))) continue;
    if (columns === null) {
      columns = cells.map((cell) => cell.toLowerCase());
      continue;
    }
    const typeColumn = columns.indexOf('data type');
    const collectedColumn = columns.indexOf('collected');
    if (typeColumn < 0 || collectedColumn < 0) continue;
    const answer = cells[collectedColumn] ?? '';
    if (/^yes\b/i.test(answer)) collected.add(cells[typeColumn]);
    else if (/^no\b/i.test(answer)) notCollected.add(cells[typeColumn]);
  }
  return { collected, notCollected };
}

const modelBody = (schema, model) => {
  const match = new RegExp(`^model ${escapeRegExp(model)}\\s*\\{([\\s\\S]*?)^\\}`, 'm').exec(
    schema,
  );
  return match ? match[1] : null;
};

const answerOf = ({ collected, notCollected }, name) =>
  collected.has(name) ? 'collected' : notCollected.has(name) ? 'not collected' : 'unanswered';

/** The schema and the two answers files against each other. */
export function checkAnswers(schema, apple, play) {
  const failures = [];
  for (const [label, answers, path] of [
    ['App Store', apple, APPLE_ANSWERS],
    ['Play', play, PLAY_ANSWERS],
  ]) {
    if (answers.collected.size + answers.notCollected.size === 0) {
      failures.push(`${path}: no ${label} answers found`);
    }
    for (const name of answers.collected) {
      if (answers.notCollected.has(name)) {
        failures.push(`${path}: declares "${name}" both collected and not collected`);
      }
    }
  }
  for (const declaration of REQUIRED_DECLARATIONS) {
    const body = modelBody(schema, declaration.model);
    if (body === null) continue;
    if (
      declaration.field !== undefined &&
      !new RegExp(`^\\s*${escapeRegExp(declaration.field)}\\s`, 'm').test(body)
    ) {
      continue;
    }
    const where = declaration.field
      ? `${declaration.model}.${declaration.field}`
      : `model ${declaration.model}`;
    if (!apple.collected.has(declaration.apple)) {
      failures.push(
        `${APPLE_ANSWERS}: the server stores ${declaration.stored} (${where}), so "${declaration.apple}" must be declared collected (it is ${answerOf(apple, declaration.apple)})`,
      );
    }
    if (!play.collected.has(declaration.play)) {
      failures.push(
        `${PLAY_ANSWERS}: the server stores ${declaration.stored} (${where}), so "${declaration.play}" must be declared collected (it is ${answerOf(play, declaration.play)})`,
      );
    }
  }
  for (const [appleName, playName] of CROSS_STORE) {
    const appleAnswer = answerOf(apple, appleName);
    const playAnswer = answerOf(play, playName);
    if (appleAnswer === 'unanswered') {
      failures.push(`${APPLE_ANSWERS}: does not answer "${appleName}"`);
    }
    if (playAnswer === 'unanswered') {
      failures.push(`${PLAY_ANSWERS}: does not answer "${playName}"`);
    }
    if (appleAnswer !== 'unanswered' && playAnswer !== 'unanswered' && appleAnswer !== playAnswer) {
      failures.push(
        `the stores disagree: App Store "${appleName}" is ${appleAnswer}, Play "${playName}" is ${playAnswer}`,
      );
    }
  }
  return failures;
}

/**
 * One matcher per type that either store declares as collected. A category
 * name ("Identifiers") counts only where it heads an entry or clause, as in
 * "Identifiers — handle only": "advertising identifiers" names something else.
 */
export function collectedTerms(apple, play) {
  const names = [...new Set([...apple.collected, ...play.collected])];
  return names.map((name) => {
    const words = escapeRegExp(name).replace(/\s+/g, '\\s+');
    const head = apple.categories?.has(name) ? '^[^\\p{L}\\p{N}]*' : '(?<![\\w-])';
    return {
      name,
      patterns: [new RegExp(`${head}${words}(?![\\w-])`, 'iu'), ...(ALIASES[name] ?? [])],
    };
  });
}

const termsIn = (text, terms) =>
  terms.filter(({ patterns }) => patterns.some((pattern) => pattern.test(text)));

// Clauses run between sentence ends and parentheses, so "Contacts: collected
// (the phone's address book is not collected)" declares Contacts collected.
const clauses = (sentence) => sentence.split(/[.!?()]/);

// "Contacts: collected" and "Contacts are collected" affirm, whatever follows.
const affirmedRightAfter = (clause, patterns) =>
  patterns.some((pattern) => {
    const match = pattern.exec(clause);
    if (!match) return false;
    const rest = clause.slice(match.index + match[0].length);
    return /^[\s:—–-]*(?:(?:is|are)\s+)?collected\b/i.test(rest);
  });

/** Problems in one sentence of a document. */
export function sentenceProblems(sentence, terms) {
  const text = plain(sentence);
  const problems = [];
  if (BLANKET.some((pattern) => pattern.test(text))) {
    problems.push('frames the label as "Data Not Collected" throughout');
  }
  for (const clause of clauses(text)) {
    if (!NEGATION.test(clause)) continue;
    for (const term of termsIn(clause, terms)) {
      if (!affirmedRightAfter(clause, term.patterns)) {
        problems.push(`says "${term.name}" is not collected`);
      }
    }
  }
  if (
    SUMMARY_CONTEXT.test(text) &&
    NAMES_IDENTIFIERS.test(text) &&
    !(NAMES_CONTACTS.test(text) && NAMES_LINKED_CONTENT.test(text))
  ) {
    problems.push(
      'summarises the label with the identifiers but without Contacts and the linked user content',
    );
  }
  return problems;
}

// HTML lists and headings, as Markdown, for the list rules below. Line by
// line, so that a failure names the line of the HTML source.
const htmlAsMarkdown = (html) =>
  html
    .replace(/<(script|style)\b[\s\S]*?<\/\1>|<!--[\s\S]*?-->/gi, (block) =>
      block.replace(/[^\n]/g, ''),
    )
    .split('\n')
    .map((line) =>
      line
        .replace(/^\s*<li\b[^>]*>/i, '- ')
        .replace(/^\s*<h([1-6])\b[^>]*>/i, (_, level) => `${'#'.repeat(Number(level))} `)
        .replace(/<[^>]+>/g, '')
        .replace(/&nbsp;/g, ' ')
        .replace(/&amp;/g, '&'),
    )
    .join('\n');

const LIST_ITEM = /^\s*(?:[-*+•]|\d+\.)\s+(.*)$/;
const HEADING = /^\s{0,3}#{1,6}\s+(.*)$/;

/**
 * List items that sit under a "not collected" heading or lead-in ("The
 * service does not collect:"), and table rows whose "Collected" column says
 * no, each with its line number.
 */
export function negatedEntries(source, path) {
  const text = path.endsWith('.html') ? htmlAsMarkdown(source) : source;
  const lines = text.split('\n');
  const entries = [];
  let section = false;
  let leadIn = false;
  let item = null;
  let columns = null;
  const flush = () => {
    if (item && (section || leadIn)) entries.push(item);
    item = null;
  };
  lines.forEach((line, index) => {
    const number = index + 1;
    if (/^\s*\|/.test(line)) {
      flush();
      const cells = line
        .trim()
        .replace(/^\||\|$/g, '')
        .split('|')
        .map((cell) => plain(cell).trim());
      if (cells.every((cell) => /^:?-+:?$/.test(cell))) return;
      if (columns === null) {
        columns = cells.map((cell) => cell.toLowerCase().replace(/\?$/, ''));
        return;
      }
      const collectedColumn = columns.indexOf('collected');
      if (collectedColumn > 0 && /^no\b/i.test(cells[collectedColumn] ?? '')) {
        entries.push({ text: cells[0], line: number });
      }
      return;
    }
    columns = null;
    const heading = HEADING.exec(line);
    if (heading) {
      flush();
      section = NEGATION.test(plain(heading[1])) || /data not collected/i.test(heading[1]);
      leadIn = false;
      return;
    }
    if (line.trim() === '') return;
    const listItem = LIST_ITEM.exec(line);
    if (listItem) {
      flush();
      item = { text: listItem[1], line: number };
      return;
    }
    if (item && /^\s+\S/.test(line)) {
      item.text += ` ${line.trim()}`;
      return;
    }
    flush();
    leadIn = NEGATION.test(plain(line)) && /[:：.]\s*$/.test(line.trim());
  });
  flush();
  return entries;
}

const filesUnder = (rootDir, target) => {
  const absolute = join(rootDir, target);
  if (!existsSync(absolute)) return [];
  if (statSync(absolute).isFile()) return [target];
  return readdirSync(absolute, { withFileTypes: true }).flatMap((entry) =>
    filesUnder(rootDir, join(target, entry.name)),
  );
};

export function checkStoreLabels(rootDir, { scanned = SCANNED } = {}) {
  const read = (path) => readFileSync(join(rootDir, path), 'utf8');
  for (const path of [APPLE_ANSWERS, PLAY_ANSWERS, SCHEMA]) {
    if (!existsSync(join(rootDir, path))) return [`${path} does not exist`];
  }
  const apple = parseAppleAnswers(read(APPLE_ANSWERS));
  const play = parsePlayAnswers(read(PLAY_ANSWERS));
  const failures = checkAnswers(read(SCHEMA), apple, play);
  const terms = collectedTerms(apple, play);

  const documents = scanned
    .flatMap((target) => filesUnder(rootDir, target))
    .map((path) => path.split(sep).join('/'))
    .filter((path) => TEXT_EXTENSIONS.test(path))
    .filter((path) => path !== APPLE_ANSWERS && path !== PLAY_ANSWERS);
  for (const path of documents) {
    const source = read(path);
    for (const sentence of sentencesOf(source, path)) {
      for (const problem of sentenceProblems(sentence, terms)) {
        failures.push(`${path}: ${problem}: "${sentence}"`);
      }
    }
    for (const entry of negatedEntries(source, path)) {
      for (const term of termsIn(plain(entry.text), terms)) {
        failures.push(
          `${path}:${entry.line}: lists "${term.name}" as not collected, but the store answers declare it collected`,
        );
      }
    }
  }
  return [...new Set(failures)];
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  const rootDir = fileURLToPath(new URL('..', import.meta.url));
  const failures = checkStoreLabels(rootDir);
  if (failures.length > 0) {
    console.error('Store label check failed:');
    for (const failure of failures) console.error(`  ${failure}`);
    console.error(
      `Declare data once, in ${APPLE_ANSWERS} and ${PLAY_ANSWERS}, and point other documents there.`,
    );
    process.exit(1);
  }
  console.log('Store label check passed.');
}
