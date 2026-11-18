import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/app/veil_app.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/notifications/local_notification_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_opener.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_viewer_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_attachment_views.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_file_card.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_photo.dart';
import 'package:veil_mobile/src/features/chat/presentation/photo_image_provider.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';

import '../layout/support/media_receive_seed.dart';
import '../support/fake_attachment_opener.dart';
import '../support/fake_platform_security.dart';
import '../support/media_fixtures.dart';
import 'phone_app.dart';

// Photos and files someone sent, on a phone: a photo shows in the chat by
// itself and opens in the viewer; a file waits for a tap, then opens in
// another app as its own type; on iOS an image or video the viewer cannot
// show goes to Save, never to Quick Look.

final AppLocalizations l10n = AppLocalizationsEn();
const _chat = '/chat/$chatConversationId';

// The file Sam sends in each test: the seeded chat also holds the lease the
// user sent this morning, drawn as a file card too.
final Finder _receivedFile = find.byWidgetPredicate((widget) => widget is MessageFileCard && !widget.message.isMine);

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

  testWidgets('a PDF waits for a tap, which fetches it and opens it in another app as a PDF, byte for byte',
      (tester) async {
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
      expect(find.descendant(of: _receivedFile, matching: find.byIcon(Icons.download_outlined)), findsOneWidget);

      // One tap (D28): it is fetched, then opened.
      await tester.tap(_receivedFile);
      await until(tester, () => opener.opened.isNotEmpty, reason: 'one tap did not fetch and open it');
      expect(world.relay.blobDownloads, hasLength(1));
      expect(opener.opened.single.as, 'application/pdf', reason: 'the type comes from its name');
      expect(opener.opened.single.bytes, leasePdf);
      expect(find.descendant(of: _receivedFile, matching: find.byIcon(Icons.insert_drive_file_outlined)), findsOneWidget);
    });
  });

  // The real router, so the lock replaces the chat with the lock screen as
  // it does on a phone.
  testWidgets('the app locks while a file is decrypted for Open: nothing reaches another app', (tester) async {
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      overrides: [attachmentOpenerProvider.overrideWithValue(opener)],
    );
    try {
      final lease = await deliverAttachment(world,
          plaintext: leasePdf,
          contentType: 'application/pdf',
          kind: MessageKind.file,
          body: leaseFileName,
          hour: 10,
          minute: 16);
      await fetchAndOpen(world, lease, photo: false);
      final router = world.container.read(appRouterProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: world.container,
        child: MaterialApp.router(
          theme: VeilTheme.dark(fontFamily: layoutFontFamily),
          locale: const Locale('en'),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ));
      await pumpFrames(tester);
      unawaited(router.push(_chat));
      await pumpFrames(tester);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      await until(
          tester,
          () => find
              .descendant(of: _receivedFile, matching: find.byIcon(Icons.insert_drive_file_outlined))
              .evaluate()
              .isNotEmpty,
          reason: 'the file is not ready');

      await tester.tap(_receivedFile);
      await tester.pump();
      // Home on Android (opening a file gets no grace) while it decrypts.
      world.container.read(appSessionProvider.notifier).lock();
      await pumpFrames(tester, frames: 6);
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(world.container.read(appSessionProvider).locked, isTrue);
      expect(opener.opened, isEmpty, reason: 'a decrypted file was handed to another app while Veil is locked');
      expect(world.messenger.media.cleanup.copies, isEmpty, reason: 'a copy made across the lock was left behind');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });

  // D36, through VeilApp, which empties the decrypted bytes and the image
  // cache on lock before the router takes the chat and the viewer down.
  for (final viewer in [true, false]) {
    testWidgets('a lock ${viewer ? 'with the viewer up' : 'over the chat'} leaves no decoded photo behind the lock screen',
        (tester) async {
      usePhoneView(tester, phoneSmall);
      final platform = RecordingPlatformSecurity();
      addTearDown(platform.close);
      final world = await LayoutWorld.create(
        identities: identities,
        account: LayoutAccount.signedIn,
        locale: 'en',
        overrides: [
          attachmentOpenerProvider.overrideWithValue(opener),
          platformSecurityServiceProvider.overrideWithValue(platform),
          localNotificationServiceProvider.overrideWithValue(_QuietNotifications()),
        ],
      );
      try {
        await deliverAttachment(world,
            plaintext: landscapePhoto, contentType: 'image/jpeg', kind: MessageKind.image, hour: 10, minute: 16);
        final router = world.container.read(appRouterProvider);
        await tester.pumpWidget(UncontrolledProviderScope(container: world.container, child: const VeilApp()));
        await pumpFrames(tester);
        unawaited(router.push(_chat));
        await pumpFrames(tester);
        expect(find.byType(ChatRoomScreen), findsOneWidget);
        final inBubble = find.descendant(of: find.byType(MessagePhoto), matching: drawnPhoto);
        await until(tester, () => inBubble.evaluate().isNotEmpty, reason: 'the photo never showed');
        if (viewer) {
          await tester.tap(inBubble);
          await pumpFrames(tester, frames: 4);
          final inViewer = find.descendant(of: find.byType(PhotoViewerScreen), matching: drawnPhoto);
          await until(tester, () => inViewer.evaluate().isNotEmpty, reason: 'the viewer never drew the photo');
        }
        final decodes = PhotoImageProvider.debugDecodes;

        world.container.read(appSessionProvider.notifier).lock();
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(world.container.read(appSessionProvider).locked, isTrue);
        expect(find.byType(PhotoViewerScreen, skipOffstage: false), findsNothing);
        expect(find.byType(ChatRoomScreen, skipOffstage: false), findsNothing);
        expect(PhotoImageProvider.debugDecodes, decodes, reason: 'a photo was decoded after the lock');
        final cache = PaintingBinding.instance.imageCache;
        expect(cache.currentSize + cache.pendingImageCount + cache.liveImageCount, 0,
            reason: 'a decoded photo stays in memory behind the lock screen');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        world.dispose();
      }
    });
  }

  testWidgets('the viewer closes when its disappearing photo expires, and nothing of it can be saved after',
      (tester) async {
    await withChat(tester, (world) async {
      world.messenger.media.setInUse(true);
      await deliverAttachment(world,
          plaintext: landscapePhoto,
          contentType: 'image/jpeg',
          kind: MessageKind.image,
          hour: 10,
          minute: 16,
          expiresAt: world.relay.now().add(const Duration(minutes: 1)));
    }, (world) async {
      final inBubble = find.descendant(of: find.byType(MessagePhoto), matching: drawnPhoto);
      await until(tester, () => inBubble.evaluate().isNotEmpty, reason: 'the photo never showed');
      await tester.tap(inBubble);
      await pumpFrames(tester, frames: 4);
      final inViewer = find.descendant(of: find.byType(PhotoViewerScreen), matching: drawnPhoto);
      await until(tester, () => inViewer.evaluate().isNotEmpty, reason: 'the viewer never drew the photo');
      // The Save dialog is up when the minute runs out.
      await tester.tap(find.byKey(const ValueKey('photo-viewer-save')));
      await pumpFrames(tester, frames: 4);
      expect(find.text(l10n.chatSaveTitle), findsOneWidget);
      final downloads = world.relay.blobDownloads.length;

      world.relay.deviceClockSkew[selfHandle] = const Duration(minutes: 2);
      // Any change to the chat lets the store notice.
      await deliverAttachment(world,
          plaintext: pdfBytes('later'),
          contentType: 'application/pdf',
          kind: MessageKind.file,
          body: 'later.pdf',
          hour: 10,
          minute: 30);
      // Real time for the store to notice, fake time for the viewer to fade.
      for (var i = 0; i < 150 && find.byType(PhotoViewerScreen).evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(PhotoViewerScreen), findsNothing,
          reason: 'the viewer kept showing a photo whose message disappeared');
      expect(find.byType(MessagePhoto), findsNothing);
      expect(find.text(l10n.chatSaveTitle), findsNothing, reason: 'the Save dialog outlived the photo');
      expect(opener.saved, isEmpty);
      expect(world.relay.blobDownloads, hasLength(downloads), reason: 'the expired photo was fetched again');
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
      await tester.tap(_receivedFile);
      await until(tester, () => find.text('No app found to open this file').evaluate().isNotEmpty,
          reason: 'no toast');
    });
  });

  // The long-press menu's Save (H4): above Report, behind the dialog, and
  // the copy goes once the save screen returns.
  testWidgets('a long press on a file offers Save above Report, and Save asks first', (tester) async {
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
      await tester.longPress(_receivedFile);
      await pumpFrames(tester, frames: 4);
      final save = find.byKey(const ValueKey('message-save'));
      final report = find.byKey(const ValueKey('message-report'));
      expect(save, findsOneWidget);
      expect(report, findsOneWidget);
      expect(tester.getTopLeft(save).dy, lessThan(tester.getTopLeft(report).dy), reason: 'Save sits above Report');

      await tester.tap(save);
      await pumpFrames(tester, frames: 4);
      expect(find.text(l10n.chatSaveTitle), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save-confirm')));
      await until(tester, () => opener.saved.isNotEmpty, reason: 'nothing reached the save screen');
      expect(opener.saved.single.bytes, leasePdf);
      expect(opener.saved.single.as, leaseFileName);
      await until(tester, () => find.text(l10n.chatSaved).evaluate().isNotEmpty, reason: 'no "Saved"');
      expect(world.messenger.media.cleanup.copies, isEmpty, reason: 'the copy outlived the save');
    });
  });

  // Design rule 18 on the desktop alpha, where nothing can be handed to
  // another app or the save screen: no Save anywhere, and a file that is no
  // photo says this version cannot open it, with nothing fetched.
  group('where nothing can be handed over', () {
    Future<void> withDesktopChat(WidgetTester tester, Future<void> Function(LayoutWorld world) seed,
        Future<void> Function(LayoutWorld world) body) {
      return withPhoneApp(
        tester,
        identities,
        location: _chat,
        overrides: [
          attachmentOpenerProvider.overrideWithValue(opener),
          fileHandOverAvailableProvider.overrideWithValue(false),
        ],
        afterSession: seed,
        body: body,
      );
    }

    Future<void> lease(LayoutWorld world) => deliverAttachment(world,
        plaintext: leasePdf,
        contentType: 'application/pdf',
        kind: MessageKind.file,
        body: leaseFileName,
        hour: 10,
        minute: 16);

    testWidgets('a long press on a file offers no Save', (tester) async {
      await withDesktopChat(tester, (world) async {
        await lease(world);
      }, (world) async {
        await tester.longPress(find.byType(MessageFileCard));
        await pumpFrames(tester, frames: 4);
        expect(find.byKey(const ValueKey('message-report')), findsOneWidget);
        expect(find.byKey(const ValueKey('message-save')), findsNothing);
      });
    });

    testWidgets('a tap on a PDF says this version cannot open it, and nothing is fetched or handed over',
        (tester) async {
      await withDesktopChat(tester, lease, (world) async {
        await tester.tap(find.byType(MessageFileCard));
        await until(tester, () => find.text(l10n.chatAttachmentCannotOpen).evaluate().isNotEmpty,
            reason: 'nothing said why it does not open');
        expect(world.relay.downloadTicketRequests, isEmpty, reason: 'a file that cannot open was fetched');
        expect(opener.opened, isEmpty);
        expect(world.messenger.media.cleanup.copies, isEmpty);
      });
    });

    testWidgets('a PNG sent as a file still opens in the viewer, which offers no Save', (tester) async {
      await withDesktopChat(
          tester,
          (world) => deliverAttachment(world,
              plaintext: solidPng(width: 300, height: 200),
              contentType: 'image/png',
              kind: MessageKind.file,
              body: 'diagram.png',
              hour: 10,
              minute: 16), (world) async {
        await tester.tap(find.byType(MessageFileCard));
        await until(tester, () => find.byType(PhotoViewerScreen).evaluate().isNotEmpty,
            reason: 'a photo sent as a file did not open in the viewer');
        expect(find.byKey(const ValueKey('photo-viewer-save')), findsNothing);
        expect(opener.opened, isEmpty);
      });
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
      expect(_receivedFile, findsNothing);
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
            await tester.tap(_receivedFile);
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
          await tester.tap(_receivedFile);
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

class _QuietNotifications implements LocalNotificationService {
  @override
  void Function(String? conversationId)? onNotificationTapped;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showMessageNotification({required String conversationId, required String title, required String body}) async {}

  @override
  Future<void> cancelConversation(String conversationId) async {}
}
