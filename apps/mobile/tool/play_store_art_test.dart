import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/auth/presentation/choose_handle_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/reaction_chips_row.dart';
import 'package:veil_mobile/src/features/chat/presentation/typing_indicator.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_screen.dart';
import 'package:veil_mobile/src/features/reactions/presentation/reaction_picker_widget.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../test/layout/support/layout_seed.dart';
import '../test/layout/support/layout_world.dart';
import '../test/layout/support/phone_layout_probe.dart';
import '../test/support/fake_relay.dart';

// Draws the Google Play listing art from the app's real screens:
// - store/play/screenshots/NN-<screen>.png, the phone screenshots, each
//   exactly 1080 x 1920;
// - store/play/feature-graphic.png, 1024 x 500: the app icon and the name.
//
// Run from apps/mobile. It is a test so that it can build the app, and it
// sits under tool/ so that the normal suite does not run it:
//
//   flutter test tool/play_store_art_test.dart
//
// Each screenshot opens a screen the way the layout gate does (the real
// route table over the fake relay and the seeded account of
// test/layout/support, so the names and messages are the gate's: Sam Rivera,
// Priya Nair and the others), in the light theme, on a phone 1080 x 1920
// pixels at Android's 420 dpi density (2.625, a Pixel's), with the 24 dp
// status bar left empty. Nothing is drawn around a screen: no caption, frame
// or device.
//
// The text is Roboto, which Android draws: the theme is the production one
// (no font family named), which on the test platform (Android) resolves to
// `Roboto`, and loadTestFonts loads Roboto from test/fonts under that name.
// Those are Roboto Regular, Medium and Bold, so the theme's w600 styles
// (titles, names, button labels) are drawn in Bold, a step heavier than the
// variable Roboto of Android 12 and later. A shot may draw no text in
// `monospace`, which this tool has no font for (_expectNoMonospace).
// Emoji (the reaction in the chat) are Noto Color Emoji, Android's emoji
// font, read from the first of: --dart-define=EMOJI_FONT=<path>, the copy in
// the Flutter SDK's engine sources, the Debian and Ubuntu package
// fonts-noto-color-emoji (see _emojiFontPath). The theme names it as the
// fallback for what Roboto lacks, which is what Android does with its
// system fonts.
//
// A still shows a screenful as it is cut, so no list may cut through a line
// of text or a bubble at its top or bottom edge (_expectNothingCut): each
// shot chooses what it shows and where it scrolls so that nothing does.
//
// Play wants PNGs without an alpha channel, so both are written as RGB.
// The iPhone set is not drawn here: iOS shows SF Pro, which a test cannot
// render, so it is captured on a simulator (store/appstore/screenshot-spec.md).

/// Where the art goes, from apps/mobile.
const String _outDir = String.fromEnvironment('PLAY_ART_DIR', defaultValue: '../../store/play');

/// The phone of the screenshots: 1080 x 1920 pixels at 2.625, which is
/// 411 x 731 dp. Narrower phones are in the layout gate; at 360 dp the
/// chat's bar has room for "Sam Rive…" only.
const _shotSize = (1080, 1920);
const double _pixelRatio = 2.625;
const double _statusBar = 24;
const _featureGraphicSize = (1024, 500);

const _emojiFamily = 'NotoColorEmoji';

/// One screenshot: where the router opens (and the screen it is pushed
/// from, if the app pushes it), the account it opens with, what to change in
/// the seeded relay before the session loads it, what to do once the screen
/// is open, and the screen that must then be on it.
class _Shot {
  const _Shot(
    this.name, {
    required this.screen,
    required this.location,
    this.from,
    this.account = LayoutAccount.signedIn,
    this.attention = const ChatAttention(),
    this.withGroup = false,
    this.prepare,
    this.settle,
  });

  final String name;
  final Type screen;
  final String location;

