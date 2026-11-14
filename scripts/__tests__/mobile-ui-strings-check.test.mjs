import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  KNOWN_HARDCODED,
  MOBILE_SRC,
  NOT_COPY,
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
    "final name = 'dossier.enc';",
    "if (normalized.endsWith('.jpeg')) return 'image/jpeg';",
    "final example = 'icarus';",
    "return 'android';",
    "prefs.getString('themeMode')",
    "json.containsKey('deviceName')",
    "Hero(tag: 'chatAvatar', child: c)",
    "storage.read('veil.themeMode')",
    "channel.invokeMethod('SystemNavigator.pop')",
    "final cleaned = raw.replaceAll('Bad state: ', '');",
    "const docs = 'https://veil.example/docs/Safety-Numbers';",
    "const stamp = 'yyyy-MM-dd HH:mm';",
    "Image.asset('assets/Brand Mark.png')",
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

// A lower-case word alone looks like a key or a wire value, and is left alone
// where nothing says what it is. Where the code says it is text on screen,
// it is a finding like any other.
test('a literal that stands where text goes is a finding whatever its shape', () => {
  assert.deepEqual(texts("Text('send')"), ['send']);
  assert.deepEqual(texts("const Text('ok', style: s)"), ['ok']);
  assert.deepEqual(texts("Text(ready ? 'on' : 'off')"), ['on', 'off']);
  assert.deepEqual(texts("Tooltip(message: 'copy', child: c)"), ['copy']);
  assert.deepEqual(texts("VeilButton(label: 'retry', onPressed: f)"), ['retry']);
  assert.deepEqual(texts("VeilSectionLabel('devices')"), ['devices']);
  assert.deepEqual(texts("InputDecoration(hintText: 'icarus')"), ['icarus']);
  assert.deepEqual(texts("TextEditingController(text: 'dossier.enc')"), ['dossier.enc']);
  assert.deepEqual(texts("Icon(Icons.send, semanticLabel: 'themeMode')"), ['themeMode']);
  // Not where text goes: the same words are left alone.
  assert.deepEqual(texts("foo('send', mode: 'ok')"), []);
  assert.deepEqual(texts("Text(labels['send'])"), []);
  assert.deepEqual(texts("Text(status == 'on' ? l10n.on : l10n.off)"), []);
  assert.deepEqual(texts("Text(l10n.count(n, 'other'))"), []);
  // The brand and what has no word are nobody's translation there either.
  assert.deepEqual(texts("Text('VEIL')"), []);
  assert.deepEqual(texts("Text('@$handle')"), []);
});

test('a list that follows a condition is read; an index is not', () => {
  assert.deepEqual(texts("final days = short ? ['Mon day', 'Tue day'] : [];"), [
    'Mon day',
    'Tue day',
  ]);
  assert.deepEqual(texts("final name = row?['Display Name'];"), []);
  assert.deepEqual(texts("final name = row['Display Name'];"), []);
});

// The second argument of a call whose first names a pattern or a key may be
// text.
test('only the first argument of a pattern or key call is left alone', () => {
  assert.deepEqual(texts("raw.replaceAll('Bad state: ', 'Something went wrong')"), [
    'Something went wrong',
  ]);
  assert.deepEqual(texts("prefs.setString('Display Name', 'Atlas Moreau')"), ['Atlas Moreau']);
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
  const failures = checkUiStrings(root, {}, {});
  assert.equal(failures.length, 1);
  assert.match(failures[0], /features\/chat\/presentation\/chat_room_screen\.dart/);
  assert.match(failures[0], /line 2: "Hard-coded English"/);
  assert.match(failures[0], /app_en\.arb and app_ko\.arb/);
});

test('the allow-list is exact: each listed literal, once per occurrence, and no other', () => {
  const file = 'features/voice/presentation/voice_recorder_screen.dart';
  const two = "Text('Tap to record');\nText('Recording');\n";
  const listed = { [file]: ['Tap to record', 'Recording'] };
  assert.deepEqual(checkUiStrings(tree({ [file]: two }), listed, {}), []);

  const more = checkUiStrings(tree({ [file]: `${two}Text('Playing');\n` }), listed, {});
  assert.equal(more.length, 1);
  assert.match(more[0], /voice_recorder_screen\.dart holds user-facing string literals/);
  assert.match(more[0], /line 3: "Playing"/);
  assert.doesNotMatch(more[0], /Tap to record/);

  const fewer = checkUiStrings(tree({ [file]: "Text('Tap to record');\n" }), listed, {});
  assert.equal(fewer.length, 1);
  assert.match(fewer[0], /no longer holds these literals; remove their lines from KNOWN_HARDCODED/);
  assert.match(fewer[0], /"Recording"/);
  assert.doesNotMatch(fewer[0], /the entry of the file/);

  const none = checkUiStrings(tree({ [file]: 'Text(l10n.voiceTapToRecord);\n' }), listed, {});
  assert.equal(none.length, 1);
  assert.match(none[0], /and the entry of the file with them/);

  // The same number of literals, but not the listed ones: one moved to the
  // ARB files and another written in its place.
  const swapped = checkUiStrings(
    tree({ [file]: "Text('Tap to record');\nText('Hold to record');\n" }),
    listed,
    {},
  );
  assert.equal(swapped.length, 2);
  assert.match(swapped[0], /line 2: "Hold to record"/);
  assert.match(swapped[1], /no longer holds these literals/);
  assert.match(swapped[1], /"Recording"/);

  // A literal that occurs twice is listed twice.
  const twice = tree({ [file]: "Text('Cancel');\nText('Cancel');\n" });
  assert.deepEqual(checkUiStrings(twice, { [file]: ['Cancel', 'Cancel'] }, {}), []);
  const once = checkUiStrings(twice, { [file]: ['Cancel'] }, {});
  assert.equal(once.length, 1);
  assert.match(once[0], /line 2: "Cancel"/);
});

