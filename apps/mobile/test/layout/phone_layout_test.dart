import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import 'known_other_language_text.dart';
import 'known_phone_layout_failures.dart';
import 'support/layout_seed.dart';
import 'support/layout_world.dart';
import 'support/phone_layout_probe.dart';
import 'support/screen_cases.dart';

// The layout gate. Every screen of the app is opened at three phone sizes
// in both languages, with the bundled fonts, and scrolled to its end. A
// case fails
// - when the framework reports a layout error (an overflowing flex,
//   unbounded constraints, a build that throws);
// - when the messages of a chat or the rows of the conversation list get
//   less than 45% of the screen height;
// - when a control is smaller than 44x44 (on every screen but the one
//   listed in tapTargetExemptScreens);
// - when the action of a chat's warning is not wholly on screen where a tap
//   reaches it;
// - when the control a screen is for (the first input or primary button its
//   case names) is not on the first screenful;
// - when a text of the app's own copy is in the other language (see
//   support/language_probe.dart for what is not the app's own copy).
//
// Each case is rendered once more in the light theme (390x844, Korean, every
// screenful), held to layout errors and tap targets. Nothing reads colours:
// that a light render passes does not say its text can be read, so look at
// the PNGs. The wide cases open the two-pane shell and a tablet, held to
// layout errors, the messages' share, the warning actions and tap targets.
//
// Cases known to fail are listed in known_phone_layout_failures.dart, and
// the texts screens are known to show in the other language in
// known_other_language_text.dart. The gate only lets both lists shrink.
//
//   flutter test test/layout
//
// With --dart-define=SHOTS_DIR=/abs/dir the same run also writes one 2x PNG
// per case and a report.json (defects, measured shares, small tap targets,
// texts in the other language) into that directory. Adding
// --dart-define=SHOTS_PAGES=all writes a PNG for every further screenful of
// a scrolling screen. Without SHOTS_DIR no file is written.

const _locales = ['en', 'ko'];

