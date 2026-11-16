import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/domain/message_search.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_parts.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';

import '../layout/support/layout_seed.dart';
import 'phone_app.dart';

// When things were sent, on the Chats list, on a message the search found
// and in a chat's bubbles, as Signal and WhatsApp say it: the time for
// today, "Yesterday", the weekday within the week, then the date; the time
// in the phone's own 12- or 24-hour form. The clock is the phone's
// (wallClockProvider); the layout world sets it to the seed's Tuesday
// morning, 10:20.

// A screen tall enough that every conversation has its row built.
const _tall = PhoneSize(412, 1400, topInset: 32, bottomInset: 24);

Map<String, String> _rowTimes(WidgetTester tester) => {
      for (final row in tester.widgetList<ConversationRow>(find.byType(ConversationRow))) row.title: row.timestamp,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  testWidgets('a Chats row shows the time today, then Yesterday, the weekday and the date', (tester) async {
    await withPhoneApp(tester, identities, size: _tall, location: '/conversations', body: (world) async {
      final times = _rowTimes(tester);
      expect(times['Sam Rivera'], '9:45 AM');
      expect(times['Priya Nair'], '8:42 AM');
      expect(times['Mia Chen'], 'Yesterday');
      expect(times['tom_walsh'], 'Sat');
      // A chat with nothing in it has no time to show.
      expect(times['Lena Fischer'], '');
      expect(find.text('9:45 AM'), findsOneWidget, reason: 'drawn on its row');
    });
  });

  testWidgets('a row from more than a week back shows its date', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      size: _tall,
      location: '/conversations',
      // The same chats, looked at nine days later.
      prepare: (world) async {
        world.now = layoutNow.add(const Duration(days: 9));
        return null;
      },
      body: (world) async {
        final times = _rowTimes(tester);
        expect(times['Sam Rivera'], 'Apr 7');
        expect(times['Mia Chen'], 'Apr 6');
        expect(times['tom_walsh'], 'Apr 4');
      },
    );
  });

  // The list reads the clock it is given, not the time the test runs at.
  testWidgets('the rows follow the phone\'s clock into the next day', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      size: _tall,
      location: '/conversations',
      prepare: (world) async {
        world.now = DateTime.utc(2026, 4, 8, 7, 30);
        return null;
      },
      body: (world) async {
        final times = _rowTimes(tester);
        expect(times['Sam Rivera'], 'Yesterday');
        expect(times['Mia Chen'], 'Mon');
        expect(times['tom_walsh'], 'Sat');
      },
    );
  });

  // Nothing arrives and nothing is touched: the rows still move to the new
  // day when the phone's clock passes midnight.
  testWidgets('a list left open across midnight says "Yesterday" from midnight on', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      size: _tall,
      location: '/conversations',
      prepare: (world) async {
        // Ten seconds before midnight. The clock here stands still while
        // the test's time runs, so it is moved past midnight by hand once
        // what the opening of the app set going has settled, before the ten
        // seconds are up.
        world.now = DateTime(2026, 4, 7, 23, 59, 50);
        return null;
      },
      body: (world) async {
        await tester.pump(const Duration(seconds: 5));
        expect(_rowTimes(tester)['Sam Rivera'], '9:45\u00a0AM');
        world.now = DateTime(2026, 4, 8, 0, 0, 1);
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(_rowTimes(tester)['Sam Rivera'], 'Yesterday');
        expect(_rowTimes(tester)['Mia Chen'], 'Mon');
      },
    );
  });

  testWidgets('with the phone set to 24-hour time, rows and bubbles show it', (tester) async {
    tester.platformDispatcher.alwaysUse24HourFormatTestValue = true;
    addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);
    await withPhoneApp(tester, identities, size: _tall, location: '/conversations', body: (world) async {
      final times = _rowTimes(tester);
      expect(times['Sam Rivera'], '09:45');
      expect(times['Mia Chen'], 'Yesterday');

      await tester.tap(find.text('Sam Rivera'));
      await pumpFrames(tester);
      final latest = find.ancestor(of: find.text(latestChatLine), matching: find.byType(MessageBubble));
      expect(find.descendant(of: latest, matching: find.text('09:45')), findsOneWidget);
    });
  });

  testWidgets('a bubble shows the time in the phone\'s 12-hour form, under its day', (tester) async {
    await withPhoneApp(tester, identities, size: _tall, location: '/chat/$chatConversationId', body: (world) async {
      final latest = find.ancestor(of: find.text(latestChatLine), matching: find.byType(MessageBubble));
      expect(find.descendant(of: latest, matching: find.text('9:45 AM')), findsOneWidget);
      expect(find.text('09:45'), findsNothing);
      // The morning is today by the phone's clock.
      expect(find.text('Today'), findsOneWidget);
    });
  });

  testWidgets('a message the search found is dated by the same rule', (tester) async {
    MessageSearchResult hit(String id, DateTime sentAt, String body) => MessageSearchResult(
          conversationId: chatConversationId,
          messageId: id,
          peerHandle: peerHandle,
          peerDisplayName: 'Sam Rivera',
          sentAt: sentAt,
          messageKind: MessageKind.text,
          isMine: false,
          bodySnippet: body,
        );
    await withPhoneApp(
      tester,
      identities,
      size: _tall,
      location: '/conversations',
      prepare: (world) async {
        world.cache.archiveHits = [
          hit('today', DateTime.utc(2026, 4, 7, 9, 10), 'they moved move-in to the 14th'),
          hit('yesterday', DateTime.utc(2026, 4, 6, 21, 6), 'this is the place btw'),
          hit('thursday', DateTime.utc(2026, 4, 2, 18), 'the place on the 14th is free'),
          hit('march', DateTime.utc(2026, 3, 12, 18), 'the 14th or the 16th?'),
        ];
        return null;
      },
      body: (world) async {
        await tester.enterText(find.byType(TextField), '14th');
        await tester.pump(const Duration(milliseconds: 250));
        await pumpFrames(tester, frames: 2);
        final shown = {
          for (final tile in tester.widgetList<MessageSearchResultTile>(find.byType(MessageSearchResultTile)))
            tile.result.messageId: tile,
        };
        expect(shown.keys, containsAll(['today', 'yesterday', 'thursday', 'march']));
        String dateOn(String id) {
          final tile = find.byWidget(shown[id]!);
          for (final label in ['10:10 AM', '9:10 AM', 'Yesterday', 'Thu', 'Mar 12']) {
            if (find.descendant(of: tile, matching: find.text(label)).evaluate().isNotEmpty) return label;
          }
          return '(none)';
        }

        expect(dateOn('today'), '9:10 AM');
        expect(dateOn('yesterday'), 'Yesterday');
        expect(dateOn('thursday'), 'Thu');
        expect(dateOn('march'), 'Mar 12');
      },
    );
  });
}
