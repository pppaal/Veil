import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final status = ['Relay linked  ·  ', '8 conversations  ·  ', 'No backup'];
      for (final part in status) {
        expect(find.text(part), findsOneWidget);
      }
      expect({for (final part in status) tester.getTopLeft(find.text(part)).dy}, hasLength(1),
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

  testWidgets('with larger text the status line wraps between its parts, never inside one', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', textScale: 1.3, body: (world) async {
      final relay = tester.getRect(find.text('Relay linked  ·  '));
      final noBackup = tester.getRect(find.text('No backup'));
      expect(noBackup.top, greaterThan(relay.top), reason: 'the line is too long for 360 px at this size');
      expect(noBackup.height, relay.height, reason: '"No backup" is on one line');
      expect(noBackup.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    });
  });

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
        expect(find.text('No direct conversations yet'), findsOneWidget);
        await tester.tap(find.text('Start direct chat'));
        await pumpFrames(tester);
        expect(find.byType(StartDirectChatScreen), findsOneWidget);
      },
    );
  });

  testWidgets('is in Korean in a Korean app, tabs included', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', locale: 'ko', body: (world) async {
      for (final part in ['릴레이 연결됨  ·  ', '대화 8개  ·  ', '백업 없음']) {
        expect(find.text(part), findsOneWidget);
      }
      expect(find.widgetWithText(TextField, '대화와 메시지 검색'), findsOneWidget);
      for (final tab in ['채팅', '연락처', '설정']) {
        expect(find.text(tab), findsOneWidget);
      }
      expect(find.text('통화'), findsNothing, reason: 'calls are switched off (kCallsEnabled)');
      expect(find.text('Chats'), findsNothing);
      expect(find.byTooltip('새 대화'), findsOneWidget);
    });
  });
}
