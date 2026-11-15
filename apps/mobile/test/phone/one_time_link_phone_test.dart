import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/secret_link/data/one_time_link.dart';
import 'package:veil_mobile/src/features/secret_link/data/one_time_link_service.dart';
import 'package:veil_mobile/src/features/secret_link/presentation/one_time_link_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/phone_layout_probe.dart';
import '../support/copy_finder.dart';

// The one-time link screen on a phone: the form first, then the link that
// was made, then what such a link protects and what it does not.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final en = lookupAppLocalizations(const Locale('en'));
  final ko = lookupAppLocalizations(const Locale('ko'));
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

  Future<void> open(WidgetTester tester, {String locale = 'en', int status = 201, double keyboardHeight = 0}) async {
    usePhoneView(tester, phoneSmall, keyboardHeight: keyboardHeight);
    await tester.pumpWidget(MaterialApp(
      theme: VeilTheme.dark(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OneTimeLinkScreen(service: relay(status: status)),
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

  testWidgets('opens on the secret, the passphrase switch and the button; the explanation follows', (tester) async {
    await open(tester);
    expect(find.byType(VeilShell), findsOneWidget);
    final field = tester.getRect(find.byType(TextField));
    final passphrase = tester.getRect(find.byType(Switch));
    final button = tester.getRect(find.byType(FilledButton));
    expect(field.top, lessThan(140), reason: 'the field is the first thing under the bar');
    expect(field.bottom, lessThan(passphrase.top));
    expect(passphrase.bottom, lessThan(button.top));
    expect(button.bottom, lessThanOrEqualTo(640), reason: 'on the first screenful of a 360x640 phone');
    expect(find.byType(VeilStatusPill), findsNothing);

    // What it protects, then what it does not, each with its sentences.
    final said = <String>[];
    void collect() {
      for (final element in find.byType(Text).evaluate()) {
        final text = plainCopy((element.widget as Text).data ?? '');
        if (text.isNotEmpty && !said.contains(text)) said.add(text);
      }
    }

    collect();
    await scrollToEnd(tester, onPage: (_) async => collect());
    final order = [
      en.oneTimeLinkCreate,
      en.oneTimeLinkProtectsLabel,
      en.oneTimeLinkProtectsEncrypted,
      en.oneTimeLinkProtectsBurn,
      en.oneTimeLinkLimitsLabel,
      en.oneTimeLinkLimitHolder,
      en.oneTimeLinkLimitReader,
      en.oneTimeLinkLimitRelay,
    ];
    expect([for (final text in said) if (order.contains(text)) text], order);
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

  testWidgets('shows the link with its code and its expiry, and copies it', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    // With the keyboard still up, as it is when the button is pressed.
    await open(tester, keyboardHeight: 300);
    expect(find.byType(QrImageView, skipOffstage: false), findsNothing);
    await tester.enterText(find.byType(TextField), secret);
    await tester.pump();
    await tapCreate(tester);

    final link = tester.widget<SelectableText>(find.byType(SelectableText, skipOffstage: false)).data!;
    expect(link, startsWith('https://relay.example.org/demo/s.html#link-7.k.'));
    expect(find.byType(QrImageView, skipOffstage: false), findsOneWidget);
    // When the relay deletes it unopened, as the relay answered.
    expect(findCopyContaining('Apr 8'), findsOneWidget);
    expect(findCopyContaining(en.oneTimeLinkSendPassphraseApart), findsNothing, reason: 'no passphrase was set');
    // The code is brought on screen: it appears under the button, which the
    // keyboard leaves at the bottom edge of a 360x640 phone.
    final result = tester.getRect(find.byType(QrImageView, skipOffstage: false));
    expect(result.top, greaterThanOrEqualTo(24 + 52));
    expect(result.bottom, lessThanOrEqualTo(640 - 300));

    final copy = find.text(en.oneTimeLinkCopy, skipOffstage: false);
    await Scrollable.ensureVisible(tester.element(copy), alignment: 0.5);
    await tester.pump();
    await tester.tap(copy);
    await pumpFrames(tester, frames: 2);
    expect(copied, [link]);
    expect(findCopy(en.oneTimeLinkCopied), findsOneWidget);
  });

  testWidgets('says in Korean that the relay refused, and keeps the form', (tester) async {
    await open(tester, locale: 'ko', status: 503);
    await tester.enterText(find.byType(TextField), '현관 비밀번호 4471');
    await tester.pump();
    await tapCreate(tester);
    expect(findCopy(ko.oneTimeLinkFailed), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(create(tester).onPressed, isNotNull, reason: 'ready for another try');
    // The field may have scrolled out above the button: it is still there.
    expect(tester.widget<TextField>(find.byType(TextField, skipOffstage: false)).controller!.text, '현관 비밀번호 4471');
  });

  testWidgets('in a Korean app the form, the link that was made and the explanation are Korean', (tester) async {
    await open(tester, locale: 'ko');
    await tester.enterText(find.byType(TextField), '현관 비밀번호 4471');
    await tester.pump();
    await tapCreate(tester);
    expect(find.byType(QrImageView), findsOneWidget);

    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pump();
    final foreign = otherLanguageTextsOnScreen(tester, 'ko');
    await scrollToEnd(tester, onPage: (_) async => foreign.addAll(otherLanguageTextsOnScreen(tester, 'ko')));
    // The link itself is an address, which the check leaves out.
    expect(foreign, isEmpty);
  });
}
