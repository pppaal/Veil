// Every string the mobile app shows comes from AppLocalizations
// (apps/mobile/lib/src/l10n/app_en.arb and app_ko.arb). This gate reads the
// Dart files that build UI text and fails when one holds a user-facing
// string literal instead of a lookup, so a screen cannot ship English to a
// Korean user (or the reverse) in a state no render test opens: a toast, a
// dialog, an error.
//
// What it reads (UI_SOURCES): every presentation folder of a feature (the
// screens and the labels and logic files next to them), the shared
// components, the app shell and router, and the error formatter whose output
// screens show.
//
// What counts as user-facing: a string literal with a word in it (two Latin
// letters in a row, or any other letter such as Hangul) once its
// interpolations and escapes are taken out, unless the code says it is not
// text for a person: a route path, a widget key, a map or JSON key, a value
// compared or switched on, a date or number pattern, a regular expression,
// an exception or log message, an import, or a token shaped like an
// identifier, a file name or a MIME type. A literal whose only words are
// written the same in every language (NOT_TRANSLATED: the brand, platform
// names, units) is left alone too. No comment silences a finding: a literal
// is either one of these or it moves to the ARB files.
//
// Files that fail today are listed in KNOWN_HARDCODED with the number of
// literals they hold. The list only shrinks: a file with more literals than
// listed fails, and so does one with fewer (lower its number, or remove its
// line at zero), so a fixed file cannot quietly gain a literal back.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const MOBILE_SRC = 'apps/mobile/lib/src';

/** Whether [path] (relative to MOBILE_SRC, with forward slashes) builds UI text. */
export const isUiSource = (path) =>
  /^features\/[^/]+\/presentation\/.+\.dart$/.test(path) ||
  /^shared\/presentation\/.+\.dart$/.test(path) ||
  /^app\/.+\.dart$/.test(path) ||
  path === 'core/errors/user_facing_error.dart';

/**
 * Words that are written the same in every language. A literal made only of
 * these (and interpolations and punctuation) has nothing to translate.
 */
export const NOT_TRANSLATED = new Set([
  // The product's name.
  'VEIL',
  // Platform names: trademarks.
  'Android',
  'iPhone',
  'iPad',
  'iOS',
  'macOS',
  'Windows',
  'Linux',
  // Units and the name of a time zone.
  'KB',
  'MB',
  'GB',
  'TB',
  'UTC',
]);

// Today's hard-coded literals, by file (relative to MOBILE_SRC) and grouped
// by who owns the screen. To fix a file: move its strings to app_en.arb and
// app_ko.arb, then lower its number here to what the gate reports, or delete
// its line when none is left. Never raise a number and never add a line.
export const KNOWN_HARDCODED = {
  // --- Onboarding, account and device transfer.
  'features/device_transfer/presentation/device_transfer_screen.dart': 2,

  // --- Chat and conversation list, starting a chat or a group.
  'features/conversations/presentation/start_group_screen.dart': 2,

  // --- Settings, security status, safety numbers, contacts, one-time link.
  'features/settings/presentation/settings_screen.dart': 3,

  // --- Switched-off surfaces (calls, media picker, voice recorder, sticker
  // picker, assistant, stories): whoever switches one on localizes it first.
  'features/ai/presentation/ai_chat_screen.dart': 21,
  'features/calls/presentation/call_screen.dart': 10,
  'features/media/presentation/media_picker_screen.dart': 13,
  'features/stickers/presentation/sticker_picker_screen.dart': 20,
  'features/stories/presentation/stories_screen.dart': 24,
  'features/stories/presentation/story_viewer_screen.dart': 14,
  'features/voice/presentation/voice_recorder_screen.dart': 9,

  // --- The error formatter. Its sentences reach the screens as ready-made
  // English; they need codes the screens can translate.
  'core/errors/user_facing_error.dart': 13,
};

// --- A Dart lexer that knows strings, comments and brackets. It does not
// parse Dart; it finds every string literal and what stands around it.

// Stands for an interpolation in the text of a string token: a character no
// source file holds.
const HOLE = String.fromCharCode(0xfffc);

const IDENT_START = /[A-Za-z_$]/;
const IDENT_PART = /[A-Za-z0-9_$]/;

