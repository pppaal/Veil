import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import 'layout/support/phone_layout_probe.dart';

// What the shared components owe every screen that uses them: Korean copy
// that wraps between words, status tiles that never leave one alone on a
// row, and tones and chips that read on the light theme as on the dark one.

const _koreanBody = '이전은 핸들을 새 기기로 옮깁니다. 기존 기기가 세션을 발급하고 새 기기가 보낸 바로 그 등록 요청을 '
    '승인하며, 이전이 완료되면 기존 기기는 로그아웃됩니다. 대화 기록은 옮겨지지 않습니다.';

Widget _app(Widget child, {Brightness brightness = Brightness.dark, double width = 360}) => MaterialApp(
      theme: brightness == Brightness.dark ? VeilTheme.dark() : VeilTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );

// Every word of every paragraph under [of] sits on one line.
void _expectWordsWhole(WidgetTester tester, Finder of) {
  final paragraphs = find.descendant(of: of, matching: find.byType(RichText)).evaluate();
  expect(paragraphs, isNotEmpty);
  var wrapped = 0;
  for (final element in paragraphs) {
    final paragraph = element.renderObject! as RenderParagraph;
    final shown = paragraph.text.toPlainText();
    if (paragraph.size.height > 30) wrapped += 1;
    for (final word in RegExp(r'\S+').allMatches(shown)) {
      final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: word.start, extentOffset: word.end));
      expect({for (final box in boxes) box.top}, hasLength(1), reason: '"${word[0]}" is split over lines in "$shown"');
    }
  }
  expect(wrapped, greaterThan(0), reason: 'no paragraph wrapped, so nothing was tested');
}

