import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/di/core_providers.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_opener.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_viewer_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/photo_image_provider.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger_providers.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';

import '../support/fake_attachment_opener.dart';
import '../support/media_fixtures.dart';
import '../support/scripted_media.dart';

// The photo viewer (D29) and Save (D30): a photo on black, zoom, drag down
// to close, a bar that comes and goes, and Save behind a dialog every time.

final AppLocalizations l10n = AppLocalizationsEn();
const _chat = 'conv-1';
const _pointer = AttachmentReference(
  attachmentId: '00000000-0000-4000-8000-000000000001',
  storageKey: '',
  contentType: 'image/jpeg',
  sizeBytes: 4096,
  sha256: 'digest',
  encryptedKey: 'key',
  nonce: 'nonce',
  algorithmHint: 'aes256gcm-v2',
);

void main() {
  late ScriptedMedia media;
  late FakeAttachmentOpener opener;
  late Directory root;
  late Uint8List photo;

  setUp(() {
    root = Directory.systemTemp.createTempSync('veil-viewer-');
    media = ScriptedMedia(openRoot: root);
    opener = FakeAttachmentOpener();
    photo = solidPng(width: 400, height: 300);
    media
      ..photos[MediaKey(_chat, _pointer)] = photo
      ..setStatus(_chat, _pointer, MediaState.ready);
    PaintingBinding.instance.imageCache.clear();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester, {String title = 'Selene'}) async {
    final messenger = ScriptedMediaMessenger(media);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        messengerControllerProvider.overrideWith((ref) => messenger),
        attachmentOpenerProvider.overrideWithValue(opener),
        wallClockProvider.overrideWithValue(() => DateTime(2026, 4, 7, 18)),
      ],
      child: MaterialApp(
        theme: VeilTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPhotoViewer(
                  context,
                  conversationId: _chat,
                  attachment: _pointer,
                  bytes: photo,
                  title: title,
                  sentAt: DateTime(2026, 4, 7, 9, 52),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // Decoding and copies run outside the test's fake clock.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  double scale(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byKey(const ValueKey('photo-viewer-zoom')))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  double barOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
          find.ancestor(of: find.byKey(const ValueKey('photo-viewer-save')), matching: find.byType(AnimatedOpacity)))
      .opacity;

  testWidgets('a photo on black, with who sent it and when, and Save', (tester) async {
    await open(tester);
    await drain(tester);
    expect(find.byType(PhotoViewerScreen), findsOneWidget);
    expect(find.text('Selene'), findsOneWidget);
    expect(find.text('Today at 9:52\u00A0AM'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-viewer-save')), findsOneWidget);
    expect(find.byTooltip(l10n.commonClose), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
  });

  // A tall photo, or a screenshot, reaches under the bar: whatever it shows
  // there, white on the band reads (4.5:1 for words, 3:1 for the glyphs),
  // judged over a white photo, the worst case.
  testWidgets('the bar is white on a flat band of black that runs up behind the status bar', (tester) async {
    tester.view.padding = FakeViewPadding(top: 24 * tester.view.devicePixelRatio);
    addTearDown(tester.view.reset);
    await open(tester);
    final bandFinder = find.byKey(const ValueKey('photo-viewer-bar-band'));
    final band = tester.widget<ColoredBox>(bandFinder);
    final rect = tester.getRect(bandFinder);
    expect(rect.top, 0);
    expect(rect.height, 24 + 52, reason: 'the band covers the status bar and the bar');
    expect(rect.width, tester.getSize(find.byType(PhotoViewerScreen)).width);
    expect(band.color.a, closeTo(PhotoViewerScreen.barBandOpacity, 0.01));
    expect((band.color.r, band.color.g, band.color.b), (0, 0, 0), reason: 'flat black, no gradient');

    final ground = Color.alphaBlend(band.color, Colors.white);
    double contrastOn(Color ink) {
      final a = Color.alphaBlend(ink, ground).computeLuminance();
      final b = ground.computeLuminance();
      return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
    }

    expect(contrastOn(tester.widget<Text>(find.text('Selene')).style!.color!), greaterThanOrEqualTo(4.5));
    expect(contrastOn(tester.widget<Text>(find.text('Today at 9:52\u00A0AM')).style!.color!),
        greaterThanOrEqualTo(4.5));
    for (final glyph in [Icons.close, Icons.download_outlined]) {
      expect(contrastOn(tester.widget<Icon>(find.byIcon(glyph)).color!), greaterThanOrEqualTo(3));
    }
  });

  testWidgets('the user\'s own photo is titled "You"', (tester) async {
    await open(tester, title: l10n.viewerSenderYou);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('pinch zooms up to 4x', (tester) async {
    await open(tester);
    final viewer = tester.widget<InteractiveViewer>(find.byKey(const ValueKey('photo-viewer-zoom')));
    expect(viewer.maxScale, PhotoViewerScreen.maxScale);
    expect(viewer.maxScale, 4);

    final center = tester.getCenter(find.byType(PhotoViewerScreen));
    final first = await tester.startGesture(center - const Offset(20, 0));
    final second = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(120, 0));
    await second.moveTo(center + const Offset(120, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(scale(tester), greaterThan(1.5));
    expect(scale(tester), lessThanOrEqualTo(4));
  });

  testWidgets('a double tap zooms to 2.5x where it landed, and another goes back', (tester) async {
    await open(tester);
    final center = tester.getCenter(find.byType(PhotoViewerScreen));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(PhotoViewerScreen.doubleTapScale, 0.01));

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(1, 0.01));
  });

  testWidgets('a tap hides the bar and another shows it', (tester) async {
    await open(tester);
    expect(barOpacity(tester), 1);
    await tester.tapAt(tester.getCenter(find.byType(PhotoViewerScreen)));
    // Past the double-tap window.
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(barOpacity(tester), 0);
    await tester.tapAt(tester.getCenter(find.byType(PhotoViewerScreen)));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(barOpacity(tester), 1);
  });

  testWidgets('dragged down far enough it closes; a short drag springs back', (tester) async {
    await open(tester);
    final center = tester.getCenter(find.byType(PhotoViewerScreen));
    await tester.timedDragFrom(center, const Offset(0, 60), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewerScreen), findsOneWidget, reason: 'a short drag closed it');

    await tester.timedDragFrom(center, const Offset(0, 200), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewerScreen), findsNothing);
  });

  testWidgets('the cross closes it', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip(l10n.commonClose));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewerScreen), findsNothing);
  });

  testWidgets('Save asks first, in plain words; Cancel saves nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-viewer-save')));
    await tester.pumpAndSettle();
    expect(find.text('Save to your phone?'), findsOneWidget);
    expect(find.text('Other apps, and any cloud you save it to, can open it.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save-cancel')));
    await drain(tester);
    expect(opener.saved, isEmpty);
    expect(media.copies, isEmpty, reason: 'a copy was made before the user agreed');
  });

  testWidgets('Save hands a copy named by when it was sent to the save screen, then deletes it', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-viewer-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-confirm')));
    await drain(tester);

    expect(opener.saved, hasLength(1));
    expect(opener.saved.single.bytes, photo);
    expect(opener.saved.single.as, startsWith('photo-20260407-095200'));
    expect(media.copies.single.$2, MediaCopyPurpose.save);
    expect(File(opener.saved.single.path).existsSync(), isFalse, reason: 'the copy outlived the save');
    // A toast shows on each scaffold, the viewer's and the chat's under it.
    expect(find.text('Saved'), findsWidgets);
  });

  testWidgets('a save that failed says so', (tester) async {
    opener.saveOutcome = SaveOutcome.failed;
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('photo-viewer-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-confirm')));
    await drain(tester);
    expect(find.text('Couldn\'t save. Try again.'), findsWidgets);
    expect(File(opener.saved.single.path).existsSync(), isFalse);
  });

  testWidgets('the photo is decoded for the screen, never past 4096 pixels', (tester) async {
    expect(PhotoViewerScreen.decodeEdge(1000), 2000);
    expect(PhotoViewerScreen.decodeEdge(2400), kViewerMaxEdge);
    expect(kViewerMaxEdge, 4096);

    tester.view
      ..physicalSize = const Size(2732, 2048)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await open(tester);
    final provider = tester.widget<Image>(find.byType(Image)).image as PhotoImageProvider;
    expect(provider.target, const PhotoDecodeTarget.viewer(4096));
  });
}
