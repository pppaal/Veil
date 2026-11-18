import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';

// How a Chats row draws what is unread (spec D46, D53): the bold name, the
// message and the time in the text colour, the count or the marked-unread
// disc, grey for a quiet chat, the glyph of a photo or a file, and the row's
// long press and screen reader actions.

void main() {
  final palette = VeilPalette.light;

  Widget row({
    int unreadCount = 0,
    bool markedUnread = false,
    bool muted = false,
    bool greyBadge = false,
    String snippet = 'Section 7 is fine.',
    IconData? snippetIcon,
    int snippetIconAt = 0,
    VoidCallback? onLongPress,
    Map<CustomSemanticsAction, VoidCallback>? semanticActions,
  }) =>
      MaterialApp(
        theme: VeilTheme.light(),
        home: Scaffold(
          body: ConversationRow(
            title: 'Sam Rivera',
            seed: 'sam',
            snippet: snippet,
            snippetIcon: snippetIcon,
            snippetIconAt: snippetIconAt,
            timestamp: '9:45 AM',
            semanticLabel: 'Chat with Sam Rivera',
            unreadCount: unreadCount,
            unreadLabel: unreadCount == 0 ? null : '$unreadCount unread messages',
            markedUnread: markedUnread,
            markedUnreadLabel: 'Marked unread',
            muted: muted,
            mutedLabel: 'Muted',
            greyBadge: greyBadge,
            onTap: () {},
            onLongPress: onLongPress,
            semanticActions: semanticActions,
          ),
        ),
      );

  Finder labelled(String label) =>
      find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

  testWidgets('a chat marked unread with nothing counted shows an empty 20x20 disc and reads as unread',
      (tester) async {
    await tester.pumpWidget(row(markedUnread: true));
    final badge = tester.widget<UnreadBadge>(find.byType(UnreadBadge));
    expect(badge.count, isNull);
    expect(badge.muted, isFalse);
    expect(tester.getSize(find.byType(UnreadBadge)), const Size(20, 20));
    final disc = tester.widget<Container>(find.descendant(of: find.byType(UnreadBadge), matching: find.byType(Container)));
    expect((disc.decoration! as BoxDecoration).color, palette.primary);
    expect(find.descendant(of: find.byType(UnreadBadge), matching: find.byType(Text)), findsNothing);

    expect(tester.widget<Text>(find.text('Sam Rivera')).style?.fontWeight, FontWeight.w700);
    expect(tester.widget<Text>(find.text('Section 7 is fine.')).style?.color, palette.text);
    expect(labelled('Chat with Sam Rivera, Marked unread'), findsOneWidget);
  });

  testWidgets('an unread chat\'s time is in the text colour at 600; a read one\'s is muted', (tester) async {
    await tester.pumpWidget(row(unreadCount: 2));
    final unreadTime = tester.widget<Text>(find.text('9:45 AM')).style!;
    expect(unreadTime.color, palette.text);
    expect(unreadTime.fontWeight, FontWeight.w600);
    expect(labelled('Chat with Sam Rivera, 2 unread messages'), findsOneWidget, reason: 'the count wins over the flag');

    await tester.pumpWidget(row());
    final readTime = tester.widget<Text>(find.text('9:45 AM')).style!;
    expect(readTime.color, palette.textMuted);
    expect(readTime.fontWeight, isNot(FontWeight.w600));
    expect(find.byType(UnreadBadge), findsNothing);
  });

  testWidgets('a count past 999 reads 999+', (tester) async {
    await tester.pumpWidget(row(unreadCount: 1200));
    expect(find.text('999+'), findsOneWidget);
  });

  testWidgets('a long press opens the menu, and a screen reader has its two actions', (tester) async {
    var pressed = 0;
    final done = <String>[];
    await tester.pumpWidget(row(
      unreadCount: 1,
      onLongPress: () => pressed += 1,
      semanticActions: {
        const CustomSemanticsAction(label: 'Mark as read'): () => done.add('read'),
        const CustomSemanticsAction(label: 'Mute notifications'): () => done.add('mute'),
      },
    ));
    await tester.longPress(find.byType(ConversationRow));
    expect(pressed, 1);

    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.byType(ConversationRow));
    final actions = node.getSemanticsData().customSemanticsActionIds!.map(CustomSemanticsAction.getAction).toList();
    expect(actions.map((action) => action!.label), ['Mark as read', 'Mute notifications']);
    for (final action in actions) {
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(action!),
      );
    }
    expect(done, ['read', 'mute']);
    handle.dispose();
  });

  testWidgets('a muted chat\'s count is grey with the bell glyph; a blocked peer\'s is grey without it', (tester) async {
    await tester.pumpWidget(row(unreadCount: 3, muted: true));
    expect(tester.widget<UnreadBadge>(find.byType(UnreadBadge)).muted, isTrue);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

    await tester.pumpWidget(row(unreadCount: 3, greyBadge: true));
    final badge = tester.widget<UnreadBadge>(find.byType(UnreadBadge));
    expect(badge.muted, isTrue);
    final pill = tester.widget<Container>(find.descendant(of: find.byType(UnreadBadge), matching: find.byType(Container)));
    expect((pill.decoration! as BoxDecoration).color, palette.textMuted);
    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);

    // Marked unread and blocked: the disc is grey too.
    await tester.pumpWidget(row(markedUnread: true, greyBadge: true));
    expect(tester.widget<UnreadBadge>(find.byType(UnreadBadge)).muted, isTrue);
  });

  testWidgets('a photo shows its glyph before the word, after a group\'s sender', (tester) async {
    await tester.pumpWidget(row(snippet: 'Photo', snippetIcon: Icons.photo_outlined));
    expect(find.text('Photo'), findsOneWidget);
    final glyph = tester.widget<Icon>(find.byIcon(Icons.photo_outlined));
    expect((glyph.size, glyph.color), (16.0, palette.textMuted));
    expect(tester.getTopLeft(find.byIcon(Icons.photo_outlined)).dx, lessThan(tester.getTopLeft(find.text('Photo')).dx));

    await tester.pumpWidget(row(snippet: 'Omar: lease.pdf', snippetIcon: Icons.insert_drive_file_outlined, snippetIconAt: 6));
    final text = tester.widget<RichText>(find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText(includePlaceholders: false) == 'Omar: lease.pdf',
    ));
    final spans = (text.text as TextSpan).children!.single as TextSpan;
    expect((spans.children![0] as TextSpan).text, 'Omar: ');
    expect(spans.children![1], isA<WidgetSpan>());
    expect((spans.children![2] as TextSpan).text, 'lease.pdf');
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });
}