  /// Where the app pushes [location] from, so its bar shows the back arrow
  /// it has on a phone. Null for a screen the app goes to (Choose a handle)
  /// or a tab.
  final String? from;
  final LayoutAccount account;
  final ChatAttention attention;
  final bool withGroup;
  final void Function(FakeRelay relay)? prepare;
  final Future<void> Function(WidgetTester tester)? settle;
}

// The shot list of store/appstore/screenshot-spec.md, section 4, in its
// order.
const _shots = <_Shot>[
  _Shot('01-choose-handle',
      screen: ChooseHandleScreen,
      location: '/choose-handle',
      account: LayoutAccount.signedOut,
      settle: _typeHandle),
  _Shot('02-chats',
      screen: ConversationListScreen,
      location: '/conversations',
      withGroup: true,
      prepare: _leaveOutChats,
      settle: _expectChatsLeftOut),
  _Shot('03-chat',
      screen: ChatRoomScreen,
      location: '/chat/$chatConversationId',
      attention: ChatAttention(peerTyping: true),
      prepare: _leaveOutChatLines,
      settle: _reactWhileTyping),
  // The old phone before it asks for a code: how a move goes, and the
  // button that starts it. Once asked, the screen shows the code itself, a
  // long string in `monospace` (the session and its token), which is no
  // picture for a listing.
  _Shot('04-move-to-a-new-phone', screen: DeviceTransferScreen, location: '/device-transfer', from: '/settings'),
  _Shot('05-app-lock',
      screen: AppLockScreen, location: '/lock', account: LayoutAccount.locked, settle: _typePin),
  _Shot('06-settings', screen: SettingsScreen, location: '/settings', settle: _settingsAsOpened),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LayoutIdentities identities;
  final screenshots = Directory('$_outDir/screenshots');
  // The shots this run wrote and checked.
  final drawn = <String>{};

  setUpAll(() async {
    await loadTestFonts();
    final emoji = File(_emojiFontPath()).readAsBytesSync();
    await (FontLoader(_emojiFamily)..addFont(Future.value(ByteData.sublistView(emoji)))).load();
    identities = await LayoutIdentities.generate();
    screenshots.createSync(recursive: true);
  });

  // A shot that was renamed or dropped must not stay behind. Only a run
  // that drew every shot clears the rest away: one filtered with
  // --plain-name, or one where a shot failed, leaves the folder as it was
  // apart from the files it wrote.
  tearDownAll(() {
    if (!drawn.containsAll(_shots.map((shot) => shot.name))) return;
    for (final file in screenshots.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.endsWith('.png') && !drawn.contains(name.substring(0, name.length - 4))) file.deleteSync();
    }
  });

  test('the shot list fits what Play takes', () {
    expect(_shots.length, inInclusiveRange(2, 8));
    expect(_shots.map((shot) => shot.name).toSet(), hasLength(_shots.length));
  });

  for (final shot in _shots) {
    testWidgets(shot.name, (tester) async {
      final findings = LayoutFindings();
      final world = await LayoutWorld.create(
        identities: identities,
        account: shot.account,
        locale: 'en',
        attention: shot.attention,
        withGroup: shot.withGroup,
        beforeSession: shot.prepare,
      );
      final from = shot.from;
      final router = GoRouter(
        initialLocation: from ?? shot.location,
        routes: world.container.read(appRoutesProvider),
      );
      _usePhone(tester);
      // A test draws every shadow as a solid block; a screenshot gets the
      // real ones, and the binding wants its setting back.
      debugDisableShadows = false;
      try {
        await collectingLayoutErrors(findings, () async {
          await tester.pumpWidget(_app(world.container, router));
          await pumpFrames(tester);
          if (from != null) {
            unawaited(router.push(shot.location));
            await pumpFrames(tester);
          }
          world.startLiveAttention();
          await tester.pump();
          await shot.settle?.call(tester);
          expect(find.byType(shot.screen), findsOneWidget, reason: '${shot.location} did not open its screen');
          _expectNothingCut(tester);
          _expectNoMonospace(tester);
          await _write(tester, '${screenshots.path}/${shot.name}.png', _shotSize);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        world.dispose();
        debugDisableShadows = true;
      }
      expect(findings.isClean, isTrue, reason: '${shot.name} did not render cleanly:\n${findings.describe()}');
      drawn.add(shot.name);
    });
  }

  testWidgets('feature graphic', (tester) async {
    final view = tester.view;
    view.devicePixelRatio = 2;
    view.physicalSize = Size(_featureGraphicSize.$1.toDouble(), _featureGraphicSize.$2.toDouble());
    addTearDown(view.reset);

    // The launcher icon itself, which tool/brand.dart draws.
    final icon = MemoryImage(File('assets/branding/app_icon.png').readAsBytesSync());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => precacheImage(icon, tester.element(find.byType(SizedBox))));
    await tester.pumpWidget(_FeatureGraphic(icon: icon));
    await tester.pump();
    await _write(tester, '$_outDir/feature-graphic.png', _featureGraphicSize);
  });
}

