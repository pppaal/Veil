import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

import 'known_phone_layout_failures.dart';
import 'support/layout_seed.dart';
import 'support/layout_world.dart';
import 'support/phone_layout_probe.dart';
import 'support/screen_cases.dart';

// The phone layout gate. Every screen of the app is opened at three phone
// sizes in both languages, with the bundled fonts, and scrolled to its end.
// A case fails when the framework reports a layout error (an overflowing
// flex, unbounded constraints, a build that throws), when the messages of a
// chat or the rows of the conversation list get less than 45% of the screen
// height, or when a control of a screen laid out for phones (the chat, the
// conversation list, the lock) is smaller than 44x44. Cases known to fail
// are listed in known_phone_layout_failures.dart, which this gate only lets
// shrink; it is empty.
//
//   flutter test test/layout
//
// With --dart-define=SHOTS_DIR=/abs/dir the same run also writes one 2x PNG
// per case and a report.json (defects, measured shares, small tap targets,
// texts in the other language) into that directory. Adding
// --dart-define=SHOTS_PAGES=all writes a PNG for every further screenful of
// a scrolling screen. Without SHOTS_DIR no file is written.

const _locales = ['en', 'ko'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LayoutIdentities identities;
  final report = LayoutReport();

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
    prepareShotsDir();
  });
  tearDownAll(report.write);

  test('every screen of the app has a layout case', () {
    final screens = [
      for (final feature in Directory('lib/src/features').listSync().whereType<Directory>())
        if (Directory('${feature.path}/presentation') case final presentation when presentation.existsSync())
          for (final file in presentation.listSync().whereType<File>())
            if (file.path.endsWith('_screen.dart')) file.uri.pathSegments.last,
    ]..sort();
    final covered = {for (final screenCase in screenCases) screenCase.file};

    expect(screens, isNotEmpty, reason: 'run from apps/mobile');
    expect(screens.where((screen) => !covered.contains(screen)), isEmpty,
        reason: 'add a ScreenCase for each new screen in test/layout/support/screen_cases.dart');
    expect(covered.where((screen) => !screens.contains(screen)), isEmpty,
        reason: 'these cases name a screen file that no longer exists');
  });

  test('the allow-list names existing cases, once each', () {
    final caseIds = {for (final screenCase in screenCases) screenCase.id};
    expect(caseIds, hasLength(screenCases.length), reason: 'case ids must be unique');
    final listed = <String>{};
    for (final known in knownPhoneLayoutFailures) {
      final key = '${known.caseId} @ ${known.size} ${known.locale}';
      expect(caseIds, contains(known.caseId), reason: key);
      expect(phoneSizes, contains(known.size), reason: key);
      expect(_locales, contains(known.locale), reason: key);
      expect(known.defects, isNotEmpty, reason: key);
      expect(known.reason, isNotEmpty, reason: key);
      expect(listed.add(key), isTrue, reason: '$key is listed twice');
    }
  });

  // The chat cannot show its messages on a phone today, so nothing on
  // screen proves they are there. This does.
  testWidgets('the seeded account holds what the cases are about', (tester) async {
    for (final locale in _locales) {
      final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: locale);
      final messenger = world.messenger;
      expect(messenger.conversations, hasLength(peerNames.length));
      expect(messenger.realtimeConnected, isTrue);

      await messenger.loadConversationMessages(chatConversationId);
      final messages = messenger.messagesFor(chatConversationId);
      final opened = [for (final message in messages) await messenger.decryptMessage(message)];
      expect(messages, hasLength(chatLineCount));
      expect(opened.every((message) => message.isOk && message.body.isNotEmpty), isTrue);
      expect(opened.map((message) => message.body.length).reduce((a, b) => a > b ? a : b), greaterThan(150),
          reason: 'one message is long');
      expect(opened.where((message) => message.attachment != null), hasLength(1));
      expect(opened.where((message) => message.messageKind == MessageKind.system), hasLength(1));
      expect(messages.where((message) => message.isMine), isNotEmpty, reason: 'both sides wrote');
      expect(messages.where((message) => !message.isMine), isNotEmpty, reason: 'both sides wrote');
      expect(messages.where((message) => message.expiresAt != null), hasLength(1));
      expect(await messenger.isPeerVerified(chatConversationId), isTrue);
      expect(messenger.messagesFor(emptyChatConversationId), isEmpty);
      world.dispose();
    }
  });

  for (final screenCase in screenCases) {
    group(screenCase.id, () {
      for (final size in phoneSizes) {
        for (final locale in _locales) {
          testWidgets('$size $locale', (tester) async {
            final findings = await _render(tester, screenCase, size, locale, identities);
            final known = knownPhoneLayoutFailure(screenCase.id, size, locale);
            report.record(
              caseId: screenCase.id,
              screen: screenCase.file,
              size: size,
              locale: locale,
              findings: findings,
              knownFailure: known != null,
            );

            if (known == null) {
              expect(findings.isClean, isTrue,
                  reason: '${screenCase.id} does not fit a $size phone ($locale):\n${findings.describe()}');
            } else {
              expect(findings.isClean, isFalse,
                  reason: '${screenCase.id} now fits a $size phone ($locale): '
                      'remove it from knownPhoneLayoutFailures');
              expect(findings.defects, known.defects,
                  reason: '${screenCase.id} on a $size phone ($locale) fails in another way than listed '
                      '("${known.reason}"):\n${findings.describe()}');
            }
          });
        }
      }
    });
  }
}

