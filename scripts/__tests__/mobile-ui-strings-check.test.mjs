import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  KNOWN_HARDCODED,
  MOBILE_SRC,
  checkUiStrings,
  hardcodedStrings,
  isUiSource,
  scanUiSources,
} from '../mobile-ui-strings-check.mjs';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const scratch = mkdtempSync(join(tmpdir(), 'veil-ui-strings-test-'));
after(() => rmSync(scratch, { recursive: true, force: true }));

const texts = (source) => hardcodedStrings(source).map((found) => found.text);

let trees = 0;
const tree = (files) => {
  trees += 1;
  const root = join(scratch, `tree-${trees}`);
  for (const [path, contents] of Object.entries(files)) {
    const file = join(root, MOBILE_SRC, path);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, contents);
  }
  return root;
};

test('text a widget shows is a finding, with its line', () => {
  const source = [
    "import 'package:flutter/material.dart';",
    '',
    'Widget build(BuildContext context) {',
    '  return Column(children: [Text(\'Send encrypted media\'), const Text("Clear")]);',
    '}',
  ].join('\n');
  assert.deepEqual(hardcodedStrings(source), [
    { line: 4, text: 'Send encrypted media' },
    { line: 4, text: 'Clear' },
  ]);
});

test('every place a string reaches the screen from is read', () => {
  assert.deepEqual(texts("VeilButton(label: _isMuted ? 'Unmute' : 'Mute', onPressed: f)"), [
    'Unmute',
    'Mute',
  ]);
  assert.deepEqual(texts("String get status => 'Calling';"), ['Calling']);
  assert.deepEqual(texts("const tabs = ['Emoji', 'Stickers'];"), ['Emoji', 'Stickers']);
  assert.deepEqual(texts("const categories = [('Smileys', Icons.a), ('People', Icons.b)];"), [
    'Smileys',
    'People',
  ]);
  assert.deepEqual(texts("const Foo({this.label = 'Send opaque text'});"), ['Send opaque text']);
  assert.deepEqual(texts("final name = given ?? 'Unknown';"), ['Unknown']);
  assert.deepEqual(texts("IconButton(tooltip: 'Open camera', onPressed: f)"), ['Open camera']);
  assert.deepEqual(texts("Semantics(label: 'Conversation with $title')"), ['Conversation with …']);
  assert.deepEqual(texts("message: '${_selected.length} item(s) queued'"), ['… item(s) queued']);
  // A literal inside an interpolation is still a literal.
  assert.deepEqual(texts("Text('${ready ? 'Ready' : 'Waiting'}')"), ['Ready', 'Waiting']);
  // Dart joins adjacent literals: one message, one finding.
  assert.deepEqual(texts("body: 'Files are sealed on-device '\n    'before transmission.'"), [
    'Files are sealed on-device before transmission.',
  ]);
  assert.deepEqual(texts('Text("""Two\nlines""")'), ['Two lines']);
  assert.deepEqual(texts("Text('보내기')"), ['보내기']);
  assert.deepEqual(texts("Text('VEIL Assistant')"), ['VEIL Assistant']);
  assert.deepEqual(texts("expectedPhrase: 'WIPE'"), ['WIPE']);
});

test('what is not text for a person is left alone', () => {
  const notUi = [
    // Directives.
    "import '../../../shared/presentation/veil_ui.dart';",
    "export 'chat_room_labels.dart' show formatRetryCountdown;",
    "part 'app_database.g.dart';",
    // Lookups.
    'Text(l10n.chatSendAction)',
    'Text(AppLocalizations.of(context).settingsTitle)',
    // Routes and keys.
    "context.push('/chat/$conversationId');",
    "GoRoute(path: '/safety-numbers/:conversationId', builder: b)",
    "context.push('/safety-numbers/${id}?member=${Uri.encodeQueryComponent(userId)}');",
    "Dismissible(key: ValueKey('reply-${message.id}'), child: c)",
    "const Key('settings-profile')",
    "const storageKey = 'conversation-list-view-state';",
    // Map and JSON keys, and what a value is compared with or switched on.
    "final id = json['counterpartyHandle'] as String?;",
    "state.pathParameters['conversationId']!",
    "final body = {'deviceName': name, 'platform': platform};",
    "if (rawType == 'video') return a;",
    "return switch (status) { 'missed' => a, 'declined' => b, _ => c };",
    "switch (normalized) { case 'Authenticated API session required.': return x; }",
    "contactName: switch (extra) { {'name': final String name} => name, _ => '' }",
    // Patterns.
    "DateFormat('HH:mm').format(at)",
    "DateFormat.MMMd('en')",
    "RegExp(r'[A-Za-z]{3,}')",
    "final pattern = r'^\\w+ words here$';",
    // Errors and logs.
    "throw StateError('Conversation not found');",
    "assert(count > 0, 'A strip needs tiles');",
    "debugPrint('router refreshed');",
    "if (normalized.startsWith('Request failed: HTTP 401')) return x;",
    "@Deprecated('Use deviceTransferControllerProvider.')",
    // Identifiers, file names, MIME types, wire values.
    "TextStyle(fontSize: 12, fontFamily: 'Pretendard')",
    "TextStyle(fontFamily: 'monospace')",
    "return 'application/octet-stream';",
    "TextEditingController(text: 'dossier.enc')",
    "if (normalized.endsWith('.jpeg')) return 'image/jpeg';",
    "hintText: 'icarus'",
    "return 'android';",
    "const identityChanged = 'identity.changed';",
    "const String.fromEnvironment('VEIL_TLS_PINS')",
    // Nothing to translate: no words, the brand, platform names, units.
    "Text('@$handle')",
    "Text('$minutes:${seconds.toString().padLeft(2, \\'0\\')}')",
    "Text('  \\u00b7  $durationLabel')",
    "Text('\\u{1F44D}')",
    "Text('${l10n.chatTtlSheetTitle}: ${label}')",
    "MaterialApp(title: 'VEIL')",
    "return 'VEIL ${_platformName()}';",
    "return 'iPhone / iPad';",
    "return '${value.toStringAsFixed(1)} MB';",
    "return '${DateFormat.MMMd(locale).format(at)} (UTC)';",
    // Comments.
    "// Text('Not code')\n/* Text('Nor this') /* nested */ still a comment */",
    "/// Shows 'Send' when [busy] is false.",
  ];
  for (const source of notUi) {
    assert.deepEqual(texts(source), [], source);
  }
});

