import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import 'layout/support/phone_layout_probe.dart';

// What the shared components owe every screen on both themes: nothing
// decorated (no gradient, glow, blur, pill fill or oversized corner), and
// words that read on the fill they sit on.

Widget _app(Widget child, {Brightness brightness = Brightness.dark, double width = 360}) => MaterialApp(
      theme: brightness == Brightness.dark
          ? VeilTheme.dark(fontFamily: layoutFontFamily)
          : VeilTheme.light(fontFamily: layoutFontFamily),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );

// WCAG contrast of [foreground] on [background], both opaque.
double _contrast(Color foreground, Color background) {
  double luminance(Color color) {
    double channel(double value) => value <= 0.03928 ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
  }

  final a = luminance(foreground), b = luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

// Nothing under [of] carries a gradient, a shadow, a blur or a corner
// rounder than the bubble's.
void _expectUndecorated(WidgetTester tester, Finder of) {
  expect(find.descendant(of: of, matching: find.byType(BackdropFilter)), findsNothing);
  expect(find.descendant(of: of, matching: find.byType(AnimatedContainer)), findsNothing);
  for (final box in tester.widgetList<DecoratedBox>(find.descendant(of: of, matching: find.byType(DecoratedBox)))) {
    final decoration = box.decoration;
    if (decoration is! BoxDecoration) continue;
    expect(decoration.gradient, isNull);
    expect(decoration.boxShadow, anyOf(isNull, isEmpty));
    if (decoration.borderRadius case final BorderRadius radius) {
      expect(radius.topLeft.x, lessThanOrEqualTo(VeilRadius.xl));
    }
  }
  for (final material in tester.widgetList<Material>(find.descendant(of: of, matching: find.byType(Material)))) {
    expect(material.elevation, 0);
    if (material.shape case final RoundedRectangleBorder shape) {
      expect((shape.borderRadius as BorderRadius).topLeft.x, lessThanOrEqualTo(VeilRadius.xl));
    }
  }
}

void main() {
  setUpAll(loadTestFonts);

  group('nothing is decorated', () {
    final components = <String, Widget>{
      'notice': const VeilNotice(title: 'Safety number changed', message: 'Nothing is sent until you review it.', tone: VeilTone.warn, actionLabel: 'Review', onAction: _noop),
      'dense notice': const VeilNotice(message: '2 messages not sent', tone: VeilTone.danger, dense: true, actionLabel: 'Retry', onAction: _noop),
      'group': const VeilGroup(header: 'Privacy', footer: 'Only you see this.', children: [
        VeilRow(title: 'TLS pinning', subtitle: 'Every request.', status: ('Pinned', VeilTone.good)),
        VeilRow(title: 'App lock', value: 'Off', onTap: _noop),
        VeilRow(title: 'Send read receipts', switchValue: true, onSwitch: null),
      ]),
      'avatar': const VeilAvatar(name: 'Alex Kim', seed: 'alex', size: 72),
      'own bubble': const VeilBubble(isMine: true, child: Text('hello')),
      'their bubble': const VeilBubble(isMine: false, position: VeilBubblePosition.first, child: Text('hi')),
      'failed bubble': const VeilBubble(isMine: true, failed: true, failedText: 'Not sent. Tap to retry.', child: Text('hey')),
      'empty state': const VeilEmptyState(title: 'No chats yet', body: 'Start a chat with a handle.', icon: Icons.chat_bubble_outline),
      'error state': const VeilEmptyState.error(title: 'Could not load', body: 'Try again.'),
      'buttons': const Column(children: [
        VeilButton(label: 'Continue', onPressed: _noop),
        VeilButton(label: 'Scan their code', onPressed: _noop, tone: VeilButtonTone.secondary),
        VeilButton(label: 'Wipe this device', onPressed: _noop, tone: VeilButtonTone.destructive),
      ]),
    };
    for (final brightness in Brightness.values) {
      for (final MapEntry(key: name, value: component) in components.entries) {
        testWidgets('$name (${brightness.name})', (tester) async {
          await tester.pumpWidget(_app(component, brightness: brightness));
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          _expectUndecorated(tester, find.byWidget(component));
        });
      }
    }
  });

  group('on both themes', () {
    for (final brightness in Brightness.values) {
      final palette = VeilPalette.forBrightness(brightness);

      // A selected ChoiceChip sits on primarySoft, a tint of the page or the
      // group behind it; its label has to read on that tint.
      testWidgets('a selected choice chip\'s label reads on its tint (${brightness.name})', (tester) async {
        await tester.pumpWidget(_app(
          Wrap(children: [
            ChoiceChip(label: const Text('New phone'), selected: true, onSelected: (_) {}),
            ChoiceChip(label: const Text('Old phone'), selected: false, onSelected: (_) {}),
          ]),
          brightness: brightness,
        ));
        await tester.pumpAndSettle();

        Color labelOf(String label) => tester.renderObject<RenderParagraph>(find.text(label)).text.style!.color!;
        Color groundOf(String label) {
          final ink = tester.widget<Ink>(
            find.descendant(of: find.widgetWithText(ChoiceChip, label), matching: find.byType(Ink)),
          );
          // The chip's colour over the surface a chip sits on (a page or a
          // group), never over surfaceAlt.
          return Color.alphaBlend((ink.decoration! as ShapeDecoration).color!, palette.surface);
        }

        expect(_contrast(labelOf('New phone'), groundOf('New phone')), greaterThanOrEqualTo(4.5), reason: 'selected');
        expect(_contrast(labelOf('Old phone'), groundOf('Old phone')), greaterThanOrEqualTo(4.5), reason: 'unselected');
        expect(labelOf('New phone'), isNot(labelOf('Old phone')), reason: 'the selected chip is told apart');
        final shape = tester.widget<Ink>(find.descendant(of: find.byType(ChoiceChip).first, matching: find.byType(Ink)));
        expect(((shape.decoration! as ShapeDecoration).shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(6));
      });

      // A notice's fill is surfaceAlt: its title, body and button have to
      // read on it in each tone.
      for (final tone in VeilTone.values) {
        testWidgets('a ${tone.name} notice reads on its fill, and its status word on a row (${brightness.name})', (tester) async {
          await tester.pumpWidget(_app(
            Column(children: [
              VeilNotice(title: 'Delivery stopped', message: '2 messages were not sent.', tone: tone, actionLabel: 'Retry', onAction: _noop),
              VeilRow(title: 'TLS pinning', status: ('Pinned', tone)),
            ]),
            brightness: brightness,
          ));
          await tester.pumpAndSettle();

          Color colorOf(String text) => tester.renderObject<RenderParagraph>(find.text(text)).text.style!.color!;
          final fill = palette.surfaceAlt;
          expect(_contrast(colorOf('Delivery stopped'), fill), greaterThanOrEqualTo(4.5), reason: 'the title');
          expect(_contrast(colorOf('2 messages were not sent.'), fill), greaterThanOrEqualTo(4.5), reason: 'the body');
          expect(_contrast(colorOf('Retry'), fill), greaterThanOrEqualTo(4.5), reason: 'the button');
          final icon = tester.widget<Icon>(find.descendant(of: find.byType(VeilNotice), matching: find.byType(Icon)));
          expect(_contrast(icon.color!, fill), greaterThanOrEqualTo(3), reason: 'the icon');
          expect(_contrast(colorOf('Pinned'), palette.surface), greaterThanOrEqualTo(4.5), reason: 'the status word');
        });
      }
    }
  });
}

void _noop() {}
