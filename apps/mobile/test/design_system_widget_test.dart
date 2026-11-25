import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/router/main_tab_shell.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/conversations/presentation/unread_chats.dart';
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

    test('the app bundles no UI font, only icon fonts', () async {
      final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
      final families = [for (final entry in manifest.cast<Map<String, dynamic>>()) entry['family'] as String];
      expect(families, unorderedEquals(['MaterialIcons', 'packages/cupertino_icons/CupertinoIcons']));
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

    test('the switch track is the brand on iOS too, where Flutter would draw it green', () {
      for (final theme in [VeilTheme.dark(), VeilTheme.light()]) {
        final palette = VeilPalette.forBrightness(theme.brightness);
        for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
          final onPlatform = theme.copyWith(platform: platform);
          final adapted = onPlatform.getAdaptation<SwitchThemeData>()!.adapt(onPlatform, onPlatform.switchTheme);
          expect(adapted.trackColor?.resolve({WidgetState.selected}), palette.primary, reason: platform.name);
        }
      }
    });

    test('a disabled switch still reads as on or off, faded', () {
      for (final theme in [VeilTheme.dark(), VeilTheme.light()]) {
        final palette = VeilPalette.forBrightness(theme.brightness);
        final switches = theme.switchTheme;
        const onDisabled = {WidgetState.selected, WidgetState.disabled};
        expect(switches.trackColor?.resolve({WidgetState.selected}), palette.primary);
        final fadedTrack = switches.trackColor!.resolve(onDisabled)!;
        expect(fadedTrack.toARGB32() & 0x00FFFFFF, palette.primary.toARGB32() & 0x00FFFFFF, reason: 'still the brand');
        expect(fadedTrack.a, lessThan(0.5), reason: 'but faded');
        expect(switches.thumbColor?.resolve(onDisabled), Colors.white);
        expect(switches.thumbColor?.resolve({WidgetState.disabled}), palette.textSubtle);
        expect(switches.thumbColor?.resolve({}), Colors.white);
      }
    });

    test('a dark sheet has a hairline along its top edge only; a light sheet has none', () {
      const rect = Rect.fromLTWH(0, 0, 390, 300);
      final dark = VeilTheme.dark().bottomSheetTheme.shape!;
      void paintDark(Canvas canvas) => dark.paint(canvas, rect);
      expect(
        paintDark,
        paints
          ..something((method, arguments) {
            if (method != #drawPath) return false;
            final bounds = (arguments[0] as Path).getBounds();
            final paint = arguments[1] as Paint;
            return paint.color.toARGB32() == VeilPalette.dark.strokeStrong.toARGB32() &&
                paint.strokeWidth == 0.5 &&
                bounds.width >= 389 &&
                bounds.height <= VeilRadius.lg;
          }),
      );
      // No whole outline: that would draw lines down both screen edges.
      expect(paintDark, isNot(paints..drrect()));
      expect(paintDark, isNot(paints..rrect()));
      expect((Canvas canvas) => VeilTheme.light().bottomSheetTheme.shape!.paint(canvas, rect), paintsNothing);
      // The corners are still the sheet's 14.
      expect(dark.getOuterPath(rect).getBounds(), rect);
      expect((dark as RoundedRectangleBorder).borderRadius, const BorderRadius.vertical(top: Radius.circular(14)));
    });
  });

  group('tap targets', () {
    testWidgets('every control is at least 44 by 44', (tester) async {
      var segment = 'Light';
      var checked = false;
      await _pump(
        tester,
        _App(
          light: true,
          child: VeilShell(
            title: 'Settings',
            actions: [IconButton(onPressed: _noop, icon: const Icon(Icons.edit_outlined), tooltip: 'New chat')],
            child: StatefulBuilder(
              builder: (context, setState) => Column(children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Light', label: Text('Light')),
                    ButtonSegment(value: 'Dark', label: Text('Dark')),
                    ButtonSegment(value: 'System', label: Text('System')),
                  ],
                  selected: {segment},
                  onSelectionChanged: (value) => setState(() => segment = value.first),
                ),
                ChoiceChip(label: const Text('Chats'), selected: true, onSelected: (_) {}),
                Checkbox(value: checked, onChanged: (value) => setState(() => checked = value!)),
                const TextField(decoration: InputDecoration(hintText: 'Search')),
                VeilRow(title: 'Send read receipts', switchValue: checked, onSwitch: (value) {}),
              ]),
            ),
          ),
        ),
      );
      void expectTarget(Finder finder, String what) {
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(44), reason: '$what width');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$what height');
      }

      expectTarget(find.byType(IconButton), 'bar action');
      expectTarget(find.byType(SegmentedButton<String>), 'segmented control');
      expectTarget(find.byType(ChoiceChip), 'chip');
      expectTarget(find.byType(Checkbox), 'checkbox');
      expectTarget(find.byType(TextField), 'text field');
      expectTarget(find.byType(VeilRow), 'switch row');
      final barAction = tester.widget<IconButton>(find.byType(IconButton));
      expect(barAction.style, isNull, reason: 'a bar action has no tile of its own');
      expect(
        Theme.of(tester.element(find.byType(IconButton))).iconButtonTheme.style?.backgroundColor?.resolve({}),
        Colors.transparent,
      );
    });
  });

  group('VeilShell', () {
    testWidgets('draws an opaque 52dp bar with a hairline and no blur, gradient or shadow', (tester) async {
      await _pump(tester, const _App(child: VeilShell(title: 'Chats', child: SizedBox.expand(key: Key('page')))));
      expect(find.byType(BackdropFilter), findsNothing);
      // The bar is 52 in all, hairline included, and its content has all 52.
      expect(tester.getSize(find.byType(NavigationToolbar)).height, 52);
      expect(tester.getTopLeft(find.byKey(const Key('page'))).dy, 52, reason: 'the page starts under the bar');
      final decorations = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).map((box) => box.decoration);
      for (final decoration in decorations.whereType<BoxDecoration>()) {
        expect(decoration.gradient, isNull);
        expect(decoration.boxShadow, anyOf(isNull, isEmpty));
      }
      final hairline = decorations.whereType<BoxDecoration>().firstWhere((decoration) => decoration.border != null);
      expect((hairline.border! as Border).bottom.width, 0.5);
      expect((hairline.border! as Border).bottom.color, VeilPalette.dark.stroke);
      final bar = tester.widget<Material>(
        find.ancestor(of: find.byType(NavigationToolbar), matching: find.byType(Material)).first,
      );
      expect(bar.color, VeilPalette.dark.canvas);
      expect(bar.elevation, 0);
      expect(find.text('Chats'), findsOneWidget);
    });

    testWidgets('a grouped page is canvasAlt and shows the subtitle under the title', (tester) async {
      await _pump(
        tester,
        const _App(
          light: true,
          child: VeilShell(title: 'Chats', subtitle: 'Connecting…', grouped: true, child: SizedBox.expand()),
        ),
      );
      expect(find.text('Connecting…'), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, VeilPalette.light.canvasAlt);
    });

    testWidgets('puts no coloured box between the page and its rows, so their ink shows', (tester) async {
      await _pump(
        tester,
        const _App(
          child: VeilShell(
            title: 'Chats',
            child: Column(children: [
              VeilRow(title: 'Alex Kim', onTap: _noop),
              ListTile(title: Text('A plain tile'), onTap: _noop),
            ]),
          ),
        ),
      );
      // ListTile reports a coloured box between it and its Material.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the back glyph is the platform\'s', (tester) async {
      await _pump(tester, const _App(child: VeilShell(title: 'x', leading: VeilBackButton(), child: SizedBox())));
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(tester.getSize(find.byType(VeilBackButton)).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byType(VeilBackButton)).height, greaterThanOrEqualTo(44));
      await _pump(
        tester,
        const _App(
            platform: TargetPlatform.iOS, child: VeilShell(title: 'x', leading: VeilBackButton(), child: SizedBox())),
      );
      // MaterialApp animates a theme change; the platform flips half way.
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });

  group('VeilGroup and VeilRow', () {
    testWidgets('on a grouped page the rows sit in a container with hairlines inset to the text', (tester) async {
      await _pump(
        tester,
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
      final container =
          tester.widgetList<Material>(find.byType(Material)).firstWhere((m) => m.color == VeilPalette.light.surface);
      expect((container.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(10));
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('A line under it.'), findsOneWidget);
    });

    testWidgets('on a white page the rows run full-bleed, and the inset follows the leading', (tester) async {
      await _pump(
        tester,
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

    testWidgets('in a sheet the rows run full-bleed on the sheet, with lines that show on it', (tester) async {
      await _pump(
        tester,
        _App(
          child: VeilShell(
            title: 'Contacts',
            grouped: true,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const VeilGroup(children: [
                    VeilRow(title: 'Start chat', onTap: _noop),
                    VeilRow(title: 'Remove contact', destructive: true, onTap: _noop),
                  ]),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final palette = VeilPalette.dark;
      expect(tester.getRect(find.byType(VeilRow).first).left, 0, reason: 'no container even over a grouped page');
      expect(tester.getRect(find.byType(VeilRow).first).width, 390);
      expect(
        find.descendant(
          of: find.byType(VeilGroup),
          matching: find.byWidgetPredicate((w) => w is Material && w.color == palette.surface),
        ),
        findsNothing,
      );
      // `stroke` is the sheet's own colour in the dark theme.
      expect(tester.widget<Divider>(find.byType(Divider)).color, palette.strokeStrong);
    });

    testWidgets('rows are 44, 52 with a subtitle and 60 with a leading avatar', (tester) async {
      await _pump(
        tester,
        const _App(
          child: VeilShell(
            title: 'x',
            child: Column(children: [
              VeilRow(title: 'One line'),
              VeilRow(title: 'Two', subtitle: 'lines'),
              VeilRow(title: 'Avatar', leading: VeilAvatar(name: 'A', seed: 'a')),
              VeilRow(title: 'Avatar', subtitle: '@a', leading: VeilAvatar(name: 'A', seed: 'a')),
            ]),
          ),
        ),
      );
      final heights = [
        for (final row in find.byType(VeilRow).evaluate()) tester.getSize(find.byWidget(row.widget)).height
      ];
      expect(heights[0], 44);
      expect(heights[1], greaterThanOrEqualTo(52));
      expect(heights[2], 60);
      // A subtitle does not let ListTile's compact layout shrink the row
      // under its minimum (it drew this one 54).
      expect(heights[3], inInclusiveRange(60, 61));
    });

    testWidgets('status is a word in the tone colour; a destination gets a chevron; destructive gets none',
        (tester) async {
      var switched = false;
      await _pump(
        tester,
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

    testWidgets('a disabled switch row still shows and announces its state', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        const _App(
          light: true,
          child: VeilShell(
            title: 'x',
            grouped: true,
            child: VeilGroup(children: [
              VeilRow(title: 'Lock with a passphrase', switchValue: true),
              VeilRow(title: 'Send typing indicators', subtitle: 'Saving…', switchValue: false),
            ]),
          ),
        ),
      );
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches, hasLength(2), reason: 'a row without onSwitch keeps its switch');
      expect([for (final s in switches) s.value], [true, false]);
      expect([for (final s in switches) s.onChanged], [null, null], reason: 'both are disabled');

      // Tapping the row does nothing and throws nothing.
      await tester.tap(find.text('Lock with a passphrase'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final node = tester.getSemantics(find.text('Lock with a passphrase'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isToggled.toBoolOrNull(), isTrue, reason: 'its state is announced');
      expect(data.flagsCollection.isEnabled.toBoolOrNull(), isFalse, reason: 'and that it cannot be changed');
      semantics.dispose();
    });

    testWidgets('a field row hosts a borderless text field', (tester) async {
      await _pump(
        tester,
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
      await _pump(
        tester,
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
              const VeilNotice(
                  message: '2 messages not sent', tone: VeilTone.danger, actionLabel: 'Retry now', onAction: _noop),
              const VeilNotice(message: 'Just so you know'),
            ]),
          ),
        ),
      );
      final palette = VeilPalette.light;
      expect(tester.widget<Icon>(find.byIcon(Icons.warning_amber_outlined)).color, palette.warning);
      expect(tester.widget<Icon>(find.byIcon(Icons.error_outline)).color, palette.danger);
      expect(tester.widget<Icon>(find.byIcon(Icons.info_outlined)).color, palette.textMuted);
      for (final box in tester
          .widgetList<Container>(find.descendant(of: find.byType(VeilNotice), matching: find.byType(Container)))) {
        final decoration = box.decoration! as BoxDecoration;
        expect(decoration.color, palette.surfaceAlt);
        expect(decoration.border, isNull);
        expect(decoration.gradient, isNull);
        expect(decoration.borderRadius, BorderRadius.circular(10));
      }
      // The box keeps 12 from the sides of a white page.
      expect(tester.getRect(find.byType(Container).first).left, 12);
      // The button ends the box: its label is about as far from the bottom
      // as the icon is from the top, with no empty band under it.
      final first = tester.getRect(find.byType(VeilNotice).first);
      final iconGap = tester.getRect(find.byIcon(Icons.warning_amber_outlined)).top - first.top;
      final labelGap = first.bottom - tester.getRect(find.text('Review')).bottom;
      expect((labelGap - iconGap).abs(), lessThanOrEqualTo(4), reason: 'icon $iconGap, label $labelGap');
      expect(tester.getSize(find.widgetWithText(TextButton, 'Review')).height, greaterThanOrEqualTo(44));
      expect(find.byType(TextButton), findsNWidgets(2));
      final retry = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Retry now'));
      expect(retry.style?.foregroundColor?.resolve({}), palette.danger, reason: 'a danger notice acts in danger');
      await tester.tap(find.text('Review'));
      expect(acted, isTrue);
    });

    testWidgets('dense is one 44dp row, and inside a group it is a row without corners', (tester) async {
      await _pump(
        tester,
        const _App(
          child: VeilShell(
            title: 'x',
            grouped: true,
            child: Column(children: [
              VeilNotice(
                  title: '2 messages not sent',
                  message: 'later',
                  tone: VeilTone.warn,
                  dense: true,
                  actionLabel: 'Retry',
                  onAction: _noop),
              VeilGroup(children: [
                VeilRow(title: 'Old phone', status: ('Stale', VeilTone.warn)),
                VeilNotice(
                    message: 'A device has not been seen for 30 days.',
                    tone: VeilTone.warn,
                    actionLabel: 'Review',
                    onAction: _noop),
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
      await _pump(
        tester,
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
      for (final disc in tester
          .widgetList<Container>(find.descendant(of: find.byType(VeilAvatar), matching: find.byType(Container)))) {
        final decoration = disc.decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        expect(decoration.gradient, isNull);
        expect(decoration.border, isNull);
        expect(decoration.boxShadow, isNull);
      }
      expect(tester.getSize(find.byType(VeilAvatar).first), const Size(48, 48));
      // A screen reader hears nothing of it: the row carries the name.
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('A'), findsNothing);
      for (final avatar in find.byType(VeilAvatar).evaluate()) {
        final excluded = find.descendant(of: find.byWidget(avatar.widget), matching: find.byType(ExcludeSemantics));
        expect(tester.widget<ExcludeSemantics>(excluded.first).excluding, isTrue);
      }
      semantics.dispose();
    });

    testWidgets('the name tint follows the theme', (tester) async {
      late Color dark, light;
      await _pump(tester, _App(child: Builder(builder: (context) {
        dark = VeilAvatar.nameTint(context, 'alex');
        return const SizedBox();
      })));
      await _pump(
          tester,
          _App(
              light: true,
              child: Builder(builder: (context) {
                light = VeilAvatar.nameTint(context, 'alex');
                return const SizedBox();
              })));
      // MaterialApp animates a theme change; the brightness flips half way.
      await tester.pumpAndSettle();
      expect(dark, VeilAvatar.nameTintsDark[5]);
      expect(light, VeilAvatar.nameTintsLight[5]);
    });
  });

  group('VeilBubble', () {
    BoxDecoration decorationOf(WidgetTester tester, Finder bubble) =>
        tester.widget<DecoratedBox>(find.descendant(of: bubble, matching: find.byType(DecoratedBox)).first).decoration
            as BoxDecoration;

    testWidgets('corners: 18, with the tail corner 4 at the end of a run and 6 inside it', (tester) async {
      await _pump(
        tester,
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

    testWidgets('fills: brand for mine, surfaceAlt for theirs; a failed send keeps its fill, with a glyph and its line', (tester) async {
      await _pump(
        tester,
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
      // A failed send keeps its own fill; the glyph beside it and the line
      // under it say it failed, as Signal draws one.
      expect(decorationOf(tester, bubbles.at(2)).color, palette.primary);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
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
      await _pump(
        tester,
        const _App(
          child: Scaffold(
            body: SizedBox(
              width: 300,
              child: Align(
                alignment: Alignment.centerLeft,
                child: VeilBubble(
                    isMine: false, child: Text('a message long enough to need every pixel of width it can get')),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(DecoratedBox).first).width, 300 * 0.78);
    });
  });

  group('VeilComposer', () {
    testWidgets('five lines at most, no padlock, a hairline above, the reason as the hint when disabled',
        (tester) async {
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
      await _pump(tester,
          _App(child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: composer(enabled: true)))));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, 5);
      expect(field.decoration?.hintText, 'Message');
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      expect(find.text('Draft'), findsOneWidget);
      // The text field is the 44dp tap target; the grey field inside it is
      // 4 shorter at the top and the bottom.
      final fieldSize = tester.getSize(find.byType(TextField));
      expect(fieldSize.height, greaterThanOrEqualTo(44));
      final pill = find.descendant(
        of: find.byType(VeilComposer),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox && (widget.decoration as BoxDecoration).color == VeilPalette.dark.surfaceAlt,
        ),
      );
      expect(tester.getSize(pill).height, closeTo(fieldSize.height - 2 * VeilComposer.fieldInset, 0.01));
      expect(
        ((tester.widget<DecoratedBox>(pill).decoration as BoxDecoration).borderRadius! as BorderRadius).topLeft,
        const Radius.circular(18),
      );
      expect(tester.getSize(find.byType(VeilComposer)).height, greaterThanOrEqualTo(44 + 12));
      final strip = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration as BoxDecoration;
      expect(strip.color, VeilPalette.dark.canvas);
      expect((strip.border! as Border).top.width, 0.5);

      await _pump(tester,
          _App(child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: composer(enabled: false)))));
      expect(tester.widget<TextField>(find.byType(TextField)).decoration?.hintText, 'Review the safety number first');
    });
  });

  group('VeilEmptyState and VeilButton', () {
    testWidgets('an empty state is a title, one line and one button; compact drops the line', (tester) async {
      await _pump(
        tester,
        const _App(
          child: Scaffold(
            body: Column(children: [
              Expanded(
                  child: VeilEmptyState(
                      title: 'No chats yet',
                      body: 'Start a chat with someone\'s handle.',
                      icon: Icons.chat_bubble_outline)),
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

    testWidgets('notices and the error state still render with larger text on the smallest phone', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final scale in [1.4, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpWidget(
          const _App(
            light: true,
            child: Scaffold(
              body: Column(children: [
                VeilNotice(
                  title: 'Safety number changed',
                  message: 'Nothing is sent until you review it.',
                  tone: VeilTone.warn,
                  actionLabel: 'Review',
                  onAction: _noop,
                ),
                VeilNotice(message: '2 messages not sent', tone: VeilTone.danger, dense: true, actionLabel: 'Retry', onAction: _noop),
                Expanded(child: VeilEmptyState.error(title: 'Could not load your chats', body: 'Check your connection.')),
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'nothing overflows at $scale');
        expect(find.text('Nothing is sent until you review it.'), findsOneWidget);
        expect(find.text('Review'), findsOneWidget);
        expect(find.text('Could not load your chats'), findsOneWidget);
        expect(find.text('Check your connection.'), findsOneWidget);
      }
    });

    testWidgets('a destructive button is a text button in the danger colour; nothing is filled red', (tester) async {
      await _pump(
        tester,
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

    // As Signal's, WhatsApp's and Telegram's: text, at most one action, and
    // no tone icon, success or failure.
    testWidgets('a toast is a snackbar on surfaceRaised, text only', (tester) async {
      await _pump(
        tester,
        _App(
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showVeilToast(context, 'Nickname saved'),
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
      expect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)), findsNothing);
      expect(Theme.of(tester.element(find.byType(SnackBar))).snackBarTheme.backgroundColor,
          VeilPalette.dark.surfaceRaised);
    });
  });

  // A toast over a chat's composer covers the whole field: its sides are
  // 12 from the screen's edges, as the field's are, so no end of the field
  // peeks out beside it.
  testWidgets('a toast keeps 12 from each side of the screen, as the composer field does', (tester) async {
    await _pump(
      tester,
      _App(
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showVeilToast(context, 'Files can be up to 25 MB'),
              child: const Text('Attach'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Attach'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The toast's own surface; the SnackBar's box takes its inset too.
    final toast = tester.getRect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);
    final screen = tester.getRect(find.byType(Scaffold));
    expect(toast.left - screen.left, VeilSpace.sm);
    expect(screen.right - toast.right, VeilSpace.sm);
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
      // The shell reads how many chats are unread for the Chats badge.
      await _pump(
          tester,
          ProviderScope(
            overrides: [unreadChatsProvider.overrideWith((ref) => 0)],
            child: MaterialApp.router(
              theme: VeilTheme.light(fontFamily: layoutFontFamily),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
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

      // 56 tall on the page colour with a hairline above; each tab is a
      // full-height target.
      expect(tester.getSize(bar).height, 56);
      expect(Theme.of(tester.element(bar)).navigationBarTheme.backgroundColor, VeilPalette.light.canvas);
      // The hairline is painted over the opaque bar, not under it.
      final edgeBox = tester.widget<DecoratedBox>(find.ancestor(of: bar, matching: find.byType(DecoratedBox)).first);
      expect(edgeBox.position, DecorationPosition.foreground);
      final edge = edgeBox.decoration as BoxDecoration;
      expect((edge.border! as Border).top.width, 0.5);
      expect((edge.border! as Border).top.color, VeilPalette.light.stroke);
      for (final tab in find.byType(NavigationDestination).evaluate()) {
        final size = tester.getSize(find.byWidget(tab.widget));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      final label = tester.widget<Text>(find.text('Settings'));
      expect(label.style?.color ?? DefaultTextStyle.of(tester.element(find.text('Settings'))).style.color,
          VeilPalette.light.primaryStrong);
    });

    testWidgets('from 1024 wide is a NavigationRail with the bar\'s look, on its side', (tester) async {
      final router = GoRouter(
        initialLocation: '/contacts',
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
      tester.view.physicalSize = const Size(MainTabShell.railBreakpoint, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [unreadChatsProvider.overrideWith((ref) => 0)],
        child: MaterialApp.router(
          theme: VeilTheme.dark(fontFamily: layoutFontFamily),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await tester.pumpAndSettle();

      final rail = find.byType(NavigationRail);
      expect(rail, findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRailDestination, skipOffstage: false), findsNothing,
          reason: 'destinations are data, not widgets');
      expect(tester.widget<NavigationRail>(rail).selectedIndex, 1);
      expect(find.byIcon(Icons.people), findsOneWidget, reason: 'the active tab shows the filled glyph');
      expect(Theme.of(tester.element(rail)).splashFactory, NoSplash.splashFactory);
      final railTheme = Theme.of(tester.element(rail)).navigationRailTheme;
      expect(railTheme.backgroundColor, VeilPalette.dark.canvas);
      expect(railTheme.useIndicator, isFalse);
      expect(railTheme.labelType, NavigationRailLabelType.all);
      expect(railTheme.selectedLabelTextStyle?.color, VeilPalette.dark.primaryStrong);
      expect(railTheme.unselectedLabelTextStyle?.color, VeilPalette.dark.textMuted);
      // The page beside it starts where the rail ends, under a hairline
      // painted over the rail's edge.
      expect(tester.getRect(find.text('/contacts')).left, greaterThan(tester.getRect(rail).right));
      final edgeBox = tester.widget<DecoratedBox>(find.ancestor(of: rail, matching: find.byType(DecoratedBox)).first);
      expect(edgeBox.position, DecorationPosition.foreground);
      final edge = (edgeBox.decoration as BoxDecoration).border! as Border;
      expect((edge.right.width, edge.right.color), (0.5, VeilPalette.dark.stroke));

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('/settings'), findsOneWidget);
      expect(tester.widget<NavigationRail>(rail).selectedIndex, 2);
      expect(find.byType(InkSplash), findsNothing);
      // Each tab is a target of 44 or more.
      for (final tab in ['Chats', 'Contacts', 'Settings']) {
        final target = find.ancestor(of: find.text(tab), matching: find.byWidgetPredicate((w) => w is InkResponse)).first;
        expect(tester.getSize(target).width, greaterThanOrEqualTo(44), reason: tab);
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44), reason: tab);
      }
    });
  });
}

void _noop() {}

/// Pumps [widget] in a 390x844 phone view at 1x, so positions and widths
/// read in logical pixels.
Future<void> _pump(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
}

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
      home: child,
    );
  }
}