test('only the files that build UI text are read', () => {
  assert.equal(isUiSource('features/chat/presentation/chat_room_screen.dart'), true);
  assert.equal(isUiSource('features/chat/presentation/chat_room_labels.dart'), true);
  assert.equal(isUiSource('features/conversations/presentation/parts/row.dart'), true);
  assert.equal(isUiSource('shared/presentation/veil_ui.dart'), true);
  assert.equal(isUiSource('app/router/app_router.dart'), true);
  assert.equal(isUiSource('app/veil_app.dart'), true);
  assert.equal(isUiSource('core/errors/user_facing_error.dart'), true);
  assert.equal(isUiSource('features/chat/data/messenger/outbox_service.dart'), false);
  assert.equal(isUiSource('core/crypto/crypto_engine.dart'), false);
  assert.equal(isUiSource('l10n/generated/app_localizations_en.dart'), false);

  const root = tree({
    'features/calls/presentation/call_screen.dart': "Text('End');",
    'features/calls/data/call_history_providers.dart':
      "counterparty: json['c'] ?? 'Unknown caller',",
    'l10n/generated/app_localizations_en.dart': "String get callsEnd => 'End the call';",
  });
  assert.deepEqual(
    [...scanUiSources(root).keys()],
    ['features/calls/presentation/call_screen.dart'],
  );
});

test('a literal in an unlisted file fails, and names the file, the line and the text', () => {
  const root = tree({
    'features/chat/presentation/chat_room_screen.dart':
      "Widget a() => Text(l10n.chatTitle);\nWidget b() => Text('Hard-coded English');\n",
  });
  const failures = checkUiStrings(root, {});
  assert.equal(failures.length, 1);
  assert.match(failures[0], /features\/chat\/presentation\/chat_room_screen\.dart/);
  assert.match(failures[0], /line 2: "Hard-coded English"/);
  assert.match(failures[0], /app_en\.arb and app_ko\.arb/);
});

test('the allow-list is exact: it passes at its number and fails above and below it', () => {
  const file = 'features/voice/presentation/voice_recorder_screen.dart';
  const two = "Text('Tap to record');\nText('Recording');\n";
  assert.deepEqual(checkUiStrings(tree({ [file]: two }), { [file]: 2 }), []);

  const more = checkUiStrings(tree({ [file]: `${two}Text('Playing');\n` }), { [file]: 2 });
  assert.equal(more.length, 1);
  assert.match(more[0], /holds 3 user-facing string literals, 1 more than the 2 listed/);

  const fewer = checkUiStrings(tree({ [file]: "Text('Tap to record');\n" }), { [file]: 2 });
  assert.equal(fewer.length, 1);
  assert.match(fewer[0], /now holds 1 user-facing string literals, not 2: lower its number/);

  const none = checkUiStrings(tree({ [file]: 'Text(l10n.voiceTapToRecord);\n' }), { [file]: 2 });
  assert.equal(none.length, 1);
  assert.match(none[0], /remove its line from KNOWN_HARDCODED/);
});

test('the allow-list cannot name a file that is gone or is not a UI source', () => {
  const root = tree({
    'features/chat/presentation/chat_room_screen.dart': 'Text(l10n.chatTitle);\n',
  });
  const failures = checkUiStrings(root, {
    'features/gone/presentation/gone_screen.dart': 3,
    'features/chat/data/outbox_service.dart': 1,
  });
  assert.equal(failures.length, 2);
  assert.match(
    failures[0],
    /features\/gone\/presentation\/gone_screen\.dart, which is not a UI source/,
  );
});

test('a tree without the mobile app fails instead of passing on nothing', () => {
  assert.match(checkUiStrings(join(scratch, 'empty'), {})[0], /no UI sources found/);
});

test('the repository passes, with every listed file at its number', () => {
  assert.deepEqual(checkUiStrings(repoRoot), []);
  for (const count of Object.values(KNOWN_HARDCODED)) assert.ok(count > 0);
});

// The mutation the gate exists for: one hard-coded string in a screen that
// has none.
test('a hard-coded Text added to a localized screen of the repository fails', () => {
  const path = 'features/secret_link/presentation/one_time_link_screen.dart';
  const source = readFileSync(join(repoRoot, MOBILE_SRC, path), 'utf8');
  assert.deepEqual(hardcodedStrings(source), [], `${path} is localized`);
  assert.equal(KNOWN_HARDCODED[path], undefined);

  const anchor = '          const SizedBox(height: VeilSpace.md),\n';
  assert.ok(source.includes(anchor));
  const mutated = source.replace(anchor, `${anchor}          const Text('Burns after reading'),\n`);
  const failures = checkUiStrings(tree({ [path]: mutated }), {});
  assert.equal(failures.length, 1);
  assert.match(failures[0], /one_time_link_screen\.dart holds user-facing string literals/);
  assert.match(failures[0], /"Burns after reading"/);
});
