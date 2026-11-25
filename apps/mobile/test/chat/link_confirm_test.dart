import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/system_sheet_grace.dart';
import 'package:veil_mobile/src/app/veil_app.dart';
import 'package:veil_mobile/src/core/notifications/local_notification_service.dart';
import 'package:veil_mobile/src/core/platform/link_opener.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/safety/application/contact_trust.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../phone/phone_app.dart';
import '../support/copy_finder.dart';
import '../support/fake_platform_security.dart';
import '../support/layout_trust.dart';

// Links in messages (2.6): drawn as links and tappable, a sheet first for
// any link not from the user or a verified sender, the strong sheet for an
// app file, a hidden or a look-alike link from anyone, and the link opened
// by the phone's browser only once Open is tapped, exactly as written. The
// phone never fetches a link itself. Opening one is a trip away from the
// app, so app lock locks on the way back.

/// The browser, for tests: every link it was asked to open.
class _Browser implements LinkOpener {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

/// Any HTTP client the app makes from here on, counted: none may be made
/// for a link.
class _CountingHttp extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients += 1;
    return super.createHttpClient(context);
  }
}

class _QuietNotifications implements LocalNotificationService {
  @override
  void Function(String? conversationId)? onNotificationTapped;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showMessageNotification({required String conversationId, required String title, required String body}) async {}

  @override
  Future<void> cancelConversation(String conversationId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  late _Browser browser;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  setUp(() => browser = _Browser());

  Finder inSheet(Finder finder) => find.descendant(of: find.byType(BottomSheet), matching: finder);

  // [from] writes [texts] (mallory, a stranger, or sam, verified on this
  // phone), and alex opens that chat.
  Future<void> withLinks(
    WidgetTester tester, {
    required String from,
    required List<String> texts,
    required Future<void> Function(LayoutWorld world, ContactTrust trust) body,
  }) async {
    late ContactTrust trust;
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/conv-$from',
      overrides: [linkOpenerProvider.overrideWithValue(browser)],
      beforeSession: (relay) => addStranger(relay, identities, 'mallory'),
      afterSession: (world) async {
        trust = await attachContactTrust(world);
        await strangerWrites(world, from, texts);
      },
      body: (world) async {
        await pumpFrames(tester, frames: 6);
        await body(world, trust);
      },
    );
  }

