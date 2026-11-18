import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_opener.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_viewer_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_attachment_views.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_file_card.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_photo.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';

import '../layout/support/media_receive_seed.dart';
import '../support/fake_attachment_opener.dart';
import '../support/media_fixtures.dart';
import 'phone_app.dart';

// Photos and files someone sent, on a phone: a photo shows in the chat by
// itself and opens in the viewer; a file waits for a tap, then opens in
// another app as its own type; on iOS an image or video the viewer cannot
// show goes to Save, never to Quick Look.

final AppLocalizations l10n = AppLocalizationsEn();
const _chat = '/chat/$chatConversationId';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  late FakeAttachmentOpener opener;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  setUp(() => opener = FakeAttachmentOpener());

  // Files, isolates and decodes run on real time only.
  Future<void> until(WidgetTester tester, bool Function() done, {String? reason}) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(done(), isTrue, reason: reason);
    await pumpFrames(tester, frames: 3);
  }

  final drawnPhoto = find.byWidgetPredicate((widget) => widget is RawImage && widget.image != null);

  Future<void> withChat(WidgetTester tester, Future<void> Function(LayoutWorld world) seed,
      Future<void> Function(LayoutWorld world) body) {
    return withPhoneApp(
      tester,
      identities,
      location: _chat,
      overrides: [attachmentOpenerProvider.overrideWithValue(opener)],
      afterSession: seed,
      body: body,
    );
  }

  testWidgets('a photo that arrives shows in the chat by itself, and a tap opens the viewer', (tester) async {
    await withChat(tester, (world) async {
      world.messenger.media.setInUse(true);
      await deliverAttachment(world,
          plaintext: landscapePhoto, contentType: 'image/jpeg', kind: MessageKind.image, hour: 10, minute: 16);
    }, (world) async {
      final inBubble = find.descendant(of: find.byType(MessagePhoto), matching: drawnPhoto);
      await until(tester, () => inBubble.evaluate().isNotEmpty, reason: 'the photo never showed');
      expect(world.relay.blobDownloads, hasLength(1), reason: 'fetched by itself, once');

      await tester.tap(inBubble);
      await pumpFrames(tester, frames: 4);
      expect(find.byType(PhotoViewerScreen), findsOneWidget);
      expect(find.descendant(of: find.byType(PhotoViewerScreen), matching: find.text('Sam Rivera')), findsOneWidget,
          reason: 'the viewer names who sent it');
      final inViewer = find.descendant(of: find.byType(PhotoViewerScreen), matching: drawnPhoto);
      await until(tester, () => inViewer.evaluate().isNotEmpty, reason: 'the viewer never drew the photo');

      await tester.tap(find.byTooltip(l10n.commonClose));
      await pumpFrames(tester, frames: 4);
      expect(find.byType(PhotoViewerScreen), findsNothing);
    });
  });

  testWidgets('a PDF waits for a tap, then opens in another app as a PDF, byte for byte', (tester) async {
    await withChat(
        tester,
        (world) => deliverAttachment(world,
            plaintext: leasePdf,
            contentType: 'application/octet-stream',
            kind: MessageKind.file,
            body: leaseFileName,
            hour: 10,
            minute: 16), (world) async {
      expect(world.relay.downloadTicketRequests, isEmpty, reason: 'a file never comes by itself');
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);

      await tester.tap(find.byType(MessageFileCard));
      await until(tester, () => find.byIcon(Icons.insert_drive_file_outlined).evaluate().isNotEmpty,
          reason: 'the file never came');
      expect(opener.opened, isEmpty, reason: 'fetching it opened it');

      await tester.tap(find.byType(MessageFileCard));
      await until(tester, () => opener.opened.isNotEmpty, reason: 'it never opened');
      expect(opener.opened.single.as, 'application/pdf', reason: 'the type comes from its name');
      expect(opener.opened.single.bytes, leasePdf);
    });
  });

  testWidgets('no app for a file: a toast says so', (tester) async {
    opener.openOutcome = OpenOutcome.noApp;
    await withChat(tester, (world) async {
      final lease = await deliverAttachment(world,
          plaintext: leasePdf,
          contentType: 'application/pdf',
          kind: MessageKind.file,
          body: leaseFileName,
          hour: 10,
          minute: 16);
      await fetchAndOpen(world, lease, photo: false);
    }, (world) async {
      await tester.tap(find.byType(MessageFileCard));
      await until(tester, () => find.text('No app found to open this file').evaluate().isNotEmpty,
          reason: 'no toast');
    });
  });

  testWidgets('a voice message still says this version cannot open it', (tester) async {
    await withChat(
        tester,
        (world) => deliverAttachment(world,
            plaintext: webVoiceNote, contentType: 'audio/webm', kind: MessageKind.voice, hour: 10, minute: 16),
        (world) async {
      expect(find.text(l10n.chatAttachmentCannotOpen), findsWidgets);
      expect(find.byType(MessageAttachmentCard), findsWidgets);
      expect(find.byType(MessageFileCard), findsNothing);
      expect(world.relay.downloadTicketRequests, isEmpty);
    });
  });

  group('on iOS', () {
    // Quick Look would offer to save an image or a video to Photos, which
    // the app has no permission for: Save asks first instead.
    for (final (label, name, bytes) in [
      ('a HEIC photo', 'IMG_2041.heic', heicHead()),
      ('an MP4 video', 'walkthrough.mp4', mp4Head()),
    ]) {
      testWidgets('$label sent as a file never reaches another app: Save asks instead', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await withChat(tester, (world) async {
            final file = await deliverAttachment(world,
                plaintext: bytes, contentType: 'application/octet-stream', kind: MessageKind.file, body: name,
                hour: 10, minute: 16);
            await fetchAndOpen(world, file, photo: false);
          }, (world) async {
            await tester.tap(find.byType(MessageFileCard));
            await until(tester, () => find.text(l10n.chatSaveTitle).evaluate().isNotEmpty,
                reason: 'the Save dialog never showed');
            expect(opener.opened, isEmpty);
            await tester.tap(find.byKey(const ValueKey('save-cancel')));
            await pumpFrames(tester, frames: 3);
            expect(opener.saved, isEmpty, reason: 'saved without the user agreeing');
          });
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('a PNG sent as a file opens in the viewer', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await withChat(tester, (world) async {
          final file = await deliverAttachment(world,
              plaintext: solidPng(width: 300, height: 200),
              contentType: 'image/png',
              kind: MessageKind.file,
              body: 'floor plan.png',
              hour: 10,
              minute: 16);
          await fetchAndOpen(world, file, photo: false);
        }, (world) async {
          await tester.tap(find.byType(MessageFileCard));
          await until(tester, () => find.byType(PhotoViewerScreen).evaluate().isNotEmpty,
              reason: 'the viewer never opened');
          expect(opener.opened, isEmpty);
          await tester.tap(find.byTooltip(l10n.commonClose));
          await pumpFrames(tester, frames: 4);
        });
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