Future<LayoutFindings> _render(
  WidgetTester tester,
  ScreenCase screenCase,
  PhoneSize size,
  String locale,
  LayoutIdentities identities,
) async {
  usePhoneView(tester, size, keyboardHeight: screenCase.keyboardHeight, textScale: screenCase.textScale);
  final findings = LayoutFindings();
  final name = '${screenCase.id}__${size}__$locale';
  final world = await LayoutWorld.create(
    identities: identities,
    account: screenCase.account,
    locale: locale,
    attention: screenCase.attention,
    bootstrapping: screenCase.bootstrapping,
    transferStarted: screenCase.transferStarted,
  );

  Future<void> audit() async {
    if (screenCase.holdsTapTargets) {
      for (final target in await smallTapTargetsOnScreen(tester, guideline: minimumTapTarget)) {
        findings.add(LayoutDefect.smallTapTarget, 'smaller than 44x44: $target');
      }
    }
    if (!writesShots) return;
    findings.smallTapTargets.addAll(await smallTapTargetsOnScreen(tester));
    findings.otherLanguageTexts.addAll(otherLanguageTextsOnScreen(tester, locale));
  }

  // A test draws every shadow as a solid block. A shot is for looking at,
  // so it gets the real ones; the binding wants its setting back.
  if (writesShots) debugDisableShadows = false;
  try {
    await collectingLayoutErrors(findings, () async {
      await tester.pumpWidget(world.app(
        location: screenCase.location,
        extra: screenCase.extra,
        extraRoutes: layoutOnlyRoutes,
      ));
      await pumpFrames(tester);
      await screenCase.settle?.call(tester);
      expect(find.byType(screenCase.screen), findsOneWidget, reason: '${screenCase.location} did not open its screen');

      final measure = screenCase.primaryExtent;
      if (measure != null) {
        final extent = measure(tester);
        final share = extent / screenHeight(tester);
        findings.primaryShare = share;
        final minShare = screenCase.minPrimaryShare;
        final minExtent = screenCase.minPrimaryExtent;
        if (minShare != null && share < minShare) {
          findings.add(
            LayoutDefect.primaryContentSqueezed,
            'primary content gets ${(share * 100).toStringAsFixed(0)}% of the screen height, '
            'under ${(minShare * 100).toStringAsFixed(0)}%',
          );
        }
        if (minExtent != null && extent < minExtent) {
          findings.add(
            LayoutDefect.primaryContentSqueezed,
            'primary content gets ${extent.toStringAsFixed(0)} logical px, under ${minExtent.toStringAsFixed(0)}',
          );
        }
      }
      if (writesShots) {
        await writeShot(tester, name);
        findings.mainListShare = mainListShare(tester);
      }
      await audit();

      // Rows below the fold are only laid out once they scroll into view.
      await scrollToEnd(tester, onPage: (page) async {
        if (shootsEveryPage) await writeShot(tester, '$name~$page');
        await audit();
      });

      // Inside the collection, so that an error thrown while the screen
      // is disposed counts against it too.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  } finally {
    // The test ends with its timers checked, so the screen and then its
    // world (the messenger's timers) go before it ends, whatever happened.
    await tester.pumpWidget(const SizedBox.shrink());
    world.dispose();
    debugDisableShadows = true;
  }
  return findings;
}