/// The emoji font: the one named with --dart-define=EMOJI_FONT, else the
/// copy in the Flutter SDK, which comes with the SDK version CI pins and so
/// is the same font on every machine, else the Debian and Ubuntu package
/// fonts-noto-color-emoji, whose version varies with the system.
String _emojiFontPath() {
  const named = String.fromEnvironment('EMOJI_FONT');
  const inSdk = 'engine/src/flutter/txt/third_party/fonts/NotoColorEmoji.ttf';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (named.isNotEmpty) named,
    if (flutterRoot != null) '$flutterRoot/$inSdk',
    if (_sdkOfTester() case final sdk?) '$sdk/$inSdk',
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw StateError('No Noto Color Emoji font in ${candidates.join(', ')}: '
      'pass one with --dart-define=EMOJI_FONT=<path to NotoColorEmoji.ttf>');
}

/// The Flutter SDK that runs this test, from where its test runner sits:
/// `<sdk>/bin/cache/artifacts/engine/<platform>/flutter_tester`.
String? _sdkOfTester() {
  final segments = File(Platform.resolvedExecutable).absolute.uri.pathSegments;
  final cache = segments.lastIndexOf('cache');
  if (cache < 2 || segments[cache - 1] != 'bin') return null;
  return Uri(scheme: 'file', pathSegments: segments.take(cache - 1)).toFilePath();
}

/// The app as a phone runs it: the light theme with the production font
/// (none named) and Android's emoji fallback, over the layout world's
/// providers and route table.
Widget _app(ProviderContainer container, GoRouter router) {
  final theme = VeilTheme.light();
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      title: 'Veil',
      theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamilyFallback: const [_emojiFamily])),
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void _usePhone(WidgetTester tester) {
  final view = tester.view;
  view.devicePixelRatio = _pixelRatio;
  view.physicalSize = Size(_shotSize.$1.toDouble(), _shotSize.$2.toDouble());
  view.viewPadding = const FakeViewPadding(top: _statusBar * _pixelRatio);
  view.padding = const FakeViewPadding(top: _statusBar * _pixelRatio);
  addTearDown(view.reset);
}

/// Writes what is on screen to [path] as an RGB PNG (no alpha channel),
/// and checks it is [size] pixels.
Future<void> _write(WidgetTester tester, String path, (int, int) size) async {
  final renderView = tester.binding.renderViews.first;
  final layer = renderView.debugLayer! as OffsetLayer;
  final captured = await tester.runAsync(() async {
    final image = await layer.toImage(renderView.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width, height = image.height;
    image.dispose();
    return (bytes!, width, height);
  });
  final (bytes, width, height) = captured!;
  expect((width, height), size, reason: path);
  final rgb = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: bytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  ).convert(numChannels: 3);
  final png = img.encodePng(rgb, level: 9);
  File(path).writeAsBytesSync(png, flush: true);

  final written = img.decodePng(png)!;
  expect((written.width, written.height, written.numChannels), (size.$1, size.$2, 3), reason: path);
}

