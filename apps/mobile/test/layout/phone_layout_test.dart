import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import 'known_phone_layout_failures.dart';
import 'support/layout_seed.dart';
import 'support/layout_world.dart';
import 'support/phone_layout_probe.dart';
import 'support/screen_cases.dart';

// The layout gate. Every screen of the app is opened at three phone sizes,
// with the bundled fonts, and scrolled to its end. A case fails
// - when the framework reports a layout error (an overflowing flex,
//   unbounded constraints, a build that throws);
// - when the messages of a chat or the rows of the conversation list get
//   less than 45% of the screen height;
// - when a control is smaller than 44x44 (on every screen: none is left in
//   tapTargetExemptScreens);
// - when the action of a chat's warning is not wholly on screen where a tap
//   reaches it;
// - when the control a screen is for (the first input or primary button its
//   case names) is not on the first screenful.
//
// Each case is rendered once more in the light theme (390x844, every
// screenful), held to layout errors and tap targets. Nothing reads colours:
// that a light render passes does not say its text can be read, so look at
// the PNGs. The wide cases open the two-pane shell and a tablet, held to
// layout errors, the messages' share, the warning actions and tap targets.
//
// Cases known to fail are listed in known_phone_layout_failures.dart. The
// gate only lets that list shrink, and it is empty: a test below keeps it
// so.
//
//   flutter test test/layout
//
// With --dart-define=SHOTS_DIR=/abs/dir the same run also writes one 2x PNG
// per case and a report.json (defects, measured shares, small tap targets)
// into that directory. Adding --dart-define=SHOTS_PAGES=all writes a PNG for
// every further screenful of a scrolling screen. Without SHOTS_DIR no file
// is written.

const _locales = ['en'];

/// The one size and language of the light-theme renders.
const _lightSize = phoneMedium;
const _lightLocale = 'en';

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

  // Each feature adds its cases in a file of its own; an id taken twice
  // would make two renders write one PNG and one report entry.
  test('no two cases share an id', () {
    final seen = <String>{};
    final repeated = [for (final screenCase in allCases) if (!seen.add(screenCase.id)) screenCase.id];
    expect(repeated, isEmpty, reason: 'case ids must be unique');
  });

  test('the allow-list names existing cases, once each', () {
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
  });

  // Every case fits. A screen that stops doing so is fixed, not listed: the
  // list exists to say what was known to fail while it was being fixed, and
  // nothing is.
  test('nothing is listed as known to fail', () {
    expect(knownPhoneLayoutFailures, isEmpty, reason: 'fix the screen instead of listing its case');
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
      expect(opened.where((message) => message.body.contains(longLinkHost)), hasLength(1), reason: 'one link is long');
      expect(opened.where((message) => message.messageKind == MessageKind.system), isEmpty,
          reason: 'the chat of the everyday cases has no notice');
      expect(messages.where((message) => message.isMine), isNotEmpty, reason: 'both sides wrote');
      expect(messages.where((message) => !message.isMine), isNotEmpty, reason: 'both sides wrote');
      expect(messages.where((message) => message.expiresAt != null), hasLength(1));
      expect(await messenger.isPeerVerified(chatConversationId), isTrue);
      expect(messenger.messagesFor(emptyChatConversationId), isEmpty);

      await messenger.loadConversationMessages(noticeChatConversationId);
      final notices = [
        for (final message in messenger.messagesFor(noticeChatConversationId))
          if (await messenger.decryptMessage(message) case DecryptedMessage(isOk: true, messageKind: MessageKind.system))
            message,
      ];
      expect(notices, hasLength(1), reason: 'the notice case has its notice');
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
    transferClaimed: screenCase.transferClaimed,
    withGroup: screenCase.withGroup,
    searchesArchive: screenCase.searchesArchive,
    beforeSession: screenCase.beforeSession,
    overrides: screenCase.overrides?.call() ?? const [],
  );
  // What happens after the first list and before the screen opens.
  await screenCase.afterSession?.call(world);

  Future<void> audit() async {
    if (screenCase.holdsTapTargets) {
      for (final target in await smallTapTargetsOnScreen(tester, minimum: minimumTapTarget)) {
        findings.add(LayoutDefect.smallTapTarget, 'smaller than 44x44: $target');
      }
    }
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