/// The one size and language of the light-theme renders.
const _lightSize = phoneMedium;
const _lightLocale = 'ko';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LayoutIdentities identities;
  final report = LayoutReport();
  final language = _LanguageLedger();

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

  test('the allow-lists name existing cases and screens, once each', () {
    final cases = {for (final screenCase in allCases) screenCase.id: screenCase};
    expect(cases, hasLength(allCases.length), reason: 'case ids must be unique');
    final listed = <String>{};
    for (final known in knownPhoneLayoutFailures) {
      final screenCase = cases[known.caseId];
      expect(screenCase, isNotNull, reason: '${known.caseId} is not a case');
      expect(known.defects, isNotEmpty, reason: known.caseId);
      expect(known.reason, isNotEmpty, reason: known.caseId);
      expect(known.sizes, isNotEmpty, reason: known.caseId);
      expect(known.locales, isNotEmpty, reason: known.caseId);
      for (final size in known.sizes) {
        for (final locale in known.locales) {
          final key = '${known.caseId} @ $size $locale${known.light ? ' light' : ''}';
          expect(_locales, contains(locale), reason: key);
          if (known.light) {
            expect(screenCases, contains(screenCase), reason: '$key: only the phone cases have a light render');
            expect((size, locale), (_lightSize, _lightLocale), reason: '$key: the light render is one size and language');
          } else {
            expect(screenCase!.sizes, contains(size), reason: '$key: the case is not rendered at that size');
          }
          expect(listed.add(key), isTrue, reason: '$key is listed twice');
        }
      }
    }

    final files = {for (final screenCase in allCases) screenCase.file};
    for (final MapEntry(key: file, value: byLocale) in knownOtherLanguageText.entries) {
      expect(files, contains(file), reason: '$file has no case');
      expect(byLocale, isNotEmpty, reason: file);
      for (final MapEntry(key: locale, value: texts) in byLocale.entries) {
        expect(_locales, contains(locale), reason: file);
        expect(texts, isNotEmpty, reason: '$file $locale: delete the entry instead of listing none');
        for (final text in texts) {
          expect(isOtherLanguage(text, locale), isTrue,
              reason: '$file $locale: "$text" is not text in the other language, and cannot be listed as one');
        }
      }
    }
  });

  // The list names texts, not a number of them: a screen cannot trade a
  // listed text for a new one, and only a run of every case can tell that a
  // listed text is gone.
  test('the language ledger fails a text that is not listed, and a listed one that is gone', () {
    // Whichever screen is listed first: a screen leaves the list once it is
    // localized, so no one screen can be named here.
    final file = knownOtherLanguageText.keys.first;
    final cases = [for (final screenCase in allCases) if (screenCase.file == file) screenCase];
    expect(cases, isNotEmpty);
    final listed = knownOtherLanguageText[file]!['ko']!;

    LayoutFindings showing(Set<String> texts) => LayoutFindings()..otherLanguageTexts.addAll(texts);
    _LanguageLedger renderAll(Set<String> koTexts) {
      final ledger = _LanguageLedger();
      for (final screenCase in cases) {
        for (final size in screenCase.sizes) {
          for (final locale in _locales) {
            final findings = showing(locale == 'ko' ? koTexts : {});
            ledger.record(screenCase, size, locale, findings);
            expect(findings.defects, isEmpty, reason: 'listed texts are no defect');
          }
        }
      }
      return ledger;
    }

    expect(renderAll(listed).problems().where((problem) => problem.contains(file)), isEmpty);

    // One more text than listed fails the case that shows it, at once.
    final more = showing({...listed, 'Hard-coded English'});
    _LanguageLedger().record(cases.first, cases.first.sizes.first, 'ko', more);
    expect(more.defects, {LayoutDefect.otherLanguage});
    expect(more.describe(), contains('not Korean: "Hard-coded English"'));
    expect(more.describe(), isNot(contains(listed.first)));

    // A listed text swapped for another: the new one fails its case, and
    // the full run says the old one is gone.
    final swapped = showing({'Another English text'});
    final ledger = renderAll(const {});
    ledger.record(cases.first, cases.first.sizes.first, 'ko', swapped);
    expect(swapped.defects, {LayoutDefect.otherLanguage});
    final gone = ledger.problems().where((problem) => problem.contains(file)).toList();
    expect(gone, hasLength(1));
    expect(gone.single, contains('no longer shows'));
    expect(gone.single, contains('"${listed.first}"'));

    // A run that left some of the screen's renders out has not seen all of
    // its texts, and says nothing about what is gone.
    final partial = _LanguageLedger()..record(cases.first, cases.first.sizes.first, 'ko', showing(const {}));
    expect(partial.problems().where((problem) => problem.contains(file)), isEmpty);

    // On a screen with no entry, any such text is a defect.
    final unlisted = allCases.firstWhere((screenCase) => !knownOtherLanguageText.containsKey(screenCase.file));
    final findings = showing({'보내기'});
    _LanguageLedger().record(unlisted, unlisted.sizes.first, 'en', findings);
    expect(findings.describe(), contains('not English: "보내기"'));
  });

  // The framework's own tap target check passes over a control that
  // touches any edge of the list it is in, so a short button set flush left
  // in a scrolling screen went unseen. The gate's check must see it, and
  // must still leave out what the list has half scrolled away.
  testWidgets('the tap target check sees a small control flush with the side of its list', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(40),
          child: ListView(
            children: [
              const SizedBox(height: 60),
              Align(alignment: Alignment.centerLeft, child: _smallButton('flush left')),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    ));
    expect(await smallTapTargetsOnScreen(tester, minimum: minimumTapTarget), {'Size(120.0, 30.0) (flush left)'});
    expect(await smallTapTargetsOnScreen(tester, minimum: 30), isEmpty);

    // Half scrolled out at the top of the list, it is not measured: what
    // is on screen of it says nothing about its size.
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(75);
    await tester.pump();
    expect(await smallTapTargetsOnScreen(tester, minimum: minimumTapTarget), isEmpty);
  });

  // It also passes over whatever touches an edge of the screen, which is
  // where a bar's last action and a full-width row's button sit. Only a
  // modal's scrim is left out there: it is what the modal leaves uncovered.
  testWidgets('the tap target check sees a small control at an edge of the screen', (tester) async {
    usePhoneView(tester, phoneMedium);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            for (final (label, alignment) in [
              ('at the top right', Alignment.topRight),
              ('at the bottom left', Alignment.bottomLeft),
              ('at the right', Alignment.centerRight),
            ])
              Align(alignment: alignment, child: _smallButton(label)),
          ],
        ),
      ),
    ));
    expect(await smallTapTargetsOnScreen(tester, minimum: minimumTapTarget), {
      'Size(120.0, 30.0) (at the top right)',
      'Size(120.0, 30.0) (at the bottom left)',
      'Size(120.0, 30.0) (at the right)',
    });

    // A sheet that covers all but a strip: the strip is the scrim, which
    // dismisses the sheet and has no size of its own to hold to 44 px.
    final context = tester.element(find.byType(Stack).first);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(height: phoneMedium.height - 20, child: const Center(child: Text('sheet'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(await smallTapTargetsOnScreen(tester, minimum: minimumTapTarget), isEmpty);
  });

  test('the language check tells the app\'s copy from what it only shows', () {
    // Fixtures, data and the brand are nobody's translation.
    for (final shown in [
      'VEIL',
      'Selene Park',
      'Selene',
      'S',
      '@selene',
      'Maximilian Alexander von Hohenberg-Schwarzenfeld',
      'lease-signed.pdf',
      '2.3 MB · application/pdf',
      'Pixel 9 Pro Fold',
      'iPhone / iPad',
      'PIN',
      'cold.operator',
      'dev-atlas',
      'The registry entry is at https://registry.example.org/property/KR-11680-2026-0419-0031/owners?verify=true',
      '08:49',
    ]) {
      expect(isOtherLanguage(shown, 'ko'), isFalse, reason: '"$shown" is not the app\'s copy');
    }
    for (final shown in ['한지우', '김', '김서연 (디자인팀)', '주말 등산', '내일 회의 자료는 여기로 보낼게']) {
      expect(isOtherLanguage(shown, 'en'), isFalse, reason: '"$shown" is not the app\'s copy');
    }

    // The app's own words are, whatever they stand beside.
    for (final copy in ['Send', 'Conversation with Selene Park', 'Connected 00:02', 'VEIL Assistant', '2h ago']) {
      expect(isOtherLanguage(copy, 'ko'), isTrue, reason: '"$copy" is English copy');
    }
    for (final copy in ['보내기', 'Selene Park님과의 대화', '2시간 전']) {
      expect(isOtherLanguage(copy, 'en'), isTrue, reason: '"$copy" is Korean copy');
    }
    // A sentence in the run's language may name what is Latin by nature.
    expect(isOtherLanguage('VEIL 릴레이에 연결됨', 'ko'), isFalse);
    expect(isOtherLanguage('PIN 입력', 'ko'), isFalse);
    expect(isOtherLanguage('Relay linked · 8 conversations', 'en'), isFalse);
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

      final withGroup = await LayoutWorld.create(
        identities: identities,
        account: LayoutAccount.signedIn,
        locale: locale,
        withGroup: true,
      );
      final group = withGroup.messenger.conversationById(groupConversationId);
      expect(group?.type, ConversationType.group);
      expect(group?.members, hasLength(groupMemberHandles.length + 1));
      expect(withGroup.messenger.conversations.first.id, groupConversationId, reason: 'the group is the newest');
      withGroup.dispose();
    }
  });

  for (final screenCase in allCases) {
    group(screenCase.id, () {
      for (final size in screenCase.sizes) {
        for (final locale in _locales) {
          testWidgets('$size $locale', (tester) async {
            final findings = await _render(tester, screenCase, size, locale, identities);
            language.record(screenCase, size, locale, findings);
            final known = knownPhoneLayoutFailure(screenCase.id, size, locale);
            report.record(
              caseId: screenCase.id,
              screen: screenCase.file,
              size: size,
              locale: locale,
              findings: findings,
              knownFailure: known != null,
            );
            _expectAsListed(findings, known, '${screenCase.id} on a $size screen ($locale)');
          });
        }
      }
    });
  }

  // The light theme shares every layout with the dark one, so one render of
  // each case, scrolled to its end, is enough to catch what only the theme
  // changes: a control or a border that takes a different size.
  group('light theme', () {
    for (final screenCase in screenCases) {
      testWidgets(screenCase.id, (tester) async {
        final findings = await _render(tester, screenCase, _lightSize, _lightLocale, identities, light: true);
        final known = knownPhoneLayoutFailure(screenCase.id, _lightSize, _lightLocale, light: true);
        report.record(
          caseId: screenCase.id,
          screen: screenCase.file,
          size: _lightSize,
          locale: _lightLocale,
          findings: findings,
          knownFailure: known != null,
          light: true,
        );
        _expectAsListed(findings, known, '${screenCase.id} in the light theme');
      });
    }
  });

  // After every case: the texts each screen showed in the other language,
  // added up over its cases and sizes, against the texts listed for it.
  test('each screen shows the other language exactly as listed', () {
    final problems = language.problems();
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

// A small tap target with a semantics node of its own, as a button's is.
Widget _smallButton(String label) => SizedBox(
      width: 120,
      height: 30,
      child: Semantics(
        container: true,
        button: true,
        label: label,
        onTap: () {},
        child: const ColoredBox(color: Color(0xFF444444)),
      ),
    );

void _expectAsListed(LayoutFindings findings, KnownPhoneLayoutFailure? known, String what) {
  if (known == null) {
    expect(findings.isClean, isTrue, reason: '$what does not pass the layout gate:\n${findings.describe()}');
    return;
  }
  expect(findings.isClean, isFalse, reason: '$what now passes: remove it from knownPhoneLayoutFailures');
  expect(findings.defects, known.defects,
      reason: '$what fails in another way than listed ("${known.reason}"):\n${findings.describe()}');
}

/// What every screen showed in the other language, over all of its cases.
class _LanguageLedger {
  // screen file -> locale -> the listed texts that were shown
  final Map<String, Map<String, Set<String>>> _shown = {};
  final Set<String> _rendered = {};

  /// Takes the case's texts in the other language. One that is not listed
  /// for the case's screen in knownOtherLanguageText fails the case on the
  /// spot; the listed ones are held until the end of the run, which says
  /// which of them no case showed any more.
  void record(ScreenCase screenCase, PhoneSize size, String locale, LayoutFindings findings) {
    _rendered.add('${screenCase.id} $size $locale');
    final listed = knownOtherLanguageText[screenCase.file]?[locale] ?? const <String>{};
    for (final text in findings.otherLanguageTexts) {
      if (listed.contains(text)) {
        _shown.putIfAbsent(screenCase.file, () => {}).putIfAbsent(locale, () => {}).add(text);
      } else {
        findings.add(
          LayoutDefect.otherLanguage,
          '${locale == 'ko' ? 'not Korean' : 'not English'}: "$text" '
          '(move it to app_en.arb and app_ko.arb)',
        );
      }
    }
  }

  List<String> problems() {
    final problems = <String>[];
    for (final MapEntry(key: file, value: byLocale) in knownOtherLanguageText.entries) {
      // A run that left out some of the screen's cases (--name) has not
      // seen all of its texts, and cannot say one is gone.
      final complete = allCases.where((screenCase) => screenCase.file == file).every((screenCase) =>
          screenCase.sizes.every((size) => _locales.every((locale) => _rendered.contains('${screenCase.id} $size $locale'))));
      if (!complete) continue;
      for (final MapEntry(key: locale, value: listed) in byLocale.entries) {
        final gone = listed.difference(_shown[file]?[locale] ?? const <String>{}).toList()..sort();
        if (gone.isEmpty) continue;
        problems.add('$file no longer shows these texts in a $locale run: delete them from knownOtherLanguageText'
            '${gone.length == listed.length ? ', and the $locale entry of the screen with them' : ''}\n'
            '${gone.map((text) => '    "$text"').join('\n')}');
      }
    }
    return problems;
  }
}

Future<LayoutFindings> _render(
  WidgetTester tester,
  ScreenCase screenCase,
  PhoneSize size,
  String locale,
  LayoutIdentities identities, {
  bool light = false,
}) async {
  usePhoneView(tester, size, keyboardHeight: screenCase.keyboardHeight, textScale: screenCase.textScale);
  final findings = LayoutFindings();
  final name = '${screenCase.id}__${size}__$locale${light ? '__light' : ''}';
  final world = await LayoutWorld.create(
    identities: identities,
    account: screenCase.account,
    locale: locale,
    attention: screenCase.attention,
    bootstrapping: screenCase.bootstrapping,
    transferStarted: screenCase.transferStarted,
    withGroup: screenCase.withGroup,
  );

  Future<void> audit() async {
    if (screenCase.holdsTapTargets) {
      for (final target in await smallTapTargetsOnScreen(tester, minimum: minimumTapTarget)) {
        findings.add(LayoutDefect.smallTapTarget, 'smaller than 44x44: $target');
      }
    }
    // The light render is held to layout errors and tap targets only: the
    // dark renders of the same case already read its language.
    if (!light) findings.otherLanguageTexts.addAll(otherLanguageTextsOnScreen(tester, locale));
    if (writesShots) findings.smallTapTargets.addAll(await smallTapTargetsOnScreen(tester));
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
        themeMode: light ? ThemeMode.light : ThemeMode.dark,
      ));
      await pumpFrames(tester);
      world.startLiveAttention();
      await tester.pump();

      // Where the screen opens, before the case taps or types anything.
      final primaryAction = screenCase.primaryAction;
      if (!light && primaryAction != null && screenCase.keyboardHeight == 0) {
        final problem = primaryActionProblem(tester, primaryAction(), size);
        if (problem != null) {
          findings.add(LayoutDefect.primaryActionBelowFold, 'the control the screen is for $problem');
        }
      }

      await screenCase.settle?.call(tester);
      expect(find.byType(screenCase.screen), findsOneWidget, reason: '${screenCase.location} did not open its screen');

      final measure = screenCase.primaryExtent;
      if (!light && measure != null) {
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
      // A warning is on screen for its action: every one the case's chat
      // carries must be there, whole, where a tap reaches it.
      final wantedActions = light ? 0 : screenCase.warningActionCount;
      if (wantedActions > 0) {
        final actions = chatWarningActions().evaluate().toList();
        if (actions.length != wantedActions) {
          findings.add(
            LayoutDefect.hiddenAction,
            'the chat shows ${actions.length} warning actions, not the $wantedActions its warnings come with',
          );
        }
        for (final action in actions) {
          final label = switch ((action.widget as TextButton).child) { Text(:final data?) => data, _ => '?' };
          final problem = whyNotWhollyTappable(tester, action.renderObject! as RenderBox);
          if (problem != null) findings.add(LayoutDefect.hiddenAction, 'the warning action "$label" $problem');
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