// WCAG contrast of [foreground] on [background], both opaque.
double _contrast(Color foreground, Color background) {
  double luminance(Color color) {
    double channel(double value) =>
        value <= 0.03928 ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
  }

  final a = luminance(foreground), b = luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  setUpAll(loadBundledFonts);

  group('VeilCopy', () {
    testWidgets('draws Korean copy with its words whole and reads it out plain', (tester) async {
      await tester.pumpWidget(_app(const VeilCopy(_koreanBody)));
      _expectWordsWhole(tester, find.byType(VeilCopy));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.semanticsLabel, _koreanBody);
      expect(text.data!.replaceAll('⁠', ''), _koreanBody);
      expect(text.data, isNot(_koreanBody), reason: 'the joiners are what keeps a word on one line');
    });

    testWidgets('leaves text without Hangul as it is', (tester) async {
      await tester.pumpWidget(_app(const VeilCopy('No backup. No recovery.')));
      expect(find.text('No backup. No recovery.'), findsOneWidget);
    });

    // Without the joiners the same paragraph breaks inside words at one
    // width or another: this is what the shared components showed before
    // they drew their bodies with VeilCopy. With them it never does.
    testWidgets('keeps words whole at every width, where a plain Text does not', (tester) async {
      var plainSplits = 0;
      for (var width = 200.0; width <= 372; width += 4) {
        await tester.pumpWidget(_app(const Text(_koreanBody), width: width));
        final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
        plainSplits += RegExp(r'\S+').allMatches(_koreanBody).where((word) {
          final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: word.start, extentOffset: word.end));
          return {for (final box in boxes) box.top}.length > 1;
        }).length;

        await tester.pumpWidget(_app(const VeilCopy(_koreanBody), width: width));
        _expectWordsWhole(tester, find.byType(VeilCopy));
      }
      expect(plainSplits, greaterThan(0), reason: 'a plain Text never split a word, so the comparison says nothing');
    });
  });

  group('the shared components keep Korean words whole in their body text', () {
    final components = <String, Widget>{
      'hero panel': const VeilHeroPanel(eyebrow: '이전', title: '기존 기기가 필요합니다.', body: _koreanBody),
      'inline banner': const VeilInlineBanner(title: '대체 경로 없음', message: _koreanBody),
      'dense inline banner': const VeilInlineBanner(title: '대체 경로 없음', message: _koreanBody, dense: true),
      'empty state': const VeilEmptyState(title: '일치하는 메시지가 없습니다', body: _koreanBody),
      'error state': const VeilErrorState(title: '불러오지 못했습니다', body: _koreanBody),
      'loading block': const VeilLoadingBlock(title: '불러오는 중', body: _koreanBody),
      'destructive notice': const VeilDestructiveNotice(title: '대체 경로 없음', body: _koreanBody),
      'field block': const VeilFieldBlock(label: '핸들', caption: _koreanBody, child: SizedBox(height: 10)),
      'step row': const VeilStepRow(step: 1, title: '로컬 신원 생성', body: _koreanBody, active: true),
      'value row': const VeilValueRow(label: '기기 이전', value: '필요', detail: _koreanBody),
      'list tile card': const VeilListTileCard(title: '기기 이전', subtitle: _koreanBody),
    };
    for (final MapEntry(key: name, value: component) in components.entries) {
      testWidgets(name, (tester) async {
        await tester.pumpWidget(_app(component));
        // Entry animations of the hero.
        await tester.pump(const Duration(seconds: 1));
        _expectWordsWhole(tester, find.byWidget(component));
        expect(tester.takeException(), isNull);
      });
    }

    // A person's own words are never rewritten: a bubble's text goes into a
    // plain Text, and the conversation card shows a preview as it is.
    testWidgets('a conversation card leaves a name and a preview as they were written', (tester) async {
      const name = '김서연 (디자인팀)';
      const preview = '두 번째 시안이 더 낫긴 한데 헤더가 아직 무거워 보여요.';
      await tester.pumpWidget(_app(
        const VeilConversationCard(title: name, handle: 'seoyeon', subtitle: preview, timestamp: '08:21'),
      ));
      expect(find.text(name), findsOneWidget);
      expect(find.text(preview), findsOneWidget);
    });
  });

  group('VeilMetricStrip', () {
    test('never leaves one tile alone on a row of a phone', () {
      expect(VeilMetricStrip.phoneRows(0), isEmpty);
      expect(VeilMetricStrip.phoneRows(1), [1]);
      expect(VeilMetricStrip.phoneRows(2), [2]);
      expect(VeilMetricStrip.phoneRows(3), [3]);
      expect(VeilMetricStrip.phoneRows(4), [2, 2]);
      expect(VeilMetricStrip.phoneRows(5), [3, 2]);
      expect(VeilMetricStrip.phoneRows(6), [3, 3]);
      expect(VeilMetricStrip.phoneRows(7), [3, 2, 2]);
      for (var count = 2; count <= 12; count++) {
        final rows = VeilMetricStrip.phoneRows(count);
        expect(rows.reduce((a, b) => a + b), count);
        expect(rows.every((row) => row >= 2 && row <= 3), isTrue, reason: '$count tiles: $rows');
      }
    });

    for (final (width, count) in [(360.0, 3), (390.0, 3), (412.0, 3), (360.0, 4), (360.0, 5)]) {
      testWidgets('$count tiles share the rows of a ${width.toInt()} px phone', (tester) async {
        usePhoneView(tester, PhoneSize(width, 800, topInset: 0, bottomInset: 0));
        await tester.pumpWidget(MaterialApp(
          theme: VeilTheme.dark(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(VeilSpace.lg),
              child: VeilMetricStrip(items: [
                for (final (label, value) in [
                  ('모드', '새 기기'),
                  ('세션', '대기'),
                  ('등록 요청', '없음'),
                  ('Recovery', 'Old device'),
                  ('Relay', 'Linked'),
                ].take(count))
                  VeilMetricItem(label: label, value: value),
              ]),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);

        // Tiles by the row they sit on.
        final rows = <double, List<Rect>>{};
        for (final card in find.byType(VeilSurfaceCard).evaluate()) {
          final box = card.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          rows.putIfAbsent(rect.top, () => []).add(rect);
        }
        expect([for (final row in rows.values) row.length], VeilMetricStrip.phoneRows(count));
        for (final row in rows.values) {
          expect(row.length, greaterThan(1), reason: 'a tile is alone on its row');
          expect({for (final rect in row) rect.width.round()}, hasLength(1), reason: 'the tiles of a row share its width');
          expect({for (final rect in row) rect.height.round()}, hasLength(1), reason: 'and its height');
          expect(row.last.right, closeTo(width - VeilSpace.lg, 0.5), reason: 'the row fills the width');
        }
      });
    }

    testWidgets('on a wide screen the tiles keep their own width', (tester) async {
      usePhoneView(tester, wideSmall);
      await tester.pumpWidget(MaterialApp(
        theme: VeilTheme.dark(),
        home: const Scaffold(
          body: VeilMetricStrip(items: [
            VeilMetricItem(label: 'Relay', value: 'Linked'),
            VeilMetricItem(label: 'Local search', value: 'Ready'),
            VeilMetricItem(label: 'Conversations', value: '8'),
          ]),
        ),
      ));
      expect(find.byType(Wrap), findsOneWidget);
      expect(tester.getSize(find.byType(VeilSurfaceCard).first).width, lessThan(300));
    });
  });

  group('on both themes', () {
    for (final brightness in Brightness.values) {
      final palette = VeilPalette.forBrightness(brightness);

      // A selected ChoiceChip sits on primarySoft, a tint of what is behind
      // it; its label has to read on that tint.
      testWidgets('a selected choice chip\'s label reads on its tint (${brightness.name})', (tester) async {
        await tester.pumpWidget(_app(
          Wrap(children: [
            ChoiceChip(label: const Text('새 기기'), selected: true, onSelected: (_) {}),
            ChoiceChip(label: const Text('기존 기기'), selected: false, onSelected: (_) {}),
          ]),
          brightness: brightness,
        ));
        await tester.pumpAndSettle();

        Color labelOf(String label) =>
            tester.renderObject<RenderParagraph>(find.text(label)).text.style!.color!;
        Color groundOf(String label) {
          final ink = tester.widget<Ink>(
            find.descendant(of: find.widgetWithText(ChoiceChip, label), matching: find.byType(Ink)),
          );
          // The chip's colour over the surface the screen gives it.
          return Color.alphaBlend((ink.decoration! as ShapeDecoration).color!, palette.surfaceAlt);
        }

        expect(_contrast(labelOf('새 기기'), groundOf('새 기기')), greaterThanOrEqualTo(4.5), reason: 'selected');
        expect(_contrast(labelOf('기존 기기'), groundOf('기존 기기')), greaterThanOrEqualTo(4.5), reason: 'unselected');
        expect(labelOf('새 기기'), isNot(labelOf('기존 기기')), reason: 'the selected chip is told apart');
      });

      // A banner's fill is a tint of the surface: white text on it, right
      // for the dark theme, could not be read on the light one.
      for (final tone in VeilBannerTone.values) {
        testWidgets('a ${tone.name} banner and pill read on their tint (${brightness.name})', (tester) async {
          await tester.pumpWidget(_app(
            Column(children: [
              VeilInlineBanner(title: '전송 정지됨', message: '메시지 2개를 보내지 못했습니다.', tone: tone),
              VeilStatusPill(label: '확인 필요', tone: tone),
            ]),
            brightness: brightness,
          ));
          await tester.pumpAndSettle();

          final banner = tester.widget<AnimatedContainer>(
            find.descendant(of: find.byType(VeilInlineBanner), matching: find.byType(AnimatedContainer)),
          );
          final fill = Color.alphaBlend((banner.decoration! as BoxDecoration).color!, palette.surface);
          Color colorOf(Finder of) => tester
              .renderObject<RenderParagraph>(find.descendant(of: of, matching: find.byType(RichText)).first)
              .text
              .style!
              .color!;
          final texts = find.descendant(of: find.byType(VeilInlineBanner), matching: find.byType(VeilCopy));
          expect(texts, findsNWidgets(2));
          for (final text in texts.evaluate()) {
            final color = Color.alphaBlend(colorOf(find.byWidget(text.widget)), fill);
            expect(_contrast(color, fill), greaterThanOrEqualTo(4.5), reason: (text.widget as VeilCopy).text);
          }
          final pill = Color.alphaBlend(colorOf(find.byType(VeilStatusPill)), fill);
          expect(_contrast(pill, fill), greaterThanOrEqualTo(4.5), reason: 'the pill');
        });
      }
    }
  });
}
