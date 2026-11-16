import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/secret_link/data/one_time_link.dart';
import 'package:veil_mobile/src/features/secret_link/data/one_time_link_service.dart';
import 'package:veil_mobile/src/features/secret_link/presentation/one_time_link_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/phone_layout_probe.dart';
import '../support/copy_finder.dart';

// The one-time link screen on a phone: the form first with the one rule of
// such a link under it, then the button, then the link that was made.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final en = lookupAppLocalizations(const Locale('en'));
  const secret = 'The door code is 4471';

  setUpAll(loadBundledFonts);

  // The relay's `/s` route: keeps what was posted, answers as told.
  late List<Map<String, dynamic>> posted;
  OneTimeLinkService relay({int status = 201}) => OneTimeLinkService(
        apiBaseUrl: 'https://relay.example.org/v1',
        client: MockClient((request) async {
          posted.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({'id': 'link-7', 'expiresAt': DateTime.utc(2026, 4, 8, 9, 30).toIso8601String()}),
            status,
          );
        }),
      );

  setUp(() => posted = []);

  Future<void> open(
    WidgetTester tester, {
    int status = 201,
    double keyboardHeight = 0,
    OneTimeLinkService? service,
  }) async {
    usePhoneView(tester, phoneSmall, keyboardHeight: keyboardHeight);
    await tester.pumpWidget(MaterialApp(
      theme: VeilTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OneTimeLinkScreen(service: service ?? relay(status: status)),
    ));
    await pumpFrames(tester, frames: 2);
  }

  FilledButton create(WidgetTester tester) => tester.widget(find.byType(FilledButton));

  // Sealing runs real key derivation, which only real time moves forward.
  Future<void> tapCreate(WidgetTester tester) async {
    // A field that was just typed into scrolls its caret into view for a
    // moment, and a list that is scrolling takes no tap.
    await pumpFrames(tester, frames: 2);
    await tester.ensureVisible(find.byType(FilledButton, skipOffstage: false));
    await pumpFrames(tester, frames: 2);
    await tester.tap(find.byType(FilledButton));
    for (var i = 0; i < 200 && posted.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await pumpFrames(tester, frames: 4);
  }

  testWidgets('opens on the secret, the passphrase switch and the button, and says the rule once', (tester) async {
    await open(tester);
    expect(find.byType(VeilShell), findsOneWidget);
    expect(tester.widget<VeilShell>(find.byType(VeilShell)).grouped, isTrue, reason: 'a grouped page');
    final field = tester.getRect(find.byType(TextField));
    // The switch row has no line under its words, so its switch sits close
    // to the field: the words mark where the row starts.
    final passphrase = tester.getRect(find.text(en.oneTimeLinkUsePassphrase));
    final button = tester.getRect(find.byType(FilledButton));
    expect(find.byType(Switch), findsOneWidget);
    expect(field.top, lessThan(140), reason: 'the field is the first thing under the bar');
    expect(field.bottom, lessThan(passphrase.top));
    expect(passphrase.bottom, lessThan(button.top));
    expect(button.bottom, lessThanOrEqualTo(640), reason: 'on the first screenful of a 360x640 phone');
    // What the link does is the form's footer, between the form and the
    // button; nothing else on the screen says it again.
    final footer = tester.getRect(find.text(en.oneTimeLinkFooter));
    expect(footer.top, greaterThan(passphrase.bottom));
    expect(footer.bottom, lessThan(button.top));
    // The hint names the field on screen; a screen reader hears the name on
    // the field itself.
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(tester.getSemantics(find.byType(TextField)).label, contains(en.oneTimeLinkSecretLabel));
    semantics.dispose();

    // No section of caveats follows the button.
    final said = <String>[];
    void collect() {
      for (final element in find.byType(Text).evaluate()) {
        final text = (element.widget as Text).data ?? '';
        if (text.isNotEmpty && !said.contains(text)) said.add(text);
      }
    }

    collect();
    await scrollToEnd(tester, onPage: (_) async => collect());
    final order = [en.oneTimeLinkFooter, en.oneTimeLinkCreate];
    expect([for (final text in said) if (order.contains(text)) text], order);
    expect(said.skipWhile((text) => text != en.oneTimeLinkCreate).skip(1).where((text) => text != en.oneTimeLinkTitle),
        isEmpty,
        reason: 'nothing under the button before a link is made');
    // The footer is the one place the screen says the link opens once.
    expect([for (final text in said) if (text.contains('once')) text], [en.oneTimeLinkFooter]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('needs a secret, and a passphrase once the switch asks for one', (tester) async {
    await open(tester);
    expect(create(tester).onPressed, isNull, reason: 'nothing to seal yet');
    await tester.enterText(find.byType(TextField), secret);
    await tester.pump();
    expect(create(tester).onPressed, isNotNull);

    // Switched on from the row's words, not only from the switch.
    await tester.tap(find.text(en.oneTimeLinkUsePassphrase));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(create(tester).onPressed, isNull, reason: 'an empty passphrase would put the key back into the link');

    await tester.enterText(find.byType(TextField).last, 'open-sesame');
    await tester.pump();
    expect(create(tester).onPressed, isNotNull);

    await tapCreate(tester);
    final blob = posted.single['ciphertext'] as String;
    expect(posted.single.keys, ['ciphertext']);
    expect(blob.split('.'), hasLength(4), reason: 'the blob carries the salt of a passphrase key');
    expect(blob, isNot(contains(secret)));
    final link = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(link, 'https://relay.example.org/demo/s.html#link-7.p', reason: 'no key in the link');
    expect(await tester.runAsync(() => OneTimeLink.open(blob, 'p', passphrase: 'open-sesame')), secret);
    expect(findCopyContaining(en.oneTimeLinkSendPassphraseApart), findsOneWidget);
  });

  testWidgets('shows the link and its expiry, and copies it', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    // With the keyboard still up, as it is when the button is pressed.
    await open(tester, keyboardHeight: 300);
    expect(find.byType(SelectableText, skipOffstage: false), findsNothing);
    await tester.enterText(find.byType(TextField), secret);
    await tester.pump();
    await tapCreate(tester);

    final link = tester.widget<SelectableText>(find.byType(SelectableText, skipOffstage: false)).data!;
    expect(link, startsWith('https://relay.example.org/demo/s.html#link-7.k.'));
    expect(find.byType(SelectableText, skipOffstage: false), findsOneWidget);
    // When the relay deletes it unopened, as the relay answered.
    expect(findCopyContaining('Apr 8'), findsOneWidget);
    expect(findCopyContaining(en.oneTimeLinkSendPassphraseApart), findsNothing, reason: 'no passphrase was set');
    // The link is brought on screen: it appears under the button, which the
    // keyboard leaves at the bottom edge of a 360x640 phone.
    final result = tester.getRect(find.byType(SelectableText, skipOffstage: false));
    expect(result.top, greaterThanOrEqualTo(24 + 52));
    expect(result.bottom, lessThanOrEqualTo(640 - 300));

    // The link is drawn in monospace, with "Copy link" under it.
    expect(tester.widget<SelectableText>(find.byType(SelectableText, skipOffstage: false)).style?.fontFamily,
        'monospace');
    final copy = find.ancestor(of: find.text(en.oneTimeLinkCopy, skipOffstage: false), matching: find.byType(VeilRow));
    expect(tester.getSize(copy).shortestSide, greaterThanOrEqualTo(44));
    await Scrollable.ensureVisible(tester.element(copy), alignment: 0.5);
    await tester.pump();
    await tester.tap(copy);
    await pumpFrames(tester, frames: 2);
    expect(copied, [link]);
    expect(findCopy(en.oneTimeLinkCopied), findsOneWidget);
  });

  // What is said under a link is about that link. A link made with its key
  // inside was called passphrase-locked once the switch was turned on beside
  // it: the link on screen now goes when the form it came from changes.
  group('the link on screen is the one the form made', () {
    Finder shownLink() => find.byType(SelectableText, skipOffstage: false);
    Finder note() => findCopyContaining(en.oneTimeLinkSendPassphraseApart, skipOffstage: false);

    // The form scrolls away when the link is brought on screen.
    Future<void> backToTheForm(WidgetTester tester) async {
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await pumpFrames(tester, frames: 2);
    }

    Future<void> flipSwitch(WidgetTester tester) async {
      final row = find.text(en.oneTimeLinkUsePassphrase, skipOffstage: false);
      await tester.ensureVisible(row);
      await pumpFrames(tester, frames: 2);
      await tester.tap(row);
      await pumpFrames(tester, frames: 2);
    }

    testWidgets('made with the key inside, it goes when the passphrase switch is turned on', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), secret);
      await tester.pump();
      await tapCreate(tester);
      expect(tester.widget<SelectableText>(shownLink()).data, contains('#link-7.k.'));
      expect(note(), findsNothing);

      await flipSwitch(tester);
      expect(shownLink(), findsNothing, reason: 'a link with its key inside beside a form that says "locked"');
      expect(find.byType(SelectableText, skipOffstage: false), findsNothing);
      expect(note(), findsNothing, reason: 'nothing on screen is locked with a passphrase');
      expect(tester.widget<FilledButton>(find.byType(FilledButton, skipOffstage: false)).onPressed, isNull,
          reason: 'the next link waits for its passphrase');
      expect(posted, hasLength(1));
    });

    // The next three seal nothing: the links are handed out as the service
    // would describe them, which the tests above and one_time_link_test.dart
    // hold it to. Deriving a key from a passphrase takes seconds here.
    Future<void> createCanned(WidgetTester tester) async {
      await pumpFrames(tester, frames: 2);
      await tester.ensureVisible(find.byType(FilledButton, skipOffstage: false));
      await pumpFrames(tester, frames: 2);
      await tester.tap(find.byType(FilledButton));
      await pumpFrames(tester, frames: 4);
    }

    testWidgets('made with a passphrase, it goes when the switch is turned off, and the next one has no reminder',
        (tester) async {
      final service = _CannedLinks();
      await open(tester, service: service);
      await tester.enterText(find.byType(TextField), secret);
      await flipSwitch(tester);
      await tester.enterText(find.byType(TextField).last, 'open-sesame');
      await tester.pump();
      await createCanned(tester);
      expect(service.passphrases, ['open-sesame']);
      expect(tester.widget<SelectableText>(shownLink()).data, endsWith('#link-1.p'));
      expect(note(), findsOneWidget);

      await flipSwitch(tester);
      expect(shownLink(), findsNothing);
      expect(note(), findsNothing);

      // The form now asks for a link with its key inside, and gets one.
      await createCanned(tester);
      expect(service.passphrases, ['open-sesame', null]);
      expect(tester.widget<SelectableText>(shownLink()).data, contains('#link-2.k.'));
      expect(note(), findsNothing, reason: 'this link opens without a passphrase');
    });

    testWidgets('it goes when the secret or the passphrase is edited', (tester) async {
      final service = _CannedLinks();
      await open(tester, service: service);
      await tester.enterText(find.byType(TextField), secret);
      await flipSwitch(tester);
      await tester.enterText(find.byType(TextField).last, 'open-sesame');
      await tester.pump();
      await createCanned(tester);
      expect(shownLink(), findsOneWidget);

      await backToTheForm(tester);
      await tester.enterText(find.byType(TextField).last, 'open-sesame-2');
      await pumpFrames(tester, frames: 2);
      expect(shownLink(), findsNothing, reason: 'the link is locked with the passphrase that was replaced');

      await createCanned(tester);
      expect(shownLink(), findsOneWidget);
      await backToTheForm(tester);
      await tester.enterText(find.byType(TextField).first, 'The door code is 4472');
      await pumpFrames(tester, frames: 2);
      expect(shownLink(), findsNothing, reason: 'the link carries the secret that was replaced');
      expect(find.byType(SelectableText, skipOffstage: false), findsNothing);
      expect(service.secrets, [secret, secret], reason: 'no link was made for what was typed since');
    });

    testWidgets('a link that arrives after the secret was changed is not shown', (tester) async {
      // A relay that takes its time: the fields stay open meanwhile.
      final answer = Completer<http.Response>();
      await open(
        tester,
        service: OneTimeLinkService(
          apiBaseUrl: 'https://relay.example.org/v1',
          client: MockClient((request) {
            posted.add(jsonDecode(request.body) as Map<String, dynamic>);
            return answer.future;
          }),
        ),
      );
      await tester.enterText(find.byType(TextField), secret);
      await pumpFrames(tester, frames: 2);
      await tester.tap(find.byType(FilledButton));
      for (var i = 0; i < 200 && posted.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(posted, hasLength(1), reason: 'the first secret was sealed and sent');
      expect(create(tester).onPressed, isNull, reason: 'still creating');

      await tester.enterText(find.byType(TextField), 'The door code is 4472');
      await tester.pump();
      answer.complete(http.Response(jsonEncode({'id': 'link-7'}), 201));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await pumpFrames(tester, frames: 4);

      expect(shownLink(), findsNothing, reason: 'the link does not carry what the field says now');
      expect(find.byType(SelectableText, skipOffstage: false), findsNothing);
      expect(create(tester).onPressed, isNotNull, reason: 'ready to seal what the field says');
    });
  });

  testWidgets('says that the relay refused in one line under the button, keeps the form, and the button tries again',
      (tester) async {
    var status = 503;
    final service = OneTimeLinkService(
      apiBaseUrl: 'https://relay.example.org/v1',
      client: MockClient((request) async {
        posted.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({'id': 'link-7', 'expiresAt': DateTime.utc(2026, 4, 8, 9, 30).toIso8601String()}),
          status,
        );
      }),
    );
    await open(tester, service: service);
    await tester.enterText(find.byType(TextField), secret);
    await tester.pump();
    await tapCreate(tester);
    final failure = findCopy(en.oneTimeLinkFailed);
    expect(failure, findsOneWidget);
    // Plain text, not a notice: the button above it is the retry.
    expect(find.byType(VeilNotice), findsNothing);
    expect(tester.getTopLeft(failure).dy, greaterThanOrEqualTo(tester.getBottomLeft(find.byType(FilledButton)).dy));
    expect(find.byType(SelectableText), findsNothing);
    expect(create(tester).onPressed, isNotNull, reason: 'ready for another try');
    // The field may have scrolled out above the button: it is still there.
    expect(tester.widget<TextField>(find.byType(TextField, skipOffstage: false)).controller!.text, secret);

    // The relay answers the next try: the line goes, the link comes.
    status = 201;
    posted.clear();
    await tapCreate(tester);
    expect(posted, hasLength(1));
    expect(findCopy(en.oneTimeLinkFailed), findsNothing);
    expect(find.byType(SelectableText, skipOffstage: false), findsOneWidget);
  });
}

/// Hands out links without sealing anything: with the key inside, or locked
/// with a passphrase, as the service says of a link it made.
class _CannedLinks extends OneTimeLinkService {
  _CannedLinks() : super(apiBaseUrl: 'https://relay.example.org/v1', client: MockClient((_) async => http.Response('', 500)));

  final List<String> secrets = [];
  final List<String?> passphrases = [];

  @override
  Future<CreatedOneTimeLink> create(String secret, {String? passphrase}) async {
    secrets.add(secret);
    passphrases.add(passphrase);
    final locked = passphrase != null && passphrase.isNotEmpty;
    return CreatedOneTimeLink(
      url: 'https://relay.example.org/demo/s.html#link-${secrets.length}.${locked ? 'p' : 'k.a2V5'}',
      passphraseLocked: locked,
    );
  }
}
