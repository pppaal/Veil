import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// What the phone layout gate measures on one rendered screen, and how it
// renders it: the test fonts, a phone-sized view with its system insets,
// every error the framework reports while the screen is built and scrolled,
// and (only when asked) a PNG of what was on screen.
//
// Fonts. The app bundles no UI font: it draws the platform's own (SF on
// iOS, Roboto on Android), which a test process does not have, so text
// would render as the test font's boxes and nothing could be measured. The
// gate loads Roboto Regular, Medium and Bold from test/fonts (Apache-2.0,
// LICENSE.txt alongside; test files, not app assets) under three names:
// - `VeilTestSans` ([layoutFontFamily]), which the layout world passes to
//   VeilTheme so the gate's renders name a font explicitly whatever the
//   platform;
// - `Roboto`, the family the theme resolves on the test platform (Android)
//   when no family is passed, for the widget tests that build the theme
//   themselves;
// - `monospace`, which the safety number's digits ask for: Roboto stands
//   in (the SDK ships no Roboto Mono); with tabular figures its digits are
//   about as wide as a monospace's, where the test font's are far wider.
// Roboto is wider than SF, so the gate measures the worst case. The icon
// fonts (Material Icons, Cupertino Icons) are the app's own assets and are
// loaded from its font manifest, which holds nothing else.

/// Where the suite writes PNGs and its report. Empty unless the run passes
/// `--dart-define=SHOTS_DIR=<dir>`; without it nothing is written anywhere.
const String shotsDir = String.fromEnvironment('SHOTS_DIR');

bool get writesShots => shotsDir.isNotEmpty;

/// With --dart-define=SHOTS_PAGES=all a run that writes shots also writes
/// one PNG per screenful below the first (`<case>~2.png`, ...), for
/// reading a long screen to its end. Off by default: one PNG per case.
const bool _shootEveryPage = String.fromEnvironment('SHOTS_PAGES') == 'all';

const double _pixelRatio = 2;

/// A phone screen in logical pixels, with the system insets a phone of that
/// class reserves (status bar, home indicator). The insets are typical
/// values, not one device's exact numbers.
class PhoneSize {
  const PhoneSize(this.width, this.height, {required this.topInset, required this.bottomInset});

  final double width;
  final double height;
  final double topInset;
  final double bottomInset;

  String get label => '${width.toInt()}x${height.toInt()}';

  @override
  String toString() => label;
}

/// Compact Android, iPhone 12-15 and large Android.
const phoneSmall = PhoneSize(360, 640, topInset: 24, bottomInset: 0);
const phoneMedium = PhoneSize(390, 844, topInset: 47, bottomInset: 34);
const phoneLarge = PhoneSize(412, 915, topInset: 32, bottomInset: 24);
const phoneSizes = <PhoneSize>[phoneSmall, phoneMedium, phoneLarge];

/// The sizes of the wide cases: two desktop or landscape-tablet windows,
/// where the conversations shell shows its two panes (from 1120 px), and a
/// tablet held upright, which is too narrow for them and shows one screen
/// at a time like a phone.
const wideSmall = PhoneSize(1280, 800, topInset: 0, bottomInset: 0);
const wideLarge = PhoneSize(1440, 1000, topInset: 0, bottomInset: 0);
const tabletUpright = PhoneSize(1024, 1366, topInset: 24, bottomInset: 20);

/// The family the layout world passes to VeilTheme (see the file comment).
const String layoutFontFamily = 'VeilTestSans';

/// Where Debian and Ubuntu keep the emoji font, when it is installed.
const String _systemEmojiFont = '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf';

/// Where the test fonts are, from apps/mobile (where `flutter test` runs).
const String testFontsDir = 'test/fonts';

