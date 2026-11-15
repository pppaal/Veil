import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/shared/presentation/veil_grouped.dart';
import 'package:veil_mobile/src/shared/presentation/veil_initial_badge.dart';
import 'package:veil_mobile/src/shared/presentation/veil_screen_intro.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import 'layout/support/phone_layout_probe.dart';

// What the shared components owe every screen on both themes: nothing
// decorated (no gradient, glow, blur, pill fill or oversized corner), and
// words that read on the fill they sit on. The deprecated widgets of the
// previous pass are held to the same rule until wave 1 removes them.

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

  group('the deprecated widgets of the previous pass are flattened', () {
    // ignore_for_file: deprecated_member_use_from_same_package
    final components = <String, Widget>{
      'hero panel': const VeilHeroPanel(eyebrow: 'SYSTEM', title: 'Create account', body: 'A line under it.'),
      'status pill': const VeilStatusPill(label: 'Verified', tone: VeilTone.good),
      'inline banner': const VeilInlineBanner(title: 'Safety number changed', message: 'Nothing is sent until you review it.', tone: VeilTone.warn),
      'notice row': const VeilNoticeRow(title: '2 messages not sent', tone: VeilTone.warn, actionLabel: 'Retry', onAction: _noop),
      'destructive notice': const VeilDestructiveNotice(title: 'No backup', body: 'If you lose this phone, you lose this account.'),
      'surface card': const VeilSurfaceCard(toned: true, child: Text('In a card')),
      'section label': const VeilSectionLabel('PRIVACY'),
      'field block': const VeilFieldBlock(label: 'Handle', caption: 'Lowercase letters.', child: SizedBox(height: 10)),
      'list tile card': const VeilListTileCard(title: 'This phone', subtitle: 'Last seen now', eyebrow: 'DEVICE'),
      'value row': const VeilValueRow(label: 'TLS pinning', value: 'Pinned', valueTone: VeilTone.good, detail: 'Every request.'),
      'step row': const VeilStepRow(step: 1, title: 'Scan the code', body: 'On the old phone.', active: true),
      'loading block': const VeilLoadingBlock(title: 'Loading', body: 'ignored'),
      'skeleton line': const VeilSkeletonLine(width: 120),
      'metric strip': const VeilMetricStrip(items: [VeilMetricItem(label: 'Relay', value: 'Linked')]),
      'screen intro': const VeilScreenIntro(eyebrow: 'IDENTITY', title: 'Choose a handle', body: 'People find you by it.'),
      'initial badge': const VeilInitialBadge(name: 'Alex Kim', size: 72),
      'group row': const VeilGroupRow(title: 'App lock', value: 'Off', icon: Icons.lock_outline, onTap: _noop),
      'group switch row': const VeilGroupSwitchRow(title: 'Read receipts', value: true, onChanged: null),
      'message bubble card': const VeilMessageBubbleCard(isMine: true, child: Text('hello')),
      'conversation card': const VeilConversationCard(
        title: 'Alex Kim',
        handle: 'alex',
        subtitle: 'See you at 6',
        timestamp: '08:45',
        expiryLabel: '1 day',
        semanticLabel: 'Chat with Alex Kim',
        meta: VeilStatusPill(label: 'Queued', tone: VeilTone.warn),
      ),
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

    testWidgets('eyebrows, pills and metric tiles draw nothing', (tester) async {
      await tester.pumpWidget(_app(const Column(children: [
        VeilHeroPanel(eyebrow: 'SYSTEM', title: 'Title', body: 'Body'),
        VeilScreenIntro(eyebrow: 'IDENTITY', title: 'Title 2'),
        VeilListTileCard(title: 'Row', subtitle: 'Sub', eyebrow: 'DEVICE'),
        VeilMetricStrip(items: [VeilMetricItem(label: 'Relay', value: 'Linked')]),
        VeilSkeletonLine(width: 120, height: 14),
        VeilStatusPill(label: 'Verified', tone: VeilTone.good),
      ])));
      expect(find.text('SYSTEM'), findsNothing);
      expect(find.text('IDENTITY'), findsNothing);
      expect(find.text('DEVICE'), findsNothing);
      expect(find.text('Linked'), findsNothing);
      expect(tester.getSize(find.byType(VeilMetricStrip)), Size.zero);
      expect(tester.getSize(find.byType(VeilSkeletonLine)), Size.zero);
      // A status pill is now a word in the tone colour with no box.
      expect(find.ancestor(of: find.text('Verified'), matching: find.byType(DecoratedBox)), findsNothing);
      expect(tester.widget<Text>(find.text('Verified')).style?.color, VeilPalette.dark.success);
    });

    testWidgets('a conversation card is a full-bleed row with a solid avatar and a timer glyph', (tester) async {
      const name = 'Alex Kim';
      const preview = 'See you at 6';
      await tester.pumpWidget(_app(
        const VeilConversationCard(
          title: name,
          handle: 'alex',
          subtitle: preview,
          timestamp: '08:21',
          expiryLabel: '1 day',
          semanticLabel: 'Chat with $name',
        ),
      ));
      expect(find.text(name), findsOneWidget);
      expect(find.text(preview), findsOneWidget);
      expect(find.byType(VeilAvatar), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(tester.getRect(find.byType(VeilConversationCard)).width, 360);
      expect(tester.getSize(find.byType(VeilConversationCard)).height, greaterThanOrEqualTo(72));
      // A screen reader hears that the row is a chat, and with whom.
      expect(find.bySemanticsLabel(RegExp(RegExp.escape('Chat with $name'))), findsOneWidget);
    });

    testWidgets('a group switch row without onChanged keeps a disabled switch', (tester) async {
      // One-time link passes onChanged: null while a link is being made; the
      // switch must stay and keep showing its state.
      await tester.pumpWidget(_app(const Column(children: [
        VeilGroupSwitchRow(title: 'Lock with a passphrase', value: true, onChanged: null),
        VeilGroupSwitchRow(title: 'Send typing indicators', value: false, onChanged: null),
      ])));
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect([for (final s in switches) s.value], [true, false]);
      expect([for (final s in switches) s.onChanged], [null, null]);
    });

    testWidgets('the initial badge is the neutral disc, not a colour seeded by the display name', (tester) async {
      // Lists seed a person's colour by handle; the badge only knows the
      // name, so a colour here would give one person two colours.
      await tester.pumpWidget(_app(const VeilInitialBadge(name: 'Alexandra Montgomery-Whitfield', size: 56)));
      final avatar = tester.widget<VeilAvatar>(find.byType(VeilAvatar));
      expect(avatar.unknown, isTrue);
      final disc = tester.widget<Container>(find.descendant(of: find.byType(VeilAvatar), matching: find.byType(Container)));
      expect((disc.decoration! as BoxDecoration).color, VeilAvatar.neutralDark);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    test('the old tone name still resolves', () {
      expect(VeilBannerTone.warn, VeilTone.warn);
      expect(VeilBannerTone.values, VeilTone.values);
    });
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