/**
 * Tokens of [source] from [start] until the unmatched `}` that closes an
 * interpolation (when [inInterpolation]) or the end. Returns the tokens and
 * the index after the last character read.
 *
 * A string token carries `text` (its literal characters, with every
 * interpolation replaced by HOLE and every escape by a space), `raw`, and
 * `nested` (the token lists of its `${...}` interpolations).
 */
export function lexDart(source, start = 0, inInterpolation = false, startLine = 1) {
  const tokens = [];
  let i = start;
  let line = startLine;
  let depth = 0;

  const readString = () => {
    const tokenLine = line;
    let raw = false;
    if (source[i] === 'r') {
      raw = true;
      i += 1;
    }
    const quote = source[i];
    const triple = source.startsWith(quote.repeat(3), i);
    const close = triple ? quote.repeat(3) : quote;
    i += close.length;
    let text = '';
    const nested = [];
    while (i < source.length && !source.startsWith(close, i)) {
      const char = source[i];
      if (char === '\n') line += 1;
      if (!raw && char === '\\') {
        const unicode = /^\\u(?:\{[0-9A-Fa-f]+\}|[0-9A-Fa-f]{4})|^\\x[0-9A-Fa-f]{2}/.exec(
          source.slice(i, i + 12),
        );
        i += unicode ? unicode[0].length : 2;
        text += ' ';
      } else if (!raw && char === '$') {
        if (source[i + 1] === '{') {
          const inner = lexDart(source, i + 2, true, line);
          nested.push(inner.tokens);
          line = inner.line;
          i = inner.end + 1;
          text += HOLE;
        } else if (IDENT_START.test(source[i + 1] ?? '')) {
          i += 1;
          while (i < source.length && IDENT_PART.test(source[i]) && source[i] !== '$') i += 1;
          text += HOLE;
        } else {
          text += char;
          i += 1;
        }
      } else {
        text += char;
        i += 1;
      }
    }
    i += close.length;
    tokens.push({ type: 'string', text, raw, nested, line: tokenLine });
  };

  while (i < source.length) {
    const char = source[i];
    if (char === '\n') {
      line += 1;
      i += 1;
    } else if (/\s/.test(char)) {
      i += 1;
    } else if (source.startsWith('//', i)) {
      while (i < source.length && source[i] !== '\n') i += 1;
    } else if (source.startsWith('/*', i)) {
      // Block comments nest in Dart.
      let open = 1;
      i += 2;
      while (i < source.length && open > 0) {
        if (source.startsWith('/*', i)) {
          open += 1;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          open -= 1;
          i += 2;
        } else {
          if (source[i] === '\n') line += 1;
          i += 1;
        }
      }
    } else if (char === "'" || char === '"' || (char === 'r' && /['"]/.test(source[i + 1] ?? ''))) {
      readString();
    } else if (IDENT_START.test(char)) {
      let end = i + 1;
      while (end < source.length && IDENT_PART.test(source[end])) end += 1;
      tokens.push({ type: 'word', text: source.slice(i, end), line });
      i = end;
    } else if (/[0-9]/.test(char)) {
      let end = i + 1;
      while (end < source.length && /[0-9A-Za-z_.]/.test(source[end])) end += 1;
      tokens.push({ type: 'number', text: source.slice(i, end), line });
      i = end;
    } else {
      if (inInterpolation && char === '}' && depth === 0) return { tokens, end: i, line };
      if (char === '{') depth += 1;
      if (char === '}') depth -= 1;
      const operator = /^(?:=>|==|!=|\?\?=?|\?\.|\.\.\.\??|\.\.|&&|\|\||<=|>=)/.exec(
        source.slice(i, i + 4),
      );
      const text = operator ? operator[0] : char;
      tokens.push({ type: 'punct', text, line });
      i += text.length;
    }
  }
  return { tokens, end: i, line };
}

// Calls whose string arguments are not text for a person: keys, patterns,
// errors and logs, lookups by name.
const NON_UI_CALLEES = new Set([
  'Key',
  'ValueKey',
  'ObjectKey',
  'PageStorageKey',
  'GlobalObjectKey',
  'RegExp',
  'DateFormat',
  'NumberFormat',
  'StateError',
  'ArgumentError',
  'Exception',
  'FormatException',
  'UnsupportedError',
  'UnimplementedError',
  'AssertionError',
  'FlutterError',
  'assert',
  'debugPrint',
  'print',
  'log',
  'fromEnvironment',
  'MethodChannel',
  'EventChannel',
  'Locale',
  'startsWith',
  'endsWith',
  'contains',
  'parse',
  'tryParse',
  'Uri',
]);

// Named arguments that take an identifier, not text.
const NON_UI_ARGUMENTS = new Set([
  'path',
  'key',
  'fontFamily',
  'debugLabel',
  'restorationId',
  'restorationScopeId',
  'heroTag',
  'package',
  'initialLocation',
  'identifier',
]);

const DIRECTIVES = new Set(['import', 'export', 'part', 'library']);

// What a string looks like when it names something for the program: a
// lower-case token, or lower-case tokens joined by - _ . / : = (a key, a
// route, a file name, a MIME type, a wire value), interpolations included.
const IDENTIFIER_SHAPE = new RegExp(`^[./]?[a-z0-9${HOLE}]+(?:[-_./:=?&][a-z0-9${HOLE}]+)*$`);
const ROUTE_SHAPE = /^\/[^\s]*$/;

// The words of a literal: runs of two or more Latin letters, and any run of
// other letters (Hangul above all).
const wordsOf = (text) => text.match(/[A-Za-z]{2,}|[^\P{L}A-Za-z]+/gu) ?? [];

/**
 * The user-facing string literals of one Dart file, as `{ line, text }`.
 * Adjacent literals (Dart joins them) count as one.
 */
export function hardcodedStrings(source) {
  const found = [];
  scan(lexDart(source).tokens, found);
  return found;
}

function scan(tokens, found) {
  // One frame per open bracket: the call it belongs to, and the argument
  // the cursor is in.
  const frames = [];
  let statementStart = 0;

  const calleeBefore = (index) => {
    let at = index - 1;
    // Generic arguments: ValueKey<String>(...)
    if (tokens[at]?.text === '>') {
      let open = 1;
      at -= 1;
      while (at >= 0 && open > 0) {
        if (tokens[at].text === '>') open += 1;
        if (tokens[at].text === '<') open -= 1;
        at -= 1;
      }
    }
    const name = tokens[at];
    if (name?.type !== 'word') return { name: null, annotation: false };
    let first = at;
    while (
      first >= 2 &&
      /^(?:\.|\?\.)$/.test(tokens[first - 1].text) &&
      tokens[first - 2].type === 'word'
    ) {
      first -= 2;
    }
    return { name: name.text, annotation: tokens[first - 1]?.text === '@' };
  };

  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    const top = frames[frames.length - 1];

    if (token.type === 'punct') {
      if (token.text === '(') {
        frames.push({ kind: 'call', ...calleeBefore(index), argStart: index + 1 });
      } else if (token.text === '[') {
        const before = tokens[index - 1];
        const indexes =
          before !== undefined &&
          (before.type === 'word'
            ? !/^(?:return|case|in|is|as|const)$/.test(before.text)
            : /^[)\]!?]$/.test(before.text));
        frames.push({ kind: indexes ? 'index' : 'list', argStart: index + 1 });
      } else if (token.text === '{') {
        frames.push({ kind: 'brace', argStart: index + 1 });
        statementStart = index + 1;
      } else if (/^[)\]}]$/.test(token.text)) {
        frames.pop();
        if (token.text === '}') statementStart = index + 1;
      } else if (token.text === ',') {
        if (top) top.argStart = index + 1;
      } else if (token.text === ';') {
        statementStart = index + 1;
      }
      continue;
    }
    if (token.type !== 'string') continue;

    // Dart joins adjacent literals into one string.
    let last = index;
    while (tokens[last + 1]?.type === 'string') last += 1;
    const parts = tokens.slice(index, last + 1);
    const text = parts.map((part) => part.text).join('');
    const previous = tokens[index - 1];
    const next = tokens[last + 1];
    index = last;

    for (const part of parts) {
      for (const nested of part.nested) scan(nested, found);
    }

    if (parts.some((part) => part.raw)) continue;
    const words = wordsOf(text);
    if (words.length === 0 || words.every((word) => NOT_TRANSLATED.has(word))) continue;
    const trimmed = text.trim();
    if (IDENTIFIER_SHAPE.test(trimmed) || ROUTE_SHAPE.test(trimmed)) continue;

    // import 'x'; export 'x' show ...; part 'x';
    if (DIRECTIVES.has(tokens[statementStart]?.text)) continue;
    // Compared with, or switched on.
    if (
      /^(?:==|!=|case|\|)$/.test(previous?.text ?? '') ||
      /^(?:==|!=|=>|\|)$/.test(next?.text ?? '')
    )
      continue;
    if (top?.kind === 'index') continue;
    // The key of a map literal.
    if (top?.kind === 'brace' && next?.text === ':' && /^[{,]$/.test(previous?.text ?? ''))
      continue;
    if (top?.kind === 'call') {
      if (top.annotation || NON_UI_CALLEES.has(top.name)) continue;
      const argument = tokens[top.argStart];
      if (
        argument?.type === 'word' &&
        tokens[top.argStart + 1]?.text === ':' &&
        NON_UI_ARGUMENTS.has(argument.text)
      ) {
        continue;
      }
    }
    found.push({ line: parts[0].line, text: trimmed.replaceAll(HOLE, '…').replace(/\s+/g, ' ') });
  }
}

