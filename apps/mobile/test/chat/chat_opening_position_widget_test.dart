import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_unread_divider.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/read_state_service.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// Where a chat opens (spec D48) when its unread rows grow after the first
// frames, as a photo or a file row does once its content is in: the run
// that no longer fits opens at its divider, a third down, unless the user
// has scrolled meanwhile or the rows came in late.

const _read = 20;
const _unread = 4;
const _divider = UnreadDivider(count: _unread, firstMessageId: 'u0', olderThanLoaded: false);

void main() {
  late ScrollController controller;
  late ValueNotifier<double> unreadHeight;
  late Map<String, GlobalKey> keys;

  setUp(() {
    controller = ScrollController();
    // A placeholder's height, as a photo row has before its photo is in.
    unreadHeight = ValueNotifier<double>(57);
    keys = {};
  });

  tearDown(() {
    controller.dispose();
    unreadHeight.dispose();
  });

  GlobalKey keyOf(String id) => keys.putIfAbsent(id, GlobalKey.new);

  // A chat as ChatMessageList builds it: newest at the bottom, the divider
  // above the first unread row.
  Future<void> pumpChat(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ids = [for (var i = 0; i < _read; i++) 'r$i', for (var i = 0; i < _unread; i++) 'u$i'];
    await tester.pumpWidget(MaterialApp(
      theme: VeilTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChatOpeningPosition(
          divider: _divider,
          scrollController: controller,
          rowContextOf: (id) => keys[id]?.currentContext,
          child: ListView.builder(
            controller: controller,
            reverse: true,
            itemCount: ids.length,
            itemBuilder: (context, index) {
              final id = ids[ids.length - 1 - index];
              final row = id.startsWith('u')
                  ? ValueListenableBuilder<double>(
                      valueListenable: unreadHeight,
                      builder: (context, height, _) => SizedBox(key: keyOf(id), height: height),
                    )
                  : SizedBox(key: keyOf(id), height: 60);
              if (id != _divider.firstMessageId) return row;
              return Column(mainAxisSize: MainAxisSize.min, children: [
                ChatUnreadDivider(key: keyOf(ChatUnreadDivider.rowId), divider: _divider),
                row,
              ]);
            },
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // How far down the screen the divider's top is, as a share of it.
  double dividerShare(WidgetTester tester) =>
      tester.getRect(find.byType(ChatUnreadDivider)).top / tester.getSize(find.byType(ListView)).height;

  testWidgets('a run that fits opens at the bottom', (tester) async {
    await pumpChat(tester);
    expect(controller.offset, 0);
    expect(find.byType(ChatUnreadDivider), findsOneWidget);
  });

  testWidgets('rows that grow past the screen once their content is in open the run at its divider, a third down',
      (tester) async {
    await pumpChat(tester);
    expect(controller.offset, 0, reason: 'four placeholders fit on the screen');

    unreadHeight.value = 300;
    await settle(tester);
    expect(dividerShare(tester), closeTo(1 / 3, 0.05), reason: 'the divider went off the top as the rows grew');
  });

  testWidgets('once the user scrolls, rows that grow leave the list where they took it', (tester) async {
    await pumpChat(tester);
    await tester.drag(find.byType(ListView), const Offset(0, 80));
    await settle(tester);
    final taken = controller.offset;
    expect(taken, greaterThan(0));

    unreadHeight.value = 300;
    await settle(tester);
    expect(controller.offset, taken, reason: 'the list jumped away from where the user took it');
  });

  testWidgets('rows that come in after ${ChatOpeningPosition.followFor.inSeconds} s move nothing', (tester) async {
    await pumpChat(tester);
    await tester.pump(ChatOpeningPosition.followFor + const Duration(milliseconds: 100));

    unreadHeight.value = 300;
    await settle(tester);
    expect(controller.offset, 0, reason: 'a late row moved a list the user may be reading');
  });
}