// The way out for a literal the gate takes for text that nobody translates.
test('a literal listed as not copy is left alone, with its reason, while the file holds it', () => {
  const file = 'features/conversations/presentation/start_direct_chat_screen.dart';
  const source = "InputDecoration(hintText: 'icarus');\nText('Start a chat');\n";
  const why = { [file]: { icarus: 'an example handle' } };
  const unlisted = checkUiStrings(tree({ [file]: source }), {}, {});
  assert.match(unlisted[0], /line 1: "icarus"/);

  const excused = checkUiStrings(tree({ [file]: source }), {}, why);
  assert.equal(excused.length, 1);
  assert.doesNotMatch(excused[0], /icarus/);
  assert.match(excused[0], /line 2: "Start a chat"/);
  assert.deepEqual(checkUiStrings(tree({ [file]: source }), { [file]: ['Start a chat'] }, why), []);

  // Every occurrence in that file, and in that file only.
  const other = 'features/contacts/presentation/contacts_screen.dart';
  const both = tree({ [file]: `${source}Text('icarus');\n`, [other]: "Text('icarus');\n" });
  const elsewhere = checkUiStrings(both, { [file]: ['Start a chat'] }, why);
  assert.equal(elsewhere.length, 1);
  assert.match(elsewhere[0], /contacts_screen\.dart holds user-facing string literals/);

  const stale = checkUiStrings(tree({ [file]: "Text('Start a chat');\n" }), {}, why);
  assert.ok(stale.some((failure) => /NOT_COPY lists literals .* no longer holds/.test(failure)));

  const unexplained = checkUiStrings(
    tree({ [file]: source }),
    { [file]: ['Start a chat'] },
    {
      [file]: { icarus: ' ' },
    },
  );
  assert.equal(unexplained.length, 1);
  assert.match(unexplained[0], /NOT_COPY must say why/);
});

test('neither list can name a file that is gone or is not a UI source, or name it for nothing', () => {
  const root = tree({
    'features/chat/presentation/chat_room_screen.dart': 'Text(l10n.chatTitle);\n',
  });
  const failures = checkUiStrings(
    root,
    {
      'features/gone/presentation/gone_screen.dart': ['Gone'],
      'features/chat/data/outbox_service.dart': ['Not UI'],
      'features/chat/presentation/chat_room_screen.dart': [],
    },
    { 'features/gone/presentation/other_screen.dart': { gone: 'a key' } },
  );
  assert.equal(failures.length, 4);
  assert.match(
    failures[0],
    /KNOWN_HARDCODED lists features\/gone\/presentation\/gone_screen\.dart, which is not a UI source/,
  );
  assert.match(failures[2], /chat_room_screen\.dart with nothing in it/);
  assert.match(failures[3], /NOT_COPY lists features\/gone\/presentation\/other_screen\.dart/);
});

test('a tree without the mobile app fails instead of passing on nothing', () => {
  assert.match(checkUiStrings(join(scratch, 'empty'), {}, {})[0], /no UI sources found/);
});

test('the repository passes, with every listed literal where it is listed', () => {
  assert.deepEqual(checkUiStrings(repoRoot), []);
  for (const texts of Object.values(KNOWN_HARDCODED)) assert.ok(texts.length > 0);
  for (const reasons of Object.values(NOT_COPY)) {
    for (const why of Object.values(reasons)) assert.ok(why.trim().length > 10, why);
  }
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
  const failures = checkUiStrings(tree({ [path]: mutated }), {}, {});
  assert.equal(failures.length, 1);
  assert.match(failures[0], /one_time_link_screen\.dart holds user-facing string literals/);
  assert.match(failures[0], /"Burns after reading"/);
});