/// Fails when the edge of a list that scrolls up and down cuts through a
/// line of text or a chat bubble: a still shows the screenful as it is
/// cut, and half a line or half a bubble at the top or the bottom of it
/// reads as a mistake. Whatever is in such a list is either whole on the
/// screen or not on it at all.
void _expectNothingCut(WidgetTester tester) {
  final cut = <String>[];
  for (final element in find.byType(Scrollable).evaluate()) {
    final scrollable = (element as StatefulElement).state as ScrollableState;
    if (axisDirectionToAxis(scrollable.axisDirection) != Axis.vertical) continue;
    final viewport = _globalRect(element.renderObject! as RenderBox);
    // Only an edge with more of the list beyond it cuts what crosses it:
    // a list that fits is drawn whole, and a field's floating label may sit
    // above its top. A reversed list (the chat) starts at its bottom.
    final position = scrollable.position;
    final down = scrollable.axisDirection == AxisDirection.down;
    final moreAbove = (down ? position.extentBefore : position.extentAfter) > 0;
    final moreBelow = (down ? position.extentAfter : position.extentBefore) > 0;
    final pieces = find.descendant(
      of: find.byElementPredicate((candidate) => candidate == element),
      matching: find.byWidgetPredicate((widget) => widget is RichText || widget is VeilBubble),
    );
    for (final piece in pieces.evaluate()) {
      final box = piece.renderObject;
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = _globalRect(box);
      final cutAtTop = moreAbove && rect.top < viewport.top - 0.5 && rect.bottom > viewport.top;
      final cutAtBottom = moreBelow && rect.top < viewport.bottom && rect.bottom > viewport.bottom + 0.5;
      if (cutAtTop || cutAtBottom) {
        final widget = piece.widget;
        cut.add(widget is RichText ? '"${widget.text.toPlainText()}"' : 'a bubble at ${rect.top.round()}');
      }
    }
  }
  expect(cut, isEmpty, reason: 'the edge of a list cuts through ${cut.join(', ')}');
}

/// Where [box] is drawn on the screen, through any transform above it (a
/// floating label is laid out at full size and scaled down).
Rect _globalRect(RenderBox box) => MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

/// Fails when the screen draws text in the `monospace` family. Android
/// draws that in its own monospace font; a test has none, and the layout
/// fonts put Roboto under that name, so a shot would show a field the way
/// no phone does.
void _expectNoMonospace(WidgetTester tester) {
  final monospace = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final text = (element.widget as RichText).text;
    text.visitChildren((span) {
      if (span is TextSpan && span.style?.fontFamily == 'monospace') monospace.add(text.toPlainText());
      return true;
    });
  }
  for (final element in find.byType(EditableText).evaluate()) {
    final field = element.widget as EditableText;
    if (field.style.fontFamily == 'monospace') monospace.add(field.controller.text);
  }
  expect(monospace, isEmpty, reason: 'drawn in monospace, which this tool cannot draw as Android does: $monospace');
}

// The handle typed and the field left, as it reads once the keyboard is
// put away.
Future<void> _typeHandle(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), selfHandle);
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFrames(tester, frames: 4);
}

// Three chats of the seed are there for the gate's sake and stay out of the
// listing: the last messages of two are a voice message and a photo, which
// the app cannot send, and the third has no message yet.
const _chatsLeftOut = {'alexandra', 'omar', emptyChatPeerHandle};

void _leaveOutChats(FakeRelay relay) {
  for (final handle in _chatsLeftOut) {
    relay.conversations.remove('conv-$handle');
  }
}

