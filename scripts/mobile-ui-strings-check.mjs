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
// an exception or log message, an import, a URL, or a token shaped like an
// identifier, a file name or a MIME type. A literal whose only words are
// written the same in every language (NOT_TRANSLATED: the brand, platform
// names, units) is left alone too. Where the code says a literal is text on
// screen (the argument of Text, a label, a title, a tooltip: TEXT_CALLEES
// and TEXT_ARGUMENTS) its shape does not excuse it: Text('send') is a
// finding although 'send' alone looks like an identifier.
//
// No comment silences a finding. A literal the gate takes for text that is
// not the app's copy (an example handle in a hint, a storage key the shape
// rules do not know) goes into NOT_COPY, by file and text, with the reason:
// that list is read in review, and a line whose literal is gone fails.
//
// The literals that are copy and are still hard-coded today are listed in
// KNOWN_HARDCODED, by file and text. The list only shrinks: a literal that
// is not listed fails, and so does a listed one the file no longer holds
// (remove its line), so a fixed file cannot quietly gain a literal back,
// and one literal cannot be swapped for another.
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

// What the gate takes for text and is not the app's copy: by file (relative
// to MOBILE_SRC), each literal as the gate prints it, with why nobody
// translates it. Every occurrence of the literal in that file is left
// alone. Add a line only for what is not copy, and say why; a sentence the
// app wrote belongs in both ARB files. A line whose literal the file no
// longer holds fails.
export const NOT_COPY = {
  'features/attachments/presentation/attachment_preview_screen.dart': {
    'dossier.enc': 'the file name the placeholder attachment goes out under; a file name is data',
  },
  'features/contacts/presentation/contact_sheets.dart': {
    icarus: "an example handle in the field's hint; a handle is lower-case Latin by rule",
  },
  'features/conversations/presentation/start_direct_chat_screen.dart': {
    icarus: "an example handle in the field's hint; a handle is lower-case Latin by rule",
  },
  'features/conversations/presentation/start_group_screen.dart': {
    'icarus, daedalus, minos':
      "example handles in the field's hint; a handle is lower-case Latin by rule",
  },
};