/// Loads the test fonts (see the file comment), so text is measured and
/// drawn with real glyphs instead of the test font's boxes, and the icon
/// fonts the app declares (the only fonts in its manifest), so icons are
/// drawn as glyphs. Call from setUpAll: inside testWidgets the fake clock
/// never completes the reads.
Future<void> loadTestFonts() async {
  final regular = _fontBytes('Roboto-Regular.ttf');
  final medium = _fontBytes('Roboto-Medium.ttf');
  final bold = _fontBytes('Roboto-Bold.ttf');
  for (final family in [layoutFontFamily, 'Roboto']) {
    await (FontLoader(family)
          ..addFont(Future.value(regular))
          ..addFont(Future.value(medium))
          ..addFont(Future.value(bold)))
        .load();
  }
  await (FontLoader('monospace')..addFont(Future.value(regular))).load();
  // Emoji (the reaction bar, the chips) from the machine's own emoji font
  // where it has one, so a render shows them rather than empty boxes. The
  // layout is measured the same either way: each emoji sits in a box of
  // its own fixed size.
  final emoji = File(_systemEmojiFont);
  if (emoji.existsSync()) {
    await (FontLoader('Noto Color Emoji')..addFont(Future.value(emoji.readAsBytesSync().buffer.asByteData()))).load();
  }

  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// [loadTestFonts] under the name the tests call it by.
Future<void> loadBundledFonts() => loadTestFonts();

ByteData _fontBytes(String name) {
  final file = File('$testFontsDir/$name');
  if (!file.existsSync()) {
    throw StateError('$name is not in $testFontsDir: run the tests from apps/mobile');
  }
  return file.readAsBytesSync().buffer.asByteData();
}

/// Makes the test view a phone of [size] at 2x. [keyboardHeight] opens the
/// software keyboard, which takes over the bottom inset as on a device.
/// [textScale] is the system's text size setting (1 is the default size).
void usePhoneView(WidgetTester tester, PhoneSize size, {double keyboardHeight = 0, double textScale = 1}) {
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final view = tester.view;
  view.devicePixelRatio = _pixelRatio;
  view.physicalSize = Size(size.width, size.height) * _pixelRatio;
  final keyboardOpen = keyboardHeight > 0;
  view.viewPadding = FakeViewPadding(top: size.topInset * _pixelRatio, bottom: size.bottomInset * _pixelRatio);
  view.padding = FakeViewPadding(
    top: size.topInset * _pixelRatio,
    bottom: keyboardOpen ? 0 : size.bottomInset * _pixelRatio,
  );
  view.viewInsets = FakeViewPadding(bottom: keyboardHeight * _pixelRatio);
  addTearDown(view.reset);
}

/// What can be wrong with one rendered case.
enum LayoutDefect {
  /// A RenderFlex (or other box) painted outside its bounds.
  overflow,

  /// Any other error while building, laying out or painting: unbounded
  /// constraints, a box that was never laid out, a build that threw.
  exception,

  /// The messages or conversations got less of the screen than the gate
  /// asks for.
  primaryContentSqueezed,

  /// Something to tap is smaller than 44x44, on a screen held to that
  /// (every screen but the ones exempted by name).
  smallTapTarget,

  /// The action of a chat's warning is missing, or not wholly on screen
  /// where a tap reaches it: cut off by the area it scrolls in, say.
  hiddenAction,

  /// The control a screen is for (its first input or primary button) is
  /// not on the first screenful.
  primaryActionBelowFold,
}

/// The defects of one case, with a line of evidence for each.
class LayoutFindings {
  final Map<LayoutDefect, List<String>> _evidence = {};

  /// Share of the screen height the primary content got, when measured.
  double? primaryShare;

  /// For the report of a run that writes shots only: the share of the
  /// screen height the screen's main scrolling list has, and tap targets
  /// under 48x48.
  double? mainListShare;
  final Set<String> smallTapTargets = {};

  void add(LayoutDefect defect, String evidence) {
    final lines = _evidence.putIfAbsent(defect, () => []);
    if (!lines.contains(evidence)) lines.add(evidence);
  }

  Set<LayoutDefect> get defects => _evidence.keys.toSet();

  bool get isClean => _evidence.isEmpty;

  List<String> evidenceFor(LayoutDefect defect) => _evidence[defect] ?? const [];

  String describe() => [
        for (final entry in _evidence.entries)
          for (final line in entry.value) '  ${entry.key.name}: $line',
      ].join('\n');

  Map<String, Object?> toJson() => {
        'defects': {for (final entry in _evidence.entries) entry.key.name: entry.value},
        if (primaryShare != null) 'primaryShare': double.parse(primaryShare!.toStringAsFixed(3)),
        if (mainListShare != null) 'mainListShare': double.parse(mainListShare!.toStringAsFixed(3)),
        if (smallTapTargets.isNotEmpty) 'smallTapTargets': smallTapTargets.toList(),
      };
}

/// Runs [body] with every framework error routed into [findings] instead of
/// failing the test at the first one. The test binding insists on finding
/// its own handler back when the test ends, so it is restored here.
Future<void> collectingLayoutErrors(LayoutFindings findings, Future<void> Function() body) async {
  final bindingHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final summary = _summarize(details);
    final overflowed = summary.contains('overflowed');
    findings.add(overflowed ? LayoutDefect.overflow : LayoutDefect.exception, summary);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = bindingHandler;
  }
}