Future<void> _expectChatsLeftOut(WidgetTester tester) async {
  expect(find.byType(ConversationRow), findsNWidgets(peerNames.length + 1 - _chatsLeftOut.length),
      reason: 'the group and every chat but the ones left out');
  for (final handle in _chatsLeftOut) {
    expect(find.text(peerNames[handle]!), findsNothing, reason: 'the chat with $handle is still listed');
  }
}

// The seed's chat holds more than one screen does. The listing keeps the
// morning from Sam's message after the file on: his two short messages, the
// user's two answers (the second disappearing) and Sam's last word. It
// leaves out the evening before (the long message and the long link of the
// gate's history case), his first message of the morning and the user's
// answer to it, and the PDF the user sent, which the app cannot send. What
// is left fits on the screen whole, which _expectNothingCut holds it to.
void _leaveOutChatLines(FakeRelay relay) {
  final history = relay.conversations[chatConversationId]!.messages;
  final file = history.indexWhere((message) => message['attachment'] != null);
  expect(file, isNot(-1), reason: 'the seed chat no longer holds the attachment the listing starts after');
  final kept = history.sublist(file + 1);
  expect(kept.first['senderDeviceId'], 'dev-$peerHandle', reason: "the message after the attachment is no longer Sam's");
  expect(kept.where((message) => message['expiresAt'] != null), hasLength(1),
      reason: 'the kept lines no longer hold the disappearing message');
  expect(kept.where((message) => message['messageType'] == MessageKind.system.name), isEmpty,
      reason: 'the kept lines hold a notice');
  history
    ..clear()
    ..addAll(kept);
}

// The message of Sam's the user reacts to: the news of the morning.
const _reactedTo = 'they moved move-in to the 14th';

// A thumbs-up on Sam's news, given the way a user gives one, while Sam types
// the next message.
Future<void> _reactWhileTyping(WidgetTester tester) async {
  final news = find.ancestor(of: find.text(_reactedTo), matching: find.byType(VeilBubble));
  await tester.longPress(news);
  await pumpFrames(tester, frames: 4);
  await tester.tap(find.descendant(of: find.byType(ReactionPickerWidget), matching: find.text('\u{1F44D}')));
  await pumpFrames(tester, frames: 6);
  expect(find.byType(ReactionChipsRow), findsOneWidget, reason: 'the reaction did not show under the message');
  expect(find.byType(TypingIndicator), findsOneWidget, reason: 'the typing indicator is not on screen');
}

// A PIN typed in (six digits, the shortest the screen takes), so the
// button reads as it does just before the tap.
Future<void> _typePin(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '258014');
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFrames(tester, frames: 4);
}

// The top of Settings as it opens: the profile row and the groups under
// it. If a line sits across the bottom edge, the list moves up just far
// enough for that line to be whole, so the still cuts through nothing.
Future<void> _settingsAsOpened(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  final list = tester.getRect(scrollable);
  var overhang = 0.0;
  for (final text in find.descendant(of: scrollable, matching: find.byType(RichText)).evaluate()) {
    final rect = _globalRect(text.renderObject! as RenderBox);
    if (rect.top < list.bottom && rect.bottom > list.bottom && rect.bottom - list.bottom > overhang) {
      overhang = rect.bottom - list.bottom;
    }
  }
  if (overhang == 0) return;
  tester.state<ScrollableState>(scrollable).position.jumpTo(overhang);
  await pumpFrames(tester, frames: 2);
}

/// The app icon and the name, on white.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.icon});

  final ImageProvider icon;

  @override
  Widget build(BuildContext context) {
    const palette = VeilPalette.light;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: palette.canvas,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rounded as Play rounds the icon on the listing.
              ClipRRect(
                borderRadius: BorderRadius.circular(80 * 0.2),
                child: Image(image: icon, width: 80, height: 80, filterQuality: FilterQuality.high),
              ),
              const SizedBox(width: 20),
              Text(
                'Veil',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 56,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: palette.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
