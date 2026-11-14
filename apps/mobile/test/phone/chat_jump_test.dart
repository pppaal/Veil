import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_pane.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_parts.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';

import '../layout/support/layout_seed.dart';
import 'phone_app.dart';

// Opening a message a search found shows that message. The chat builds only
// the rows around what is on screen and opens at its newest message, so a
// hit further back has no row to scroll to when the chat opens: the jump
// has to bring the list there first, on a phone and in the wide layout's
// chat pane alike.

const _peer = emptyChatPeerHandle;
const _conversation = emptyChatConversationId;
const _lineCount = 60;
const _oldLine = 3;
const _middleLine = 31;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // The chat's history arrives in pages, so the old hit is two pages back
  // from the one the chat opens with.
  Future<List<String>> seedLongChat(LayoutWorld world) async {
    world.relay.messagePageSize = 25;
    return seedHistory(world.relay, peer: _peer, count: _lineCount);
  }

  MessageSearchResult hit(List<String> ids, int line) => MessageSearchResult(
        conversationId: _conversation,
        messageId: ids[line - 1],
        peerHandle: _peer,
        peerDisplayName: 'Mira',
        sentAt: DateTime.utc(2026, 4, 1, 9, line),
        messageKind: MessageKind.text,
        isMine: false,
        bodySnippet: historyLine(line),
      );

  // A jump loads history, moves the list a screenful per frame and then
  // animates to the row.
  Future<void> settleJump(WidgetTester tester) => pumpFrames(tester, frames: 40, step: const Duration(milliseconds: 50));

  // The whole row of [line] is inside the message area.
  void expectLineInView(WidgetTester tester, int line) {
    final row = find.text(historyLine(line));
    expect(row, findsOneWidget, reason: '${historyLine(line)} has no row');
    final box = tester.renderObject<RenderBox>(row);
    final shown = visibleRect(tester, box);
    final area = onScreen(tester, find.byType(ChatMessageList));
    expect(shown.height, box.size.height, reason: '${historyLine(line)} is cut off');
    expect(shown.top, greaterThanOrEqualTo(area.top));
    expect(shown.bottom, lessThanOrEqualTo(area.bottom));
  }

  testWidgets('a chat this long opens with its old messages unbuilt', (tester) async {
    await withPhoneApp(tester, identities, location: '/chat/$_conversation', prepare: seedLongChat,
        body: (world) async {
      expectLineInView(tester, _lineCount);
      expect(find.text(historyLine(_lineCount - 24)), findsNothing, reason: 'the oldest loaded message has no row');
      expect(find.text(historyLine(_oldLine)), findsNothing);
    });
  });

  testWidgets('tapping a found message in the list opens the chat at that message', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      prepare: (world) async {
        final ids = await seedLongChat(world);
        world.cache.archiveHits = [hit(ids, _oldLine)];
        return null;
      },
      body: (world) async {
        await tester.enterText(find.byType(TextField), 'history');
        // The archive search waits 180 ms for the typing to stop.
        await pumpFrames(tester, frames: 4);
        final result = find.byType(MessageSearchResultTile);
        await tester.dragUntilVisible(result, find.byType(ListView), const Offset(0, -200));
        await pumpFrames(tester, frames: 2);
        await tester.tap(result);
        await settleJump(tester);

        expect(find.byType(ChatRoomScreen), findsOneWidget);
        expectLineInView(tester, _oldLine);
        expect(find.text(historyLine(_lineCount)), findsNothing, reason: 'the chat left its newest message');
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Back'));
        await pumpFrames(tester);
        expect(find.byType(ConversationListScreen), findsOneWidget);
      },
    );
  });

  testWidgets('opens at a hit in the middle of the history, and at the newest message', (tester) async {
    late List<String> ids;
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/$_conversation',
      prepare: (world) async {
        ids = await seedLongChat(world);
        return MessageNavigationTarget(messageId: ids[_middleLine - 1], requestId: 1);
      },
      body: (world) async {
        await settleJump(tester);
        expectLineInView(tester, _middleLine);
      },
    );
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/$_conversation',
      prepare: (world) async {
        ids = await seedLongChat(world);
        return MessageNavigationTarget(messageId: ids.last, requestId: 1);
      },
      body: (world) async {
        await settleJump(tester);
        expectLineInView(tester, _lineCount);
      },
    );
  });

  testWidgets('a second target moves the chat back from an old message to the newest', (tester) async {
    late List<String> ids;
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/$_conversation',
      prepare: (world) async {
        ids = await seedLongChat(world);
        return MessageNavigationTarget(messageId: ids[_oldLine - 1], requestId: 1);
      },
      body: (world) async {
        await settleJump(tester);
        expectLineInView(tester, _oldLine);
        expect(find.text(historyLine(_lineCount)), findsNothing);

        GoRouter.of(tester.element(find.byType(ChatRoomScreen))).go(
              '/chat/$_conversation',
              extra: MessageNavigationTarget(messageId: ids.last, requestId: 2),
            );
        await settleJump(tester);
        expectLineInView(tester, _lineCount);
        expect(find.text(historyLine(_oldLine)), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // The wide layout keeps the list beside the chat: every tapped result
  // re-targets the same chat pane.
  testWidgets('the wide layout\'s chat pane follows each tapped result, old and new', (tester) async {
    const wide = PhoneSize(1440, 1400, topInset: 0, bottomInset: 0);
    await withPhoneApp(
      tester,
      identities,
      size: wide,
      location: '/conversations',
      prepare: (world) async {
        final ids = await seedLongChat(world);
        world.cache.archiveHits = [hit(ids, _lineCount), hit(ids, _oldLine)];
        return null;
      },
      body: (world) async {
        await tester.enterText(find.byType(TextField).first, 'history');
        await pumpFrames(tester, frames: 4);

        // The results follow the conversations in a list that builds only
        // what is near the screen.
        Future<void> tapResult(int line) async {
          final tile = find.byWidgetPredicate(
            (widget) => widget is MessageSearchResultTile && widget.result.bodySnippet == historyLine(line),
          );
          await tester.dragUntilVisible(tile, find.byType(ConversationListPane), const Offset(0, -200));
          await pumpFrames(tester, frames: 2);
          await tester.tap(tile);
          await settleJump(tester);
        }

        await tapResult(_oldLine);
        expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).embedded, isTrue);
        expectLineInView(tester, _oldLine);
        expect(find.text(historyLine(_lineCount)), findsNothing);

        await tapResult(_lineCount);
        expectLineInView(tester, _lineCount);
        expect(find.text(historyLine(_oldLine)), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