// Today's hard-coded copy, by file (relative to MOBILE_SRC) and grouped by
// who owns the screen: each literal as the gate prints it (`--list`), once
// per occurrence. To fix a file: move its strings to app_en.arb and
// app_ko.arb and delete their lines here, and the file's entry with the
// last of them. Never add a line.
export const KNOWN_HARDCODED = {
  // --- Onboarding, account and device transfer.

  // --- Chat and conversation list, starting a chat or a group.

  // --- Settings, security status, safety numbers, contacts, one-time link.

  // --- Switched-off surfaces (calls, media picker, voice recorder, sticker
  // picker, assistant, stories): whoever switches one on localizes it first.
  'features/ai/presentation/ai_chat_screen.dart': [
    'This is a scripted preview of VEIL Assistant. It answers a few privacy and security questions from fixed replies, and the whole conversation stays on this device.',
    'VEIL Assistant',
    'Clear conversation',
    'Messages',
    'Model',
    'Scripted',
    'Privacy',
    'Local',
    'Ask anything',
    'Start a conversation with the VEIL assistant.',
    'Ask about privacy, security, or VEIL features.',
    'Thinking',
    'Ask',
    'You',
    'VEIL Assistant',
    'Thinking...',
    'VEIL has no backup and no account recovery. Messages are encrypted on this device before they reach the relay.',
    'Moving to a new device needs your old device to approve it. There is no cloud recovery path, by design.',
    'Group messages are encrypted on the sending device before they reach the relay.',
    'Calls in this build are a preview screen only. No audio or video connection is made yet.',
    'This is a scripted demo with a few fixed replies. Nothing you type here leaves this device.',
  ],
  'features/calls/presentation/call_screen.dart': [
    'Calling',
    'Ringing',
    'Connected …',
    'Call ended',
    'Calls are routed peer-to-peer when possible. Relay fallback is encrypted.',
    'Unmute',
    'Mute',
    'Speaker',
    'Video',
    'End',
  ],
  'features/media/presentation/media_picker_screen.dart': [
    'Camera access requires device permission',
    'Select at least one item to send',
    '… item(s) queued for encrypted upload',
    'Media',
    'Open camera',
    'ENCRYPTED MEDIA',
    'Send encrypted media',
    'Send encrypted media through the opaque relay. Files are sealed on-device before transmission.',
    'Media is encrypted locally before upload. The relay never sees plaintext.',
    '… selected',
    'Clear',
    'Select media to send',
    'Send … selected',
  ],
  'features/stickers/presentation/sticker_picker_screen.dart': [
    'Emoji',
    'Stickers',
    'GIFs',
    'Smileys',
    'People',
    'Animals',
    'Food',
    'Travel',
    'Objects',
    'Symbols',
    'Flags',
    'Selected …',
    'Stickers',
    'Search emoji and stickers',
    'RECENTLY USED',
    'ALL EMOJI',
    'Custom sticker packs',
    'Custom sticker packs coming soon. Stickers will be encrypted the same as all other media.',
    'GIF search',
    'GIF search requires external service integration. Privacy-preserving proxy under evaluation.',
  ],
  'features/stories/presentation/stories_screen.dart': [
    'New text story',
    'Text stories disappear after 24 hours. No media capture needed.',
    'What is going on?',
    'Posting',
    'Post story',
    'Story posted',
    'Failed to post story',
    'just now',
    '…m ago',
    '…h ago',
    '…d ago',
    'Photo moment',
    'Video clip',
    'Text update',
    'Stories',
    'Stories unavailable',
    'Stories expire after 24 hours. Content is stored locally until expiration.',
    'My Story',
    'No stories yet',
    'Stories from your contacts will appear here when they post.',
    'Recent stories',
    'Feed',
    '… views',
    'Add story',
  ],
  'features/stories/presentation/story_viewer_screen.dart': [
    'Story replies require messaging integration',
    'just now',
    '…m ago',
    '…h ago',
    '…d ago',
    'Unable to load stories',
    'No stories from this user',
    'Close',
    'Reply to story',
    'Send reply',
    'Empty story',
    'Video story',
    'Photo story',
    'Media rendering not yet connected',
  ],
  'features/voice/presentation/voice_recorder_screen.dart': [
    'Voice message encrypted and queued for relay',
    'Voice Message',
    'Voice data is encrypted on this device before relay.',
    'Tap to record',
    'Recording...',
    'Playing',
    'Tap to preview',
    'Cancel',
    'Send',
  ],

  // --- The error formatter. Its sentences reach the screens as ready-made
  // English; they need codes the screens can translate.
  'core/errors/user_facing_error.dart': [
    'This device no longer has a trusted VEIL session.',
    'Device transfer is available only while connected to the VEIL API.',
    'Register this new device first, then wait for approval from the old device.',
    'The relay returned an unexpected response. Try again.',
    'Opaque blob upload failed. Check the relay and try again.',
    'This session is no longer valid on this device.',
    'This action is not allowed on the current device.',
    'The requested VEIL resource was not found.',
    'This request conflicts with the current VEIL state. Refresh and try again.',
    'The submitted values were rejected. Review the form and try again.',
    'The VEIL relay failed to complete the request. Try again shortly.',
    'The VEIL API endpoint must use TLS outside local development.',
    'The VEIL realtime endpoint must use TLS outside local development.',
  ],
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
      tokens.push({ type: 'punct', text, line, start: i });
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
  'AssetImage',
]);

// Calls whose first argument names something for the program (a pattern to
// look for, a method of a platform channel, a key in a store); what follows
// it may be text.
const NON_UI_FIRST_ARGUMENT = new Set([
  'replaceAll',
  'replaceFirst',
  'split',
  'indexOf',
  'lastIndexOf',
  'invokeMethod',
  'invokeListMethod',
  'invokeMapMethod',
  'containsKey',
  'getString',
  'getBool',
  'getInt',
  'getDouble',
  'getStringList',
  'setString',
  'setBool',
  'setInt',
  'setDouble',
  'setStringList',
  'read',
  'write',
  'delete',
  'asset',
]);