final _creationLocation = RegExp(r'(\w+):file://\S*?/(lib/\S+\.dart:\d+)');

// "A RenderFlex overflowed by 96 pixels on the bottom. (Column, lib/src/…:42)"
String _summarize(FlutterErrorDetails details) {
  final headline = details.exceptionAsString().split('\n').first.trim();
  // The widget inspector adds "The relevant error-causing widget was" with
  // the place it was created; it is only in the rendered text.
  final match = _creationLocation.firstMatch(details.toString());
  final where = match == null ? '' : ' (${match.group(1)}, ${match.group(2)})';
  final library = details.library == null || headline.contains('overflowed') ? '' : ' [${details.library}]';
  return '$headline$where$library';
}

/// Lets a screen finish what it starts when opened: its first frames, the
/// microtask-driven loads of the fakes, and entry animations. A fixed
/// number of fixed steps, because several screens animate forever.
Future<void> pumpFrames(WidgetTester tester,
    {int frames = 8, Duration step = const Duration(milliseconds: 150)}) async {
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// The part of [box] that is on screen, in logical pixels.
Rect visibleRect(WidgetTester tester, RenderBox box) {
  final screen = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final rect = box.localToGlobal(Offset.zero) & box.size;
  return rect.overlaps(screen) ? rect.intersect(screen) : Rect.zero;
}

double screenHeight(WidgetTester tester) => tester.view.physicalSize.height / tester.view.devicePixelRatio;

/// What keeps a tap from reaching all of [box], or null when nothing does:
/// the whole of it is on screen above the keyboard, and a tap at its centre
/// and just inside the middle of each edge lands on it. A control that the
/// edge of a scrolling area cuts off fails this, which no layout error
/// reports: the part outside is simply not there to tap.
String? whyNotWhollyTappable(WidgetTester tester, RenderBox box) {
  final view = tester.view;
  final screen = view.physicalSize / view.devicePixelRatio;
  final aboveKeyboard =
      Rect.fromLTRB(0, 0, screen.width, screen.height - view.viewInsets.bottom / view.devicePixelRatio);
  final rect = box.localToGlobal(Offset.zero) & box.size;
  if (rect.isEmpty) return 'has no size';
  if (rect.left < aboveKeyboard.left ||
      rect.top < aboveKeyboard.top ||
      rect.right > aboveKeyboard.right ||
      rect.bottom > aboveKeyboard.bottom) {
    return 'reaches outside the screen at $rect';
  }
  final probes = {
    'centre': rect.center,
    'top edge': rect.topCenter.translate(0, 1),
    'bottom edge': rect.bottomCenter.translate(0, -1),
    'left edge': rect.centerLeft.translate(1, 0),
    'right edge': rect.centerRight.translate(-1, 0),
  };
  for (final probe in probes.entries) {
    final hit = tester.hitTestOnBinding(probe.value);
    if (!hit.path.any((entry) => entry.target == box)) {
      return 'takes no tap at its ${probe.key} (${probe.value}); it is at $rect';
    }
  }
  return null;
}

/// Scrolls the screen's main vertical list to its end one screenful at a
/// time, so that lazily built rows below the fold are laid out too and can
/// report their own overflows. [onPage] runs after each step.
Future<void> scrollToEnd(WidgetTester tester, {Future<void> Function(int page)? onPage}) async {
  final position = _mainVerticalPosition(tester);
  if (position == null) return;
  for (var page = 2; page <= 40; page++) {
    if (position.pixels >= position.maxScrollExtent - 0.5) break;
    final step = position.viewportDimension * 0.9;
    position.jumpTo((position.pixels + step).clamp(0.0, position.maxScrollExtent));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await onPage?.call(page);
  }
}

/// The share of the screen height the screen's main vertical list has, or
/// null for a screen that does not scroll.
double? mainListShare(WidgetTester tester) {
  final position = _mainVerticalPosition(tester);
  return position == null ? null : position.viewportDimension / screenHeight(tester);
}

// The tallest vertical scrollable on screen: the screen's own list, not a
// text field or a horizontal strip inside it.
ScrollPosition? _mainVerticalPosition(WidgetTester tester) {
  ScrollPosition? best;
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    final position = state.position;
    if (position.axis != Axis.vertical || !position.hasContentDimensions) continue;
    if (best == null || position.viewportDimension > best.viewportDimension) best = position;
  }
  return best;
}