const dartFilesUnder = (dir) =>
  readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return dartFilesUnder(path);
    return entry.name.endsWith('.dart') ? [path] : [];
  });

/** Every UI source under [rootDir] with its user-facing literals. */
export function scanUiSources(rootDir) {
  const base = join(rootDir, MOBILE_SRC);
  const results = new Map();
  if (!existsSync(base)) return results;
  for (const file of dartFilesUnder(base)) {
    const path = file
      .slice(base.length + 1)
      .split(sep)
      .join('/');
    if (!isUiSource(path)) continue;
    if (/\.(?:g|freezed)\.dart$/.test(path)) continue;
    results.set(path, hardcodedStrings(readFileSync(file, 'utf8')));
  }
  return results;
}

/** The gate: failures as lines of text, empty when it passes. */
export function checkUiStrings(rootDir, known = KNOWN_HARDCODED) {
  const failures = [];
  const results = scanUiSources(rootDir);
  if (results.size === 0) failures.push(`no UI sources found under ${MOBILE_SRC}`);

  for (const [path, strings] of results) {
    const allowed = known[path] ?? 0;
    if (strings.length > allowed) {
      const what =
        allowed === 0
          ? 'holds user-facing string literals'
          : `holds ${strings.length} user-facing string literals, ${strings.length - allowed} more than the ${allowed} listed`;
      failures.push(
        `${MOBILE_SRC}/${path} ${what}; move them to app_en.arb and app_ko.arb and read them from AppLocalizations:\n` +
          strings
            .map((found) => `    line ${found.line}: ${JSON.stringify(found.text)}`)
            .join('\n'),
      );
    } else if (strings.length < allowed) {
      failures.push(
        `${MOBILE_SRC}/${path} now holds ${strings.length} user-facing string literals, not ${allowed}: ` +
          (strings.length === 0
            ? 'remove its line from KNOWN_HARDCODED'
            : `lower its number in KNOWN_HARDCODED to ${strings.length}`) +
          ' (scripts/mobile-ui-strings-check.mjs)',
      );
    }
  }
  for (const path of Object.keys(known)) {
    if (!results.has(path)) {
      failures.push(
        `KNOWN_HARDCODED lists ${path}, which is not a UI source under ${MOBILE_SRC}; remove the line`,
      );
    }
  }
  return failures;
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  const rootDir = join(fileURLToPath(new URL('.', import.meta.url)), '..');
  if (process.argv.includes('--list')) {
    // Every finding, listed or not: what a number in KNOWN_HARDCODED stands for.
    for (const [path, strings] of scanUiSources(rootDir)) {
      if (strings.length === 0) continue;
      console.log(`${path}: ${strings.length}`);
      for (const found of strings)
        console.log(`    line ${found.line}: ${JSON.stringify(found.text)}`);
    }
  } else {
    const failures = checkUiStrings(rootDir);
    if (failures.length > 0) {
      console.error('Mobile UI strings check failed:');
      for (const failure of failures) console.error(`- ${failure}`);
      process.exit(1);
    }
    const listed = Object.values(KNOWN_HARDCODED).reduce((sum, count) => sum + count, 0);
    console.log(
      `Mobile UI strings check passed: no user-facing string literal outside the ARB files` +
        (listed > 0
          ? `, except the ${listed} known in ${Object.keys(KNOWN_HARDCODED).length} files (KNOWN_HARDCODED).`
          : '.'),
    );
  }
}