// Where a literal is text on screen whatever it looks like: the first
// argument of these widgets, and these named arguments of any call.
const TEXT_CALLEES = new Set(['Text', 'SelectableText', 'VeilCopy', 'VeilSectionLabel']);
const TEXT_ARGUMENTS = new Set([
  'label',
  'labelText',
  'hintText',
  'helperText',
  'errorText',
  'title',
  'subtitle',
  'body',
  'message',
  'eyebrow',
  'caption',
  'detail',
  'tooltip',
  'semanticLabel',
  'semanticsLabel',
  'actionLabel',
  'confirmVerb',
  'titleIconLabel',
  'placeholder',
  'description',
  'text',
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
  'tag',
]);

const DIRECTIVES = new Set(['import', 'export', 'part', 'library']);

// What a string looks like when it names something for the program: a
// lower-case or camelCase token, or such tokens joined by - _ . / : = (a
// key, a route, a file name, a MIME type, a wire value), interpolations
// included; or a dotted name such as `SystemNavigator.pop`.
const IDENTIFIER_SHAPE = new RegExp(
  `^[./]?[a-z0-9${HOLE}][A-Za-z0-9${HOLE}]*(?:[-_./:=?&][A-Za-z0-9${HOLE}]+)*$`,
);
const DOTTED_NAME_SHAPE = /^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+$/;
const ROUTE_SHAPE = /^\/[^\s]*$/;
const URL_SHAPE = /^[a-z][a-z0-9+.-]*:\/\/\S+$/;
// A word of a date pattern ('yyyy-MM-dd HH:mm'): one pattern letter, repeated.
const DATE_PATTERN_WORD = /^(?:y+|M+|d+|E+|H+|h+|m+|s+|S+|a+|z+|Z+)$/;

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
        frames.push({ kind: 'call', ...calleeBefore(index), argStart: index + 1, argIndex: 0 });
      } else if (token.text === '[') {
        const before = tokens[index - 1];
        // `a?[0]` indexes; `ready ? [x] : [y]` opens a list. Only the
        // first is written without a space.
        const indexes =
          before !== undefined &&
          (before.type === 'word'
            ? !/^(?:return|case|in|is|as|const)$/.test(before.text)
            : before.text === '?'
              ? before.start + 1 === token.start
              : /^[)\]!]$/.test(before.text));
        frames.push({ kind: indexes ? 'index' : 'list', argStart: index + 1, argIndex: 0 });
      } else if (token.text === '{') {
        frames.push({ kind: 'brace', argStart: index + 1, argIndex: 0 });
        statementStart = index + 1;
      } else if (/^[)\]}]$/.test(token.text)) {
        frames.pop();
        if (token.text === '}') statementStart = index + 1;
      } else if (token.text === ',') {
        if (top) {
          top.argStart = index + 1;
          top.argIndex += 1;
        }
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
    if (URL_SHAPE.test(trimmed)) continue;

    // import 'x'; export 'x' show ...; part 'x';
    if (DIRECTIVES.has(tokens[statementStart]?.text)) continue;

    // Text on screen by where it stands: its shape does not excuse it.
    const namedArgument =
      top?.kind === 'call' &&
      tokens[top.argStart]?.type === 'word' &&
      tokens[top.argStart + 1]?.text === ':'
        ? tokens[top.argStart].text
        : null;
    const shownAsText =
      top?.kind === 'call' &&
      (namedArgument
        ? TEXT_ARGUMENTS.has(namedArgument)
        : top.argIndex === 0 && TEXT_CALLEES.has(top.name));
    if (!shownAsText) {
      if (
        IDENTIFIER_SHAPE.test(trimmed) ||
        DOTTED_NAME_SHAPE.test(trimmed) ||
        ROUTE_SHAPE.test(trimmed) ||
        words.every((word) => DATE_PATTERN_WORD.test(word))
      )
        continue;
    }
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
      if (top.argIndex === 0 && !namedArgument && NON_UI_FIRST_ARGUMENT.has(top.name)) continue;
      if (namedArgument && NON_UI_ARGUMENTS.has(namedArgument)) continue;
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

// Takes one occurrence of each of [texts] out of [found] (`{ line, text }`),
// and returns what is left of both: the findings no text accounts for, and
// the texts no finding was there for.
function takeOut(found, texts) {
  const rest = [...found];
  const missing = [];
  for (const text of texts) {
    const at = rest.findIndex((each) => each.text === text);
    if (at < 0) missing.push(text);
    else rest.splice(at, 1);
  }
  return { rest, missing };
}

const quoted = (texts) => texts.map((text) => `    ${JSON.stringify(text)}`).join('\n');

/** The gate: failures as lines of text, empty when it passes. */
export function checkUiStrings(rootDir, known = KNOWN_HARDCODED, notCopy = NOT_COPY) {
  const failures = [];
  const results = scanUiSources(rootDir);
  if (results.size === 0) failures.push(`no UI sources found under ${MOBILE_SRC}`);

  for (const [path, strings] of results) {
    const exempt = notCopy[path] ?? {};
    const stale = Object.keys(exempt).filter((text) => !strings.some((each) => each.text === text));
    if (stale.length > 0) {
      failures.push(
        `NOT_COPY lists literals ${MOBILE_SRC}/${path} no longer holds; remove their lines (scripts/mobile-ui-strings-check.mjs):\n` +
          quoted(stale),
      );
    }
    const unexplained = Object.entries(exempt).filter(([, why]) => !String(why ?? '').trim());
    if (unexplained.length > 0) {
      failures.push(
        `NOT_COPY must say why each literal of ${path} is not copy:\n` +
          quoted(unexplained.map(([text]) => text)),
      );
    }
    const copy = strings.filter((each) => !Object.hasOwn(exempt, each.text));
    const { rest: unlisted, missing: gone } = takeOut(copy, known[path] ?? []);
    if (unlisted.length > 0) {
      failures.push(
        `${MOBILE_SRC}/${path} holds user-facing string literals; move them to app_en.arb and app_ko.arb and read them from AppLocalizations:\n` +
          unlisted
            .map((found) => `    line ${found.line}: ${JSON.stringify(found.text)}`)
            .join('\n'),
      );
    }
    if (gone.length > 0) {
      failures.push(
        `${MOBILE_SRC}/${path} no longer holds these literals; remove their lines from KNOWN_HARDCODED` +
          `${gone.length === (known[path] ?? []).length ? ', and the entry of the file with them' : ''}` +
          ` (scripts/mobile-ui-strings-check.mjs):\n` +
          quoted(gone),
      );
    }
  }
  for (const [name, list] of [
    ['KNOWN_HARDCODED', known],
    ['NOT_COPY', notCopy],
  ]) {
    for (const path of Object.keys(list)) {
      if (!results.has(path)) {
        failures.push(
          `${name} lists ${path}, which is not a UI source under ${MOBILE_SRC}; remove the line`,
        );
      } else if (Object.keys(list[path]).length === 0) {
        failures.push(`${name} lists ${path} with nothing in it; remove the line`);
      }
    }
  }
  return failures;
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  const rootDir = join(fileURLToPath(new URL('.', import.meta.url)), '..');
  if (process.argv.includes('--list')) {
    // Every finding as the lists spell it, listed or not.
    for (const [path, strings] of scanUiSources(rootDir)) {
      if (strings.length === 0) continue;
      console.log(`${path}: ${strings.length}`);
      for (const found of strings) {
        const notCopy = Object.hasOwn(NOT_COPY[path] ?? {}, found.text) ? '  (NOT_COPY)' : '';
        console.log(`    line ${found.line}: ${JSON.stringify(found.text)}${notCopy}`);
      }
    }
  } else {
    const failures = checkUiStrings(rootDir);
    if (failures.length > 0) {
      console.error('Mobile UI strings check failed:');
      for (const failure of failures) console.error(`- ${failure}`);
      process.exit(1);
    }
    const listed = Object.values(KNOWN_HARDCODED).reduce((sum, texts) => sum + texts.length, 0);
    console.log(
      `Mobile UI strings check passed: no user-facing string literal outside the ARB files` +
        (listed > 0
          ? `, except the ${listed} known in ${Object.keys(KNOWN_HARDCODED).length} files (KNOWN_HARDCODED).`
          : '.'),
    );
  }
}