/// Writes what is on screen to `<SHOTS_DIR>/<name>.png` at 2x.
Future<void> writeShot(WidgetTester tester, String name) async {
  final renderView = tester.binding.renderViews.first;
  final layer = renderView.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(renderView.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$shotsDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);
  });
}

bool get shootsEveryPage => writesShots && _shootEveryPage;

/// Tap targets on screen smaller than [minimum] logical pixels either way:
/// Android's 48 for the report, [minimumTapTarget] for the gate.
///
/// What takes a tap or a long press is read from the semantics tree, as the
/// framework's own tap target guideline reads it, with the same exceptions
/// (links, hidden nodes). That guideline also passes over every control
/// that touches any edge of the list it scrolls in, or of the screen, on
/// the grounds that it may be half scrolled out, which lets through each
/// button set flush left in a list and every control at a screen edge. Here
/// a control is passed over only when it reaches an edge of its list along
/// the way the list scrolls, where the list may have cut it. A control that
/// touches an edge of the screen is measured like any other. The one thing
/// left out there is a modal's scrim (the node that dismisses a sheet, a
/// menu or a dialog): it is whatever the modal leaves uncovered, not a
/// control with a size of its own.
Future<Set<String>> smallTapTargetsOnScreen(WidgetTester tester, {double minimum = 48}) async {
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    final view = tester.view;
    final screen = Offset.zero & view.physicalSize;
    final small = <String>{};

    void visit(SemanticsNode node) {
      node.visitChildren((child) {
        visit(child);
        return true;
      });
      if (node.isMergedIntoParent) return;
      final data = node.getSemanticsData();
      final takesTaps = data.hasAction(SemanticsAction.tap) || data.hasAction(SemanticsAction.longPress);
      if (!takesTaps || data.flagsCollection.isHidden || data.flagsCollection.isLink) return;
      if (data.hasAction(SemanticsAction.dismiss)) return;

      // The node's rectangle, carried up to the root: physical pixels.
      var rect = node.rect;
      for (SemanticsNode? current = node; current != null; current = current.parent) {
        final transform = current.transform;
        if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
        final list = current.parent;
        if (list == null || !list.flagsCollection.hasImplicitScrolling) continue;
        final scrolling = list.getSemanticsData();
        final vertical =
            scrolling.hasAction(SemanticsAction.scrollUp) || scrolling.hasAction(SemanticsAction.scrollDown);
        final horizontal =
            scrolling.hasAction(SemanticsAction.scrollLeft) || scrolling.hasAction(SemanticsAction.scrollRight);
        if (vertical && (rect.top <= list.rect.top + _edge || rect.bottom >= list.rect.bottom - _edge)) return;
        if (horizontal && (rect.left <= list.rect.left + _edge || rect.right >= list.rect.right - _edge)) return;
      }
      // What reaches past the screen is measured by the part that is on it:
      // that part is all there is to tap.
      if (!rect.overlaps(screen)) return;
      final size = rect.intersect(screen).size / view.devicePixelRatio;
      if (size.width < minimum - _edge || size.height < minimum - _edge) {
        final label = data.label.isEmpty ? (data.tooltip.isEmpty ? 'unlabelled' : data.tooltip) : data.label;
        small.add('Size(${size.width.toStringAsFixed(1)}, ${size.height.toStringAsFixed(1)}) ($label)');
      }
    }

    for (final renderView in tester.binding.renderViews) {
      final root = renderView.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null) visit(root);
    }
    return small;
  } finally {
    handle.dispose();
  }
}

/// The least a control may measure where the gate holds it: 44 logical
/// pixels each way, Apple's minimum, which Android's 48 also meets.
const double minimumTapTarget = 44;

// How close to an edge counts as reaching it, in physical pixels.
const double _edge = 0.01;

/// One line per case of a run that writes shots: `<SHOTS_DIR>/report.json`.
class LayoutReport {
  final List<Map<String, Object?>> _rows = [];

  void record({
    required String caseId,
    required String screen,
    required PhoneSize size,
    required String locale,
    required LayoutFindings findings,
    required bool knownFailure,
    bool light = false,
  }) {
    _rows.add({
      'case': caseId,
      'screen': screen,
      'size': size.label,
      'locale': locale,
      if (light) 'theme': 'light',
      'knownFailure': knownFailure,
      ...findings.toJson(),
    });
  }

  void write() {
    if (!writesShots || _rows.isEmpty) return;
    File('$shotsDir/report.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_rows), flush: true);
  }
}

/// Creates the shots directory once per run.
void prepareShotsDir() {
  if (writesShots) Directory(shotsDir).createSync(recursive: true);
}
