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
      expect(find.text('Relay linked  ·  8 conversations  ·  No backup'), findsOneWidget);
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

  testWidgets('keeps security status and settings in the bar', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('Security status'));
      await pumpFrames(tester);
      expect(find.byType(SecurityStatusScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester);

      await tester.tap(find.byTooltip('Settings'));
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
      expect(find.text('릴레이 연결됨  ·  대화 8개  ·  백업 없음'), findsOneWidget);
      expect(find.widgetWithText(TextField, '대화와 메시지 검색'), findsOneWidget);
      for (final tab in ['채팅', '연락처', '통화']) {
        expect(find.text(tab), findsOneWidget);
      }
      expect(find.text('Chats'), findsNothing);
      expect(find.byTooltip('새 대화'), findsOneWidget);
    });
  });
}
