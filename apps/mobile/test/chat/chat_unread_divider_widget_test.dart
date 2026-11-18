import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_unread_divider.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/read_state_service.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// The unread divider on its own (spec D48): its words, a band that runs
// past the list's padding and grows with larger text instead of cutting
// its words off.

void main() {
  const counted = UnreadDivider(count: 4, firstMessageId: 'm1', olderThanLoaded: false);
  const older = UnreadDivider(count: 50, firstMessageId: 'm51', olderThanLoaded: true);

  // [divider] in a list, as a chat holds it, at [textScale].
  Future<void> pump(WidgetTester tester, UnreadDivider divider, {double textScale = 1, double bleed = 12}) async {
    await tester.pumpWidget(MaterialApp(
      theme: VeilTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: ListView(
            padding: EdgeInsets.symmetric(horizontal: bleed),
            children: [ChatUnreadDivider(divider: divider, bleed: bleed), const SizedBox(height: 40)],
          ),
        ),
      ),
    ));
  }

  Finder band() => find.descendant(of: find.byType(ChatUnreadDivider), matching: find.byType(ColoredBox));

  testWidgets('says how many were unread, or "Unread messages" when the first is older than what is loaded',
      (tester) async {
    await pump(tester, counted);
    expect(find.text('4 unread messages'), findsOneWidget);
    await pump(tester, older);
    expect(find.text('Unread messages'), findsOneWidget);
    expect(find.textContaining('50'), findsNothing);
  });

  testWidgets('the band runs across the list\'s padding, 28 high with 16 above and below', (tester) async {
    await pump(tester, counted, bleed: 12);
    final rect = tester.getRect(band());
    expect((rect.left, rect.width), (0, tester.getSize(find.byType(ListView)).width), reason: 'edge to edge');
    expect(rect.height, ChatUnreadDivider.bandHeight);
    expect(tester.getSize(find.byType(ChatUnreadDivider)).height, ChatUnreadDivider.extent);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('at text scale $scale the band grows around its words instead of cutting them off', (tester) async {
      await pump(tester, counted, textScale: scale);
      final words = tester.renderObject<RenderParagraph>(find.text('4 unread messages'));
      final rect = tester.getRect(band());
      final text = tester.getRect(find.text('4 unread messages'));
      expect(words.didExceedMaxLines, isFalse);
      expect(rect.height, greaterThan(ChatUnreadDivider.bandHeight));
      expect(text.top, greaterThanOrEqualTo(rect.top + VeilSpace.xxs));
      expect(text.bottom, lessThanOrEqualTo(rect.bottom - VeilSpace.xxs));
      expect(tester.getSize(find.byType(ChatUnreadDivider)).height, rect.height + 2 * VeilSpace.md);
    });
  }
}