  // Taps the middle of [part] where a message draws it. A link's words are
  // read out as "Link, " and its domain, so the drawn text is searched.
  Future<void> tapLink(WidgetTester tester, String part) async {
    final paragraph = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .firstWhere((paragraph) => paragraph.text.toPlainText(includeSemanticsLabels: false).contains(part));
    final start = paragraph.text.toPlainText(includeSemanticsLabels: false).indexOf(part);
    final box = paragraph.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + part.length)).first;
    await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
    await pumpFrames(tester, frames: 6);
  }

  testWidgets('a link from an unverified sender asks first and shows its domain', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    const link = 'https://flats.example.org/listing/42';
    await withLinks(tester, from: 'mallory', texts: ['the flat is here $link'], body: (world, trust) async {
      // Accepted, so only the sender is unverified.
      await trust.accept('conv-mallory');
      await pumpFrames(tester, frames: 2);
      await tapLink(tester, 'flats.example.org');
      expect(browser.opened, isEmpty, reason: 'nothing opens before the sheet is answered');
      expect(inSheet(find.text(en.linkConfirmTitle)), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('link-sheet-domain'))).data, 'example.org',
          reason: 'the real domain, on its own line');
      expect(tester.widget<Text>(find.byKey(const ValueKey('link-sheet-address'))).data, link);
      expect(inSheet(find.text(en.linkConfirmOpen)), findsOneWidget);
      expect(inSheet(find.text(en.linkConfirmCopy)), findsOneWidget);
      expect(inSheet(find.text(en.linkRiskKeepClosed)), findsNothing, reason: 'the plain sheet');

      // Copy link copies it and opens nothing.
      await tester.tap(inSheet(find.text(en.linkConfirmCopy)));
      await pumpFrames(tester, frames: 4);
      expect(copied, link);
      expect(findCopy(en.linkCopied), findsOneWidget);
      expect(browser.opened, isEmpty);

      await tapLink(tester, 'flats.example.org');
      await tester.tap(inSheet(find.text(en.linkConfirmOpen)));
      await pumpFrames(tester, frames: 4);
      expect(browser.opened, [Uri.parse(link)]);
    });

    // The same link from a verified contact opens at once.
    browser.opened.clear();
    await withLinks(tester, from: 'sam', texts: ['the flat is here $link'], body: (world, trust) async {
      await tapLink(tester, 'flats.example.org');
      expect(find.byType(BottomSheet), findsNothing);
      expect(browser.opened, [Uri.parse(link)]);
    });
  });

  testWidgets('an app-file link gets the strong sheet even from a verified contact', (tester) async {
    const apk = 'https://files.example.org/build/update.apk';
    const short = 'https://bit.ly/3kQ9xZ';
    await withLinks(tester, from: 'sam', texts: ['try this one $apk', 'or this $short'], body: (world, trust) async {
      // A verified sender's app-file link: its line is mild, its sheet strong.
      expect(findCopy(en.riskLineAppFile), findsOneWidget);
      await tapLink(tester, 'files.example.org');
      expect(inSheet(find.text(en.linkRiskAppTitle)), findsOneWidget);
      expect(inSheet(find.text(en.linkRiskAppBody)), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('link-sheet-domain'))).data, 'example.org');
      final keepClosed = inSheet(find.widgetWithText(FilledButton, en.linkRiskKeepClosed));
      expect(keepClosed, findsOneWidget, reason: 'staying away is the filled button');
      final openAnyway = tester.widget<VeilRow>(find.byKey(const ValueKey('link-sheet-open')));
      expect(openAnyway.title, en.linkRiskOpenAnyway);
      expect(openAnyway.destructive, isTrue);
      expect(tester.getTopLeft(keepClosed).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('link-sheet-open'))).dy));
      await tester.tap(keepClosed);
      await pumpFrames(tester, frames: 4);
      expect(find.byType(BottomSheet), findsNothing);
      expect(browser.opened, isEmpty);

      // A short link hides where it goes: the strong sheet too.
      await tapLink(tester, 'bit.ly');
      expect(inSheet(find.text(en.linkRiskHiddenTitle)), findsOneWidget);
      await tester.tap(inSheet(find.widgetWithText(FilledButton, en.linkRiskKeepClosed)));
      await pumpFrames(tester, frames: 4);

      // Open anyway opens it.
      await tapLink(tester, 'files.example.org');
      await tester.tap(find.byKey(const ValueKey('link-sheet-open')));
      await pumpFrames(tester, frames: 4);
      expect(browser.opened, [Uri.parse(apk)]);
    });
  });

  testWidgets('the phone opens nothing and fetches nothing until Open is tapped, then opens that exact link once',
      (tester) async {
    const link = 'https://menu.example.org/today?item=7&size=large#drinks';
    final http = _CountingHttp();
    final previous = HttpOverrides.current;
    HttpOverrides.global = http;
    addTearDown(() => HttpOverrides.global = previous);
    await withLinks(tester, from: 'mallory', texts: ['lunch? $link'], body: (world, trust) async {
      expect(trust.isRequest('conv-mallory'), isTrue);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(browser.opened, isEmpty);
      // Whatever the app made before the chat was on screen is not counted.
      final clientsBefore = http.clients;

      // A tap shows the sheet; closing it opens nothing.
      await tapLink(tester, 'menu.example.org');
      expect(inSheet(find.text(en.linkConfirmTitle)), findsOneWidget);
      expect(browser.opened, isEmpty);
      Navigator.of(tester.element(inSheet(find.text(en.linkConfirmTitle)))).pop();
      await pumpFrames(tester, frames: 4);
      expect(browser.opened, isEmpty);

      // Open: that link, as written, once.
      await tapLink(tester, 'menu.example.org');
      await tester.tap(inSheet(find.text(en.linkConfirmOpen)));
      await pumpFrames(tester, frames: 6);
      expect(browser.opened, hasLength(1));
      expect(browser.opened.single.toString(), link);
      expect(http.clients, clientsBefore, reason: 'the phone fetched, previewed or expanded the link');
    });
  });

  // A link is text, so on someone else's bubble it takes the brand's text
  // colour (primaryStrong), which reads on the dark grey bubble; the brand
  // fill (primary) is too dark there. The user's own bubble draws it white.
  testWidgets('a link on someone else\'s bubble is drawn in the brand\'s text colour', (tester) async {
    await withLinks(tester, from: 'sam', texts: ['the flat is here https://flats.example.org/listing/42'],
        body: (world, trust) async {
      final paragraph = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .firstWhere((paragraph) => paragraph.text.toPlainText(includeSemanticsLabels: false).contains('flats.example.org'));
      TextSpan? link;
      paragraph.text.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').contains('flats.example.org')) link = span;
        return link == null;
      });
      expect(link, isNotNull);
      expect(link!.style?.color, VeilPalette.dark.primaryStrong);
      expect(link!.style?.color, isNot(VeilPalette.dark.primary));
      expect(link!.style?.decoration, TextDecoration.underline);
    });
  });

  // A host written to read as another: an escaped or ideographic full
  // stop, or a Cyrillic letter. The sheet is the strong one even from a
  // verified contact, its bold domain is the one the browser would open
  // (in its xn-- form when it is not plain ASCII), and its address line is
  // exactly the link that opens.
  testWidgets('a host written to look like another gets the strong sheet with the domain a browser would open',
      (tester) async {
    const escaped = 'https://naver.com%2Elogin-check.xyz/pay';
    const ideographic = 'https://naver.com\u3002secure-check.xyz/';
    const cyrillic = 'https://\u0430pple.com/login';
    await withLinks(tester, from: 'sam', texts: ['pay here $escaped', 'or $ideographic', cyrillic], body: (world, trust) async {
      for (final (part, domain) in [
        ('login-check.xyz/pay', 'login-check.xyz'),
        ('secure-check.xyz', 'secure-check.xyz'),
        ('pple.com/login', 'xn--pple-43d.com'),
      ]) {
        await tapLink(tester, part);
        expect(inSheet(find.text(en.linkRiskHiddenTitle)), findsOneWidget, reason: part);
        expect(tester.widget<Text>(find.byKey(const ValueKey('link-sheet-domain'))).data, domain, reason: part);
        final address = tester.widget<Text>(find.byKey(const ValueKey('link-sheet-address'))).data;
        await tester.tap(find.byKey(const ValueKey('link-sheet-open')));
        await pumpFrames(tester, frames: 4);
        expect(browser.opened.last.toString(), address, reason: 'the address shown is the link that opened');
      }
      expect(browser.opened, hasLength(3));
      expect(browser.opened.last.host, '%D0%B0pple.com', reason: 'opened as written; the browser names it xn--pple-43d');
    });
  });

  // An escape that decodes to a character no host may hold (/ or @) makes
  // a host a browser refuses. The bold line names it as the address escapes
  // it, never by the part after the decoded character (naver.com), and the
  // address line is still exactly the link that opens.
  testWidgets('a host a browser would refuse is named as escaped under the strong sheet', (tester) async {
    const slash = 'https://evil.xyz%2F.naver.com/';
    const at = 'https://naver.com%40evil.xyz/';
    await withLinks(tester, from: 'sam', texts: ['see $slash', 'or $at'], body: (world, trust) async {
      for (final (part, link) in [('xyz%2F.naver.com/', slash), ('com%40evil.xyz/', at)]) {
        await tapLink(tester, part);
        expect(inSheet(find.text(en.linkRiskHiddenTitle)), findsOneWidget, reason: part);
        expect(tester.widget<Text>(find.byKey(const ValueKey('link-sheet-domain'))).data, link.substring(8, link.length - 1),
            reason: part);
        expect(tester.widget<Text>(find.byKey(const ValueKey('link-sheet-address'))).data, link, reason: part);
        await tester.tap(find.byKey(const ValueKey('link-sheet-open')));
        await pumpFrames(tester, frames: 4);
        expect(browser.opened.last.toString(), link, reason: 'the address shown is the link that opened');
      }
    });
  });

  testWidgets('coming back from an opened link locks the app when app lock is on', (tester) async {
    usePhoneView(tester, phoneSmall);
    final platform = RecordingPlatformSecurity();
    addTearDown(platform.close);
    final grace = SystemSheetGrace(isIOS: false);
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      overrides: [
        platformSecurityServiceProvider.overrideWithValue(platform),
        systemSheetGraceProvider.overrideWithValue(grace),
        localNotificationServiceProvider.overrideWithValue(_QuietNotifications()),
        linkOpenerProvider.overrideWithValue(browser),
      ],
    );
    try {
      await attachContactTrust(world);
      await strangerWrites(world, 'sam', ['the flat is here https://flats.example.org/listing/42']);
      await tester.pumpWidget(UncontrolledProviderScope(container: world.container, child: const VeilApp()));
      await pumpFrames(tester, frames: 6);
      await tester.tap(find.text('Sam Rivera').first);
      await pumpFrames(tester, frames: 8);
      expect(find.byType(ChatRoomScreen), findsOneWidget);

      // Sam is verified: the link opens at once, in the browser.
      await tapLink(tester, 'flats.example.org');
      expect(browser.opened, hasLength(1));
      expect(world.container.read(appSessionProvider).locked, isFalse);

      // The browser comes to the front: Veil goes away as it does for Home,
      // with no system sheet's grace, and locks; coming back shows the lock.
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(world.container.read(appSessionProvider).locked, isTrue);
      for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(world.container.read(appSessionProvider).locked, isTrue);
      expect(find.byType(ChatRoomScreen), findsNothing, reason: 'the lock screen, not the chat');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });
}
