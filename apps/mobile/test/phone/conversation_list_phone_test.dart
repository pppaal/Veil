import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/calls/calls_feature.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_direct_chat_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_group_screen.dart';
import 'package:veil_mobile/src/features/security_status/presentation/security_status_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import 'phone_app.dart';

// The conversation list on a phone: conversations first, and what the hero
// card, the stat tiles and the buttons at the end of the list carried is in
// the status line and the bar.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  testWidgets('starts with the conversations, under one line of status and the search', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      expect(find.byType(VeilHeroPanel), findsNothing);
      expect(find.byType(VeilMetricStrip), findsNothing);
      // What the hero card said: the relay, the count, and that nothing is
      // backed up.
      expect(find.text('Relay linked  ·  8 conversations  ·  No backup'), findsOneWidget,
          reason: 'one line at the default text size');
      expect(find.widgetWithText(TextField, 'Search chats and messages'), findsOneWidget);

      final rows = find.byType(VeilConversationCard);
      final firstRow = onScreen(tester, rows);
      expect(firstRow.top, lessThan(screenHeight(tester) * 0.3), reason: 'the first conversation is near the top');
      final whole = [
        for (final element in rows.evaluate())
          if (element.renderObject case final RenderBox box when visibleRect(tester, box).height == box.size.height)
            box,
      ];
      expect(whole.length, greaterThanOrEqualTo(4), reason: 'a 360x640 phone shows at least four whole rows');
      expect(tester.takeException(), isNull);
    });
  });

  // Where the line is too long (360 px at 1.3x) it breaks between two
  // parts, and the dot that separates parts is drawn only between two that
  // share a line: no line ends with one, and none starts with one.
  for (final (locale, lines) in [
    ('en', ['Relay linked  ·  8 conversations', 'No backup']),
    ('ko', ['릴레이 연결됨  ·  대화 8개  ·  백업 없음']),
  ]) {
    testWidgets('with larger text the status line wraps between its parts, with no separator left hanging ($locale)',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/conversations', locale: locale, textScale: 1.3,
          body: (world) async {
        final rects = [for (final line in lines) tester.getRect(find.text(line))];
        for (final (index, rect) in rects.indexed) {
          expect(rect.height, rects.first.height, reason: '"${lines[index]}" is one line');
          expect(rect.right, lessThanOrEqualTo(360), reason: '"${lines[index]}" fits the screen');
          if (index > 0) expect(rect.top, greaterThanOrEqualTo(rects[index - 1].bottom));
        }
        // Nothing drawn on the list starts or ends with the separator.
        final hanging = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .where((data) => data.trim().startsWith('·') || data.trim().endsWith('·'));
        expect(hanging, isEmpty);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('starts a direct chat or a group from the bar', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('New conversation'));
      await pumpFrames(tester, frames: 3);
      expect(find.text('New group'), findsOneWidget);
      await tester.tap(find.text('New direct chat'));
      await pumpFrames(tester);
      expect(find.byType(StartDirectChatScreen), findsOneWidget);
    });
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('New conversation'));
      await pumpFrames(tester, frames: 3);
      await tester.tap(find.text('New group'));
      await pumpFrames(tester);
      expect(find.byType(StartGroupScreen), findsOneWidget);
    });
  });

  // Settings is a tab of the bottom bar, so the bar above keeps only what
  // has no tab: security status.
  testWidgets('keeps security status in the bar, and has settings as a tab', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('Security status'));
      await pumpFrames(tester);
      expect(find.byType(SecurityStatusScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester);

      expect(find.byTooltip('Settings'), findsNothing, reason: 'no second way to settings in the bar');
      await tester.tap(find.text('Settings'));
      await pumpFrames(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  testWidgets('a search shows its filters, says it stays on the device, and lists what it found',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.enterText(find.byType(TextField), 'se');
      // The archive search waits 180 ms for the typing to stop.
      await pumpFrames(tester, frames: 4);

      expect(find.text('All senders'), findsOneWidget);
      expect(find.text('Search stays on this device.'), findsOneWidget);
      expect(find.text('CONVERSATIONS'), findsOneWidget);
      expect(find.text('2 matches'), findsOneWidget);
      expect(find.text('MESSAGES'), findsOneWidget);
      expect(find.byType(VeilConversationCard), findsNWidgets(2));
      // The status line still counts every conversation, not the matches.
      expect(find.textContaining('8 conversations'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await pumpFrames(tester, frames: 4);
      expect(find.text('All senders'), findsNothing);
      expect(find.text('MESSAGES'), findsNothing);
    });
  });

  testWidgets('with no conversation yet, offers to start one', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      account: LayoutAccount.signedInEmpty,
      body: (world) async {
        expect(find.text('No conversations yet'), findsOneWidget);
        await tester.tap(find.text('Start direct chat'));
        await pumpFrames(tester);
        expect(find.byType(StartDirectChatScreen), findsOneWidget);
      },
    );
  });

  testWidgets('is in Korean in a Korean app, tabs included', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', locale: 'ko', body: (world) async {
      expect(find.text('릴레이 연결됨  ·  대화 8개  ·  백업 없음'), findsOneWidget);
      expect(find.widgetWithText(TextField, '대화와 메시지 검색'), findsOneWidget);
      for (final tab in ['채팅', '연락처', '설정']) {
        expect(find.text(tab), findsOneWidget);
      }
      expect(find.text('통화'), kCallsEnabled ? findsOneWidget : findsNothing,
          reason: 'the Calls tab is there only while calls are switched on (kCallsEnabled)');
      expect(find.text('Chats'), findsNothing);
      expect(find.byTooltip('새 대화'), findsOneWidget);
    });
  });
}
