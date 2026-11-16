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
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/auth/presentation/choose_handle_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
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
// Emoji (the reaction in the chat) are Noto Color Emoji, Android's emoji
// font, read from the first of: --dart-define=EMOJI_FONT=<path>, the Debian
// and Ubuntu package fonts-noto-color-emoji, the copy in the Flutter SDK's
// engine sources. The theme names it as the fallback for what Roboto lacks,
// which is what Android does with its system fonts.
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

/// One screenshot: where the router opens, the account it opens with, what
/// to change in the seeded world first, what to do once the screen is open,
/// and the screen that must then be on it.
class _Shot {
  const _Shot(
    this.name, {
    required this.screen,
    required this.location,
    this.account = LayoutAccount.signedIn,
    this.extra,
    this.attention = const ChatAttention(),
    this.withGroup = false,
    this.transferStarted = false,
    this.prepare,
    this.settle,
  });

  final String name;
  final Type screen;
  final String location;
  final LayoutAccount account;
  final Object? extra;
  final ChatAttention attention;
  final bool withGroup;
  final bool transferStarted;
  final void Function(LayoutWorld world)? prepare;
  final Future<void> Function(WidgetTester tester)? settle;
}

// The shot list of store/appstore/screenshot-spec.md, section 4, in its
// order.
const _shots = <_Shot>[
  _Shot('01-choose-handle',
      screen: ChooseHandleScreen,
      location: '/choose-handle',
      account: LayoutAccount.signedOut,
      extra: selfDisplayName,
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
      settle: _reactWhileTyping),
  _Shot('04-move-to-a-new-phone',
      screen: DeviceTransferScreen, location: '/device-transfer', transferStarted: true),
  _Shot('05-app-lock',
      screen: AppLockScreen, location: '/lock', account: LayoutAccount.locked, settle: _typePin),
  _Shot('06-settings', screen: SettingsScreen, location: '/settings', settle: _showSecurityFooter),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LayoutIdentities identities;

  setUpAll(() async {
    await loadTestFonts();
    final emoji = File(_emojiFontPath()).readAsBytesSync();
    await (FontLoader(_emojiFamily)..addFont(Future.value(ByteData.sublistView(emoji)))).load();
    identities = await LayoutIdentities.generate();
    final screenshots = Directory('$_outDir/screenshots')..createSync(recursive: true);
    // A shot that was renamed or dropped must not stay behind.
    for (final old in screenshots.listSync().whereType<File>()) {
      if (old.path.endsWith('.png')) old.deleteSync();
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
        transferStarted: shot.transferStarted,
      );
      shot.prepare?.call(world);
      final router = GoRouter(
        initialLocation: shot.location,
        initialExtra: shot.extra,
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
          world.startLiveAttention();
          await tester.pump();
          await shot.settle?.call(tester);
          expect(find.byType(shot.screen), findsOneWidget, reason: '${shot.location} did not open its screen');
          await _write(tester, '$_outDir/screenshots/${shot.name}.png', _shotSize);
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

String _emojiFontPath() {
  const named = String.fromEnvironment('EMOJI_FONT');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (named.isNotEmpty) named,
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    if (flutterRoot != null) '$flutterRoot/engine/src/flutter/txt/third_party/fonts/NotoColorEmoji.ttf',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw StateError('No Noto Color Emoji font in ${candidates.join(', ')}: '
      'pass one with --dart-define=EMOJI_FONT=<path to NotoColorEmoji.ttf>');
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

// The handle typed and the field left, as it reads once the keyboard is
// put away.
Future<void> _typeHandle(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), selfHandle);
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFrames(tester, frames: 4);
}

// Three chats of the seed are there for the gate's sake and stay out of the
// listing: the last messages of two are a voice note and a photo, which the
// app cannot send, and the third has no message yet, listed last under a
// time of another day (the list gives times, not days), which reads as a
// mistake in a still.
const _chatsLeftOut = {'alexandra', 'omar', emptyChatPeerHandle};

void _leaveOutChats(LayoutWorld world) {
  for (final handle in _chatsLeftOut) {
    world.relay.conversations.remove('conv-$handle');
  }
}

Future<void> _expectChatsLeftOut(WidgetTester tester) async {
  expect(find.byType(ConversationRow), findsNWidgets(peerNames.length + 1 - _chatsLeftOut.length),
      reason: 'the group and every chat but the ones left out');
  for (final handle in _chatsLeftOut) {
    expect(find.text(peerNames[handle]!), findsNothing, reason: 'the chat with $handle is still listed');
  }
}

// A reaction on Sam's last message, given the way a user gives one, while
// Sam types the next.
Future<void> _reactWhileTyping(WidgetTester tester) async {
  final theirs = find.byWidgetPredicate((widget) => widget is MessageBubble && !widget.message.isMine);
  await tester.longPress(find.descendant(of: theirs.first, matching: find.byType(VeilBubble)));
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

// Scrolled to the Appearance group, so that the screenful runs from the
// settings a user changes to the Security group's footer, which says what
// the account rests on.
Future<void> _showSecurityFooter(WidgetTester tester) async {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final appearance = find.ancestor(of: find.text(l10n.settingsSectionAppearance), matching: find.byType(VeilGroup));
  await Scrollable.ensureVisible(tester.element(appearance));
  await pumpFrames(tester, frames: 2);
  final footer = find.textContaining(l10n.securityFooterNoRecovery);
  final list = tester.getRect(find.byType(Scrollable).first);
  expect(tester.getRect(footer).bottom, lessThanOrEqualTo(list.bottom), reason: 'the Security footer is cut off');
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
