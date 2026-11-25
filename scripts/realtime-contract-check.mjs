// Fails when the mobile client's realtime event list drifts from the
// contract. A server event the client does not subscribe to is silently
// lost (this is how group.key.distribution went unheard), so every key of
// RealtimeEventMap must appear in kRealtimeEventNames, and nothing else may.
import { readFileSync } from 'node:fs';

const contractPath = new URL('../packages/contracts/src/index.ts', import.meta.url);
const dartPath = new URL(
  '../apps/mobile/lib/src/core/realtime/realtime_events.dart',
  import.meta.url,
);

const stripComments = (source) =>
  source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|\s)\/\/.*$/gm, '$1');

// Returns the text between the brace that follows `anchor` and its match.
const bracedBody = (source, anchor, label) => {
  const start = source.indexOf(anchor);
  if (start === -1) {
    throw new Error(`${label}: could not find "${anchor}"`);
  }
  const open = source.indexOf('{', start + anchor.length);
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    if (source[i] === '}') depth -= 1;
    if (depth === 0) {
      return source.slice(open + 1, i);
    }
  }
  throw new Error(`${label}: unbalanced braces after "${anchor}"`);
};

// Index of the quote closing the single-quoted string opened at `start`.
const closingQuote = (source, start) => {
  for (let i = start + 1; i < source.length; i += 1) {
    if (source[i] === '\\') i += 1;
    else if (source[i] === "'") return i;
  }
  throw new Error(`unterminated string at offset ${start}`);
};

// Quoted keys at the top level of an object body ('a.b': ...). Quoted
// values and anything nested in braces are skipped.
const topLevelKeys = (body) => {
  const keys = [];
  let depth = 0;
  for (let i = 0; i < body.length; i += 1) {
    const char = body[i];
    if (char === '{') depth += 1;
    else if (char === '}') depth -= 1;
    else if (char === "'") {
      const end = closingQuote(body, i);
      if (depth === 0 && /^\s*:/.test(body.slice(end + 1))) {
        keys.push(body.slice(i + 1, end));
      }
      i = end;
    }
  }
  return keys;
};

const duplicates = (values) => values.filter((value, index) => values.indexOf(value) !== index);

const contractSource = stripComments(readFileSync(contractPath, 'utf8'));
const dartSource = stripComments(readFileSync(dartPath, 'utf8'));

const contractEvents = topLevelKeys(
  bracedBody(contractSource, 'export interface RealtimeEventMap', 'contract'),
);
const dartEvents = [
  ...bracedBody(dartSource, 'const kRealtimeEventNames', 'mobile').matchAll(/'([^']+)'/g),
].map((match) => match[1]);
const ignoredEvents = topLevelKeys(
  bracedBody(dartSource, 'const kIgnoredRealtimeEvents', 'mobile ignore list'),
);

const failures = [];
const contractSet = new Set(contractEvents);
const dartSet = new Set(dartEvents);

if (contractEvents.length === 0) {
  failures.push('RealtimeEventMap has no keys; the parser no longer understands the contract');
}
for (const event of contractEvents) {
  if (!dartSet.has(event)) {
    failures.push(`contract event missing from kRealtimeEventNames: ${event}`);
  }
}
for (const event of dartEvents) {
  if (!contractSet.has(event)) {
    failures.push(`kRealtimeEventNames lists an event the contract does not define: ${event}`);
  }
}
for (const event of ignoredEvents) {
  if (!dartSet.has(event)) {
    failures.push(`kIgnoredRealtimeEvents lists an event outside kRealtimeEventNames: ${event}`);
  }
}
for (const event of duplicates(contractEvents)) {
  failures.push(`RealtimeEventMap defines ${event} more than once`);
}
for (const event of duplicates(dartEvents)) {
  failures.push(`kRealtimeEventNames lists ${event} more than once`);
}

if (failures.length > 0) {
  console.error('Realtime contract check failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log(
  `Realtime contract check passed: ${contractEvents.length} events, ` +
    `${contractEvents.length - ignoredEvents.length} typed on mobile, ${ignoredEvents.length} ignored.`,
);
