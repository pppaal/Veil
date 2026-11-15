import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/router/main_tab_shell.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import 'layout/support/phone_layout_probe.dart';

// What the design system (docs/mobile-design-system.md) promises every
// screen: the platform font, one type scale with no tracking, a 52dp opaque
// bar, groups and rows with inset hairlines, status as a word in a tone
// colour, notices with one text button, stable avatar colours, bubbles with
// the right corners, a plain tab bar, and 44dp tap targets.

void main() {
  setUpAll(loadTestFonts);

  group('theme', () {
    test('uses the platform font unless the test harness passes a family', () {
      final platformFamily = ThemeData(useMaterial3: true).textTheme.bodyMedium!.fontFamily;
      for (final theme in [VeilTheme.dark(), VeilTheme.light()]) {
        expect(theme.textTheme.bodyMedium?.fontFamily, platformFamily);
        expect(theme.textTheme.titleLarge?.fontFamily, platformFamily);
        expect(theme.textTheme.bodyMedium?.fontFamily, isNot('Pretendard'));
      }
      final harnessed = VeilTheme.dark(fontFamily: layoutFontFamily);
      expect(harnessed.textTheme.bodyMedium?.fontFamily, layoutFontFamily);
      expect(harnessed.textTheme.headlineLarge?.fontFamily, layoutFontFamily);
      expect(harnessed.appBarTheme.titleTextStyle?.fontFamily, layoutFontFamily);
      // Button text replaces the ambient style, so it has to carry the
      // family itself.
      expect(harnessed.filledButtonTheme.style?.textStyle?.resolve({})?.fontFamily, layoutFontFamily);
      expect(harnessed.textButtonTheme.style?.textStyle?.resolve({})?.fontFamily, layoutFontFamily);
    });

    test('the scale is the spec\'s, with a height on every style and no positive tracking', () {
      final text = VeilTheme.light().textTheme;
      final expected = <TextStyle?, (double, double, FontWeight)>{
        text.headlineLarge: (28, 1.2, FontWeight.w700),
        text.headlineMedium: (22, 1.25, FontWeight.w600),
        text.titleLarge: (17, 1.3, FontWeight.w600),
        text.titleMedium: (16, 1.3, FontWeight.w600),
        text.titleSmall: (15, 1.3, FontWeight.w600),
        text.bodyLarge: (16, 1.4, FontWeight.w400),
        text.bodyMedium: (15, 1.4, FontWeight.w400),
        text.bodySmall: (13, 1.35, FontWeight.w400),
        text.labelLarge: (15, 1.2, FontWeight.w600),
        text.labelMedium: (13, 1.2, FontWeight.w500),
        text.labelSmall: (11, 1.2, FontWeight.w500),
      };
      for (final MapEntry(key: style, value: (size, height, weight)) in expected.entries) {
        expect(style?.fontSize, size, reason: style?.debugLabel);
        expect(style?.height, height, reason: style?.debugLabel);
        expect(style?.fontWeight, weight, reason: style?.debugLabel);
        expect(style?.letterSpacing, lessThanOrEqualTo(0), reason: style?.debugLabel);
        expect(style?.letterSpacing, greaterThanOrEqualTo(-0.3), reason: style?.debugLabel);
      }
    });

    test('bars are 52 and opaque, buttons 48, text buttons 44, and white sits on the brand fill', () {
      for (final theme in [VeilTheme.dark(), VeilTheme.light()]) {
        final palette = VeilPalette.forBrightness(theme.brightness);
        expect(theme.appBarTheme.toolbarHeight, 52);
        expect(theme.appBarTheme.backgroundColor, palette.canvas);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.colorScheme.onPrimary, Colors.white);
        expect(theme.filledButtonTheme.style?.minimumSize?.resolve({})?.height, 48);
        expect(theme.outlinedButtonTheme.style?.minimumSize?.resolve({})?.height, 48);
        expect(theme.textButtonTheme.style?.minimumSize?.resolve({})?.height, 44);
        expect(theme.textButtonTheme.style?.foregroundColor?.resolve({}), palette.primaryStrong);
        expect(theme.iconButtonTheme.style?.backgroundColor?.resolve({}), Colors.transparent);
        expect(theme.dividerTheme.thickness, 0.5);
        expect(theme.navigationBarTheme.height, 56);
        expect(theme.navigationBarTheme.indicatorColor, Colors.transparent);
        expect(theme.navigationBarTheme.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
        expect(theme.navigationBarTheme.iconTheme?.resolve({WidgetState.selected})?.color, palette.primaryStrong);
        expect(theme.navigationBarTheme.iconTheme?.resolve({})?.color, palette.textMuted);
      }
    });
  });

  group('VeilShell', () {
    testWidgets('draws an opaque 52dp bar with a hairline and no blur, gradient or shadow', (tester) async {
      await tester.pumpWidget(const _App(child: VeilShell(title: 'Chats', child: SizedBox.expand())));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.getSize(find.byType(NavigationToolbar)).height, 52);
      final decorations = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).map((box) => box.decoration);
      for (final decoration in decorations.whereType<BoxDecoration>()) {
        expect(decoration.gradient, isNull);
        expect(decoration.boxShadow, anyOf(isNull, isEmpty));
      }
      final bar = decorations.whereType<BoxDecoration>().firstWhere((decoration) => decoration.border != null);
      expect(bar.color, VeilPalette.dark.canvas);
      expect((bar.border! as Border).bottom.width, 0.5);
      expect(find.text('Chats'), findsOneWidget);
    });

    testWidgets('a grouped page is canvasAlt and shows the subtitle under the title', (tester) async {
      await tester.pumpWidget(
        const _App(
          light: true,
          child: VeilShell(title: 'Chats', subtitle: 'Connecting…', grouped: true, child: SizedBox.expand()),
        ),
      );
      expect(find.text('Connecting…'), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, VeilPalette.light.canvasAlt);
    });

    testWidgets('the back glyph is the platform\'s', (tester) async {
      await tester.pumpWidget(const _App(child: VeilShell(title: 'x', leading: VeilBackButton(), child: SizedBox())));
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      await tester.pumpWidget(
        const _App(platform: TargetPlatform.iOS, child: VeilShell(title: 'x', leading: VeilBackButton(), child: SizedBox())),
      );
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    });
  });

  group('VeilGroup and VeilRow', () {
    testWidgets('on a grouped page the rows sit in a container with hairlines inset to the text', (tester) async {
      await tester.pumpWidget(
        const _App(
          light: true,
          child: VeilShell(
            title: 'Settings',
            grouped: true,
            child: VeilGroup(header: 'Privacy', footer: 'A line under it.', children: [
              VeilRow(title: 'Send read receipts'),
              VeilRow(title: 'Send typing indicators'),
            ]),
          ),
        ),
      );
      // The container keeps 16 from the sides; the hairline starts another
      // 16 in, at the text edge.
      expect(tester.getRect(find.byType(VeilRow).first).left, 16);
      expect(tester.getTopLeft(find.byType(Divider)).dx, 32);
      final container = tester.widgetList<Material>(find.byType(Material)).firstWhere((m) => m.color == VeilPalette.light.surface);
      expect((container.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(10));
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('A line under it.'), findsOneWidget);
    });

    testWidgets('on a white page the rows run full-bleed, and the inset follows the leading', (tester) async {
      await tester.pumpWidget(
        const _App(
          child: VeilShell(
            title: 'Contacts',
            child: VeilGroup(inset: 68, children: [
              VeilRow(title: 'Alex Kim', subtitle: '@alex', leading: VeilAvatar(name: 'Alex Kim', seed: 'alex')),
              VeilRow(title: 'Sam Rivera', subtitle: '@sam', leading: VeilAvatar(name: 'Sam Rivera', seed: 'sam')),
            ]),
          ),
        ),
      );
      expect(tester.getRect(find.byType(VeilRow).first).left, 0);
      expect(tester.getRect(find.byType(VeilRow).first).width, 390);
      expect(tester.getTopLeft(find.byType(Divider)).dx, 68);
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.thickness, 0.5);
      expect(divider.color, VeilPalette.dark.stroke);
    });

    testWidgets('rows are 44, 52 with a subtitle and 60 with a leading avatar', (tester) async {
      await tester.pumpWidget(
        const _App(
          child: VeilShell(
            title: 'x',
            child: Column(children: [
              VeilRow(title: 'One line'),
              VeilRow(title: 'Two', subtitle: 'lines'),
              VeilRow(title: 'Avatar', leading: VeilAvatar(name: 'A', seed: 'a')),
            ]),
          ),
        ),
      );
      final heights = [for (final row in find.byType(VeilRow).evaluate()) tester.getSize(find.byWidget(row.widget)).height];
      expect(heights[0], 44);
      expect(heights[1], greaterThanOrEqualTo(52));
      expect(heights[2], 60);
    });

    testWidgets('status is a word in the tone colour; a destination gets a chevron; destructive gets none',
        (tester) async {
      var switched = false;
      await tester.pumpWidget(
        _App(
          light: true,
          child: VeilShell(
            title: 'x',
            child: StatefulBuilder(
              builder: (context, setState) => Column(children: [
                const VeilRow(title: 'Safety number', status: ('Verified', VeilTone.good)),
                const VeilRow(title: 'Old phone', status: ('Stale', VeilTone.warn)),
                const VeilRow(title: 'Lost phone', status: ('Revoked', VeilTone.danger)),
                const VeilRow(title: 'App lock', value: 'Off', onTap: _noop),
                const VeilRow(title: 'Delete account', destructive: true, onTap: _noop),
                VeilRow(
                  title: 'Send read receipts',
                  switchValue: switched,
                  onSwitch: (value) => setState(() => switched = value),
                ),
              ]),
            ),
          ),
        ),
      );
      final palette = VeilPalette.light;
      Color colorOf(String text) => tester.widget<Text>(find.text(text)).style!.color!;
      expect(colorOf('Verified'), palette.success);
      expect(colorOf('Stale'), palette.warning);
      expect(colorOf('Revoked'), palette.danger);
      expect(colorOf('Off'), palette.textMuted);
      expect(colorOf('Delete account'), palette.danger);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget, reason: 'only the row that opens something');
      expect(find.descendant(of: find.widgetWithText(VeilRow, 'App lock'), matching: find.byIcon(Icons.chevron_right)),
          findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      await tester.tap(find.text('Send read receipts'));
      await tester.pumpAndSettle();
      expect(switched, isTrue, reason: 'the whole row toggles the switch');
      // No pill: a status word has no box of its own.
      expect(find.ancestor(of: find.text('Verified'), matching: find.byType(DecoratedBox)), findsNothing);
    });

    testWidgets('a field row hosts a borderless text field', (tester) async {
      await tester.pumpWidget(
        const _App(
          child: VeilShell(
            title: 'Profile',
            grouped: true,
            child: VeilGroup(children: [
              VeilRow.field(title: 'Nickname', field: TextField(decoration: InputDecoration(hintText: 'Nickname'))),
            ]),
          ),
        ),
      );
      final decorator = tester.widget<InputDecorator>(find.byType(InputDecorator));
      expect(decorator.decoration.filled, isFalse);
      expect(decorator.decoration.border, InputBorder.none);
      expect(tester.getSize(find.byType(VeilRow)).height, greaterThanOrEqualTo(44));
    });
  });

  group('VeilNotice', () {
    testWidgets('is a grey box with the tone as its icon and one text button', (tester) async {
      var acted = false;
      await tester.pumpWidget(
        _App(
          light: true,
          child: VeilShell(
            title: 'x',
            child: Column(children: [
              VeilNotice(
                title: 'Safety number changed',
                message: 'Nothing is sent until you review it.',
                tone: VeilTone.warn,
                actionLabel: 'Review',
                onAction: () => acted = true,
              ),
              const VeilNotice(message: '2 messages not sent', tone: VeilTone.danger, actionLabel: 'Retry now', onAction: _noop),
              const VeilNotice(message: 'Just so you know'),
            ]),
          ),
        ),
      );
      final palette = VeilPalette.light;
      expect(tester.widget<Icon>(find.byIcon(Icons.warning_amber_outlined)).color, palette.warning);
      expect(tester.widget<Icon>(find.byIcon(Icons.error_outline)).color, palette.danger);
      expect(tester.widget<Icon>(find.byIcon(Icons.info_outlined)).color, palette.textMuted);
      for (final box in tester.widgetList<Container>(find.descendant(of: find.byType(VeilNotice), matching: find.byType(Container)))) {
        final decoration = box.decoration! as BoxDecoration;
        expect(decoration.color, palette.surfaceAlt);
        expect(decoration.border, isNull);
        expect(decoration.gradient, isNull);
        expect(decoration.borderRadius, BorderRadius.circular(10));
      }
      // The box keeps 12 from the sides of a white page.
      expect(tester.getRect(find.byType(Container).first).left, 12);
      expect(find.byType(TextButton), findsNWidgets(2));
      final retry = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Retry now'));
      expect(retry.style?.foregroundColor?.resolve({}), palette.danger, reason: 'a danger notice acts in danger');
      await tester.tap(find.text('Review'));
      expect(acted, isTrue);
    });

    testWidgets('dense is one 44dp row, and inside a group it is a row without corners', (tester) async {
      await tester.pumpWidget(
        const _App(
          child: VeilShell(
            title: 'x',
            grouped: true,
            child: Column(children: [
              VeilNotice(title: '2 messages not sent', message: 'later', tone: VeilTone.warn, dense: true, actionLabel: 'Retry', onAction: _noop),
              VeilGroup(children: [
                VeilRow(title: 'Old phone', status: ('Stale', VeilTone.warn)),
                VeilNotice(message: 'A device has not been seen for 30 days.', tone: VeilTone.warn, actionLabel: 'Review', onAction: _noop),
              ]),
            ]),
          ),
        ),
      );
      final dense = find.byType(VeilNotice).first;
      expect(tester.getSize(dense).height, 44);
      final inGroup = tester.widget<Container>(
        find.descendant(of: find.byType(VeilNotice).last, matching: find.byType(Container)),
      );
      expect((inGroup.decoration! as BoxDecoration).borderRadius, isNull);
      // Flush with the group's edge: no margin of its own.
      expect(tester.getRect(find.byType(VeilNotice).last).left, 16);
    });
  });

  group('VeilAvatar', () {
    test('picks its colour by FNV-1a of the seed, the same on every platform', () {
      expect(VeilAvatar.indexOf('alex'), 5);
      expect(VeilAvatar.indexOf('한지우'), 6);
      expect(VeilAvatar.indexOf('sam'), 4);
      expect(VeilAvatar.indexOf('priya'), 0);
      expect(VeilAvatar.colorOf('alex'), VeilAvatar.colors[5]);
      expect(veilFnv1a32('alex'), 3852794181);
    });

    testWidgets('is a flat disc with a white initial, a glyph for a group, and no semantics', (tester) async {
      await tester.pumpWidget(
        const _App(
          child: Scaffold(
            body: Row(children: [
              VeilAvatar(name: 'Alex Kim', seed: 'alex', size: 48),
              VeilAvatar(name: 'Weekend plans', seed: 'conv-1', size: 48, group: true),
            ]),
          ),
        ),
      );
      final letter = tester.widget<Text>(find.text('A'));
      expect(letter.style?.color, Colors.white);
      expect(letter.style?.fontWeight, FontWeight.w600);
      expect(letter.style?.fontSize, 48 * 0.42);
      expect(find.text('W'), findsNothing, reason: 'a group never shows a letter');
      expect(find.byIcon(Icons.group_outlined), findsOneWidget);
      for (final disc in tester.widgetList<Container>(find.descendant(of: find.byType(VeilAvatar), matching: find.byType(Container)))) {
        final decoration = disc.decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        expect(decoration.gradient, isNull);
        expect(decoration.border, isNull);
        expect(decoration.boxShadow, isNull);
      }
      expect(tester.widgetList(find.byType(VeilAvatar)).first, isA<VeilAvatar>());
      expect(tester.getSize(find.byType(VeilAvatar).first), const Size(48, 48));
      expect(find.byType(ExcludeSemantics), findsNWidgets(2));
    });

    testWidgets('the name tint follows the theme', (tester) async {
      late Color dark, light;
      await tester.pumpWidget(_App(child: Builder(builder: (context) {
        dark = VeilAvatar.nameTint(context, 'alex');
        return const SizedBox();
      })));
      await tester.pumpWidget(_App(light: true, child: Builder(builder: (context) {
        light = VeilAvatar.nameTint(context, 'alex');
        return const SizedBox();
      })));
      expect(dark, VeilAvatar.nameTintsDark[5]);
      expect(light, VeilAvatar.nameTintsLight[5]);
    });
  });

  group('VeilBubble', () {
    BoxDecoration decorationOf(WidgetTester tester, Finder bubble) =>
        tester.widget<DecoratedBox>(find.descendant(of: bubble, matching: find.byType(DecoratedBox)).first).decoration
            as BoxDecoration;

    testWidgets('corners: 18, with the tail corner 4 at the end of a run and 6 inside it', (tester) async {
      await tester.pumpWidget(
        const _App(
          child: Scaffold(
            body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              VeilBubble(isMine: true, position: VeilBubblePosition.last, child: Text('a')),
              VeilBubble(isMine: true, position: VeilBubblePosition.first, child: Text('b')),
              VeilBubble(isMine: false, position: VeilBubblePosition.single, child: Text('c')),
              VeilBubble(isMine: false, position: VeilBubblePosition.middle, child: Text('d')),
            ]),
          ),
        ),
      );
      final bubbles = find.byType(VeilBubble);
      final mineLast = decorationOf(tester, bubbles.at(0)).borderRadius! as BorderRadius;
      expect(mineLast.topLeft, const Radius.circular(18));
      expect(mineLast.bottomLeft, const Radius.circular(18));
      expect(mineLast.bottomRight, const Radius.circular(4));
      expect((decorationOf(tester, bubbles.at(1)).borderRadius! as BorderRadius).bottomRight, const Radius.circular(6));
      final theirsSingle = decorationOf(tester, bubbles.at(2)).borderRadius! as BorderRadius;
      expect(theirsSingle.bottomLeft, const Radius.circular(4));
      expect(theirsSingle.bottomRight, const Radius.circular(18));
      expect((decorationOf(tester, bubbles.at(3)).borderRadius! as BorderRadius).bottomLeft, const Radius.circular(6));
    });

    testWidgets('fills: brand for mine, surfaceAlt for theirs and for a failed send with its line', (tester) async {
      await tester.pumpWidget(
        const _App(
          child: Scaffold(
            body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              VeilBubble(isMine: true, child: Text('mine')),
              VeilBubble(isMine: false, child: Text('theirs')),
              VeilBubble(isMine: true, failed: true, failedText: 'Not sent. Tap to retry.', child: Text('lost')),
              VeilBubble(isMine: false, highlighted: true, child: Text('hit')),
            ]),
          ),
        ),
      );
      final palette = VeilPalette.dark;
      final bubbles = find.byType(VeilBubble);
      expect(decorationOf(tester, bubbles.at(0)).color, palette.primary);
      expect(decorationOf(tester, bubbles.at(0)).gradient, isNull);
      expect(decorationOf(tester, bubbles.at(0)).boxShadow, isNull);
      expect(decorationOf(tester, bubbles.at(0)).border, isNull);
      expect(decorationOf(tester, bubbles.at(1)).color, palette.surfaceAlt);
      expect(decorationOf(tester, bubbles.at(2)).color, palette.surfaceAlt);
      expect(find.text('Not sent. Tap to retry.'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Not sent. Tap to retry.')).style?.color, palette.danger);
      final highlighted = decorationOf(tester, bubbles.at(3));
      expect(highlighted.color, palette.surfaceRaised);
      expect((highlighted.border! as Border).top.color, palette.primaryStrong);
      expect((highlighted.border! as Border).top.width, 1.5);
      expect(DefaultTextStyle.of(tester.element(find.text('mine'))).style.color, Colors.white);
      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('takes at most 78% of the width it is given', (tester) async {
      await tester.pumpWidget(
        const _App(
          child: Scaffold(
            body: SizedBox(
              width: 300,
              child: Align(
                alignment: Alignment.centerLeft,
                child: VeilBubble(isMine: false, child: Text('a message long enough to need every pixel of width it can get')),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(DecoratedBox).first).width, 300 * 0.78);
    });
  });

  group('VeilComposer', () {
    testWidgets('five lines at most, no padlock, a hairline above, the reason as the hint when disabled', (tester) async {
      final controller = TextEditingController(text: 'Draft');
      final focusNode = FocusNode();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });
      Widget composer({required bool enabled}) => VeilComposer(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            onSubmit: () {},
            label: 'Message',
            helper: 'Review the safety number first',
            trailing: const SizedBox(width: 32, height: 32),
          );
      await tester.pumpWidget(_App(child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: composer(enabled: true)))));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, 5);
      expect(field.decoration?.hintText, 'Message');
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.text('Draft'), findsOneWidget);
      expect(tester.getSize(find.byType(VeilComposer)).height, greaterThanOrEqualTo(44 + 12));
      final strip = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration as BoxDecoration;
      expect(strip.color, VeilPalette.dark.canvas);
      expect((strip.border! as Border).top.width, 0.5);

      await tester.pumpWidget(_App(child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: composer(enabled: false)))));
      expect(tester.widget<TextField>(find.byType(TextField)).decoration?.hintText, 'Review the safety number first');
    });
  });

  group('VeilEmptyState and VeilButton', () {
    testWidgets('an empty state is a title, one line and one button; compact drops the line', (tester) async {
      await tester.pumpWidget(
        const _App(
          child: Scaffold(
            body: Column(children: [
              Expanded(child: VeilEmptyState(title: 'No chats yet', body: 'Start a chat with someone\'s handle.', icon: Icons.chat_bubble_outline)),
              Expanded(child: VeilEmptyState(title: 'No messages yet', body: 'Hidden', compact: true)),
              Expanded(child: VeilEmptyState.error(title: 'Could not load', body: 'Try again.')),
            ]),
          ),
        ),
      );
      expect(find.text('Start a chat with someone\'s handle.'), findsOneWidget);
      expect(find.text('Hidden'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(Icons.chat_bubble_outline)).color, VeilPalette.dark.textSubtle);
      expect(find.byType(DecoratedBox), findsNothing, reason: 'no tile behind the icon');
    });

    testWidgets('a destructive button is a text button in the danger colour; nothing is filled red', (tester) async {
      await tester.pumpWidget(
        const _App(
          light: true,
          child: Scaffold(
            body: Column(children: [
              VeilButton(label: 'Continue', onPressed: _noop),
              VeilButton(label: 'Cancel', onPressed: _noop, tone: VeilButtonTone.secondary),
              VeilButton(label: 'Delete account', onPressed: _noop, tone: VeilButtonTone.destructive),
              VeilButton(label: 'Later', onPressed: _noop, tone: VeilButtonTone.ghost),
            ]),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(TextButton), findsNWidgets(2));
      final destructive = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete account'));
      expect(destructive.style?.foregroundColor?.resolve({}), VeilPalette.light.danger);
      expect(tester.getSize(find.byType(FilledButton)).height, 48);
      expect(tester.getSize(find.widgetWithText(TextButton, 'Later')).height, greaterThanOrEqualTo(44));
    });

    testWidgets('a toast is a snackbar on surfaceRaised with the tone as an icon', (tester) async {
      await tester.pumpWidget(
        _App(
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showVeilToast(context, 'Nickname saved', tone: VeilTone.good),
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Nickname saved'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(Theme.of(tester.element(find.byType(SnackBar))).snackBarTheme.backgroundColor, VeilPalette.dark.surfaceRaised);
    });
  });

  group('MainTabShell', () {
    testWidgets('is a NavigationBar with no indicator and no ripple', (tester) async {
      final router = GoRouter(
        initialLocation: '/conversations',
        routes: [
          ShellRoute(
            builder: (context, state, child) => MainTabShell(child: child),
            routes: [
              for (final path in ['/conversations', '/contacts', '/settings'])
                GoRoute(path: path, builder: (context, state) => Center(child: Text(path))),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: VeilTheme.light(fontFamily: layoutFontFamily),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();
      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(Theme.of(tester.element(bar)).splashFactory, NoSplash.splashFactory);
      expect(tester.widget<NavigationBar>(bar).selectedIndex, 0);
      expect(find.byIcon(Icons.chat_bubble), findsOneWidget, reason: 'the active tab shows the filled glyph');
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('/settings'), findsOneWidget);
      expect(tester.widget<NavigationBar>(bar).selectedIndex, 2);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byType(InkSplash), findsNothing);
    });
  });
}

void _noop() {}

class _App extends StatelessWidget {
  const _App({required this.child, this.light = false, this.platform});

  final Widget child;
  final bool light;
  final TargetPlatform? platform;

  @override
  Widget build(BuildContext context) {
    final theme = light ? VeilTheme.light(fontFamily: layoutFontFamily) : VeilTheme.dark(fontFamily: layoutFontFamily);
    return MaterialApp(
      theme: platform == null ? theme : theme.copyWith(platform: platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), padding: EdgeInsets.zero),
        child: child,
      ),
    );
  }
}
