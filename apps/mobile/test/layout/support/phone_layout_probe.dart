import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// What the phone layout gate measures on one rendered screen, and how it
// renders it: the bundled fonts, a phone-sized view with its system insets,
// every error the framework reports while the screen is built and scrolled,
// and (only when asked) a PNG of what was on screen.

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

/// Loads every font the app bundles (Pretendard, the icon fonts), so text is
/// measured and drawn with real glyphs instead of the test font's boxes.
/// Call from setUpAll: inside testWidgets the fake clock never completes the
/// asset reads.
///
/// The platform's own `monospace` family (the safety number's digits ask for
/// it) does not exist in a test process either. Pretendard stands in for
/// it: with the tabular figures those digits also ask for, its digits are
/// about as wide as a monospace's, where the test font's are far wider.
Future<void> loadBundledFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    final assets = [
      for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) font['asset'] as String,
    ];
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
    if (family == 'Pretendard') {
      await (FontLoader('monospace')..addFont(rootBundle.load(assets.first))).load();
    }
  }
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

  /// Something to tap is smaller than 44x44, on a screen held to that.
  smallTapTarget,
}

/// The defects of one case, with a line of evidence for each.
class LayoutFindings {
  final Map<LayoutDefect, List<String>> _evidence = {};

  /// Share of the screen height the primary content got, when measured.
  double? primaryShare;

  /// For the report of a run that writes shots only: the share of the
  /// screen height the screen's main scrolling list has, tap targets under
  /// 48x48, and texts in the language the run is not in.
  double? mainListShare;
  final Set<String> smallTapTargets = {};
  final Set<String> otherLanguageTexts = {};

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
        if (otherLanguageTexts.isNotEmpty) 'otherLanguageTexts': otherLanguageTexts.toList(),
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
Future<void> pumpFrames(WidgetTester tester, {int frames = 8, Duration step = const Duration(milliseconds: 150)}) async {
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

final _hangul = RegExp(r'[\u1100-\u11FF\u3130-\u318F\uAC00-\uD7AF]');
final _latinWord = RegExp(r'[A-Za-z]{3,}');

/// Texts on screen in the language the run is not in: in a Korean run,
/// texts with Latin words and no Hangul; in an English run, texts with
/// Hangul. Names, handles and seeded message bodies show up too; the
/// report lists them all and a person tells them apart.
Set<String> otherLanguageTextsOnScreen(WidgetTester tester, String locale) {
  bool foreign(String text) => locale == 'ko'
      ? _latinWord.hasMatch(text) && !_hangul.hasMatch(text)
      : _hangul.hasMatch(text);
  final texts = <String>{
    for (final element in find.byType(RichText).evaluate())
      (element.widget as RichText).text.toPlainText().trim(),
    for (final element in find.byType(EditableText).evaluate())
      (element.widget as EditableText).controller.text.trim(),
  };
  return {
    for (final text in texts)
      if (foreign(text)) text.length > 80 ? '${text.substring(0, 80)}…' : text,
  };
}

/// Tap targets on screen smaller than [guideline] asks, as the framework's
/// own accessibility check reports them: Android's 48x48 for the report,
/// [minimumTapTarget] for the screens the gate holds to it.
Future<Set<String>> smallTapTargetsOnScreen(
  WidgetTester tester, {
  AccessibilityGuideline guideline = androidTapTargetGuideline,
}) async {
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    final evaluation = await guideline.evaluate(tester);
    if (evaluation.passed) return const {};
    return {
      for (final line in (evaluation.reason ?? '').split('\n'))
        if (_tapTargetLine.firstMatch(line) case final match?)
          '${match.group(2)} (${match.group(1) ?? 'unlabelled'})',
    };
  } finally {
    handle.dispose();
  }
}

/// The least a control may measure on the screens the gate holds to it: 44
/// logical pixels each way, Apple's minimum, which Android's 48 also meets.
const AccessibilityGuideline minimumTapTarget = iOSTapTargetGuideline;

final _tapTargetLine = RegExp(r'(?:label: "([^"]*)".*)?but found (Size\([\d., ]+\))');

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
  }) {
    _rows.add({
      'case': caseId,
      'screen': screen,
      'size': size.label,
      'locale': locale,
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
