import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/text_normalizer.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_text.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// A message's links are found only in the part the scam checker reads, and
// finding them stays fast on a text built to be slow.

Widget _app(String text) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: MessageText(text: text, style: const TextStyle(), linkColor: Colors.blue, onLinkTap: (_) {}),
        ),
      ),
    );

List<TextSpan> _linkSpans(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.byType(RichText).first);
  final spans = <TextSpan>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.recognizer != null) spans.add(span);
    return true;
  });
  return spans;
}

void main() {
  testWidgets('a link after the part the checker reads is plain text', (tester) async {
    final filler = 'a ' * (maxCheckedLength ~/ 2);
    await tester.pumpWidget(_app('https://naver.com/a $filler https://evil.xyz/pay'));
    final spans = _linkSpans(tester);
    expect(spans.map((s) => s.text), ['https://naver.com/a']);

    // A link the cut runs through is not tappable either.
    final cutText = '${'a' * (maxCheckedLength - 12)} https://evil.xyz/pay';
    await tester.pumpWidget(_app(cutText));
    expect(_linkSpans(tester), isEmpty);
  });

  testWidgets('a long text of addresses that name no host builds quickly', (tester) async {
    final watch = Stopwatch()..start();
    await tester.pumpWidget(_app('https:///' * 11000));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)), reason: '${watch.elapsedMilliseconds} ms');
    expect(_linkSpans(tester), isEmpty);
  });
}
