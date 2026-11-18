import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_viewer_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_photo.dart';
import 'package:veil_mobile/src/features/chat/presentation/photo_image_provider.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_transfer_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger_providers.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';

import '../support/media_fixtures.dart';
import '../support/scripted_media.dart';

// A photo message, state by state (D23 to D31): the tile before it opens,
// the photo at its own aspect once it does, the user's own while it sends.

final AppLocalizations l10n = AppLocalizationsEn();
const _chat = 'conv-1';

AttachmentReference _pointer({int sizeBytes = 48 * 1024, String id = '00000000-0000-4000-8000-000000000001'}) =>
    AttachmentReference(
      attachmentId: id,
      storageKey: '',
      contentType: 'image/jpeg',
      sizeBytes: sizeBytes,
      sha256: 'digest-$id',
      encryptedKey: 'key-$id',
      nonce: 'nonce',
      algorithmHint: 'aes256gcm-v2',
    );

ChatMessage _message({bool mine = false, MessageDeliveryState state = MessageDeliveryState.sent}) => ChatMessage(
      id: 'msg-1',
      senderDeviceId: mine ? 'dev-atlas' : 'dev-selene',
      sentAt: DateTime.utc(2026, 4, 7, 9, 52),
      isMine: mine,
      deliveryState: state,
      envelope: const CryptoEnvelope(
        version: 'v2',
        conversationId: _chat,
        senderDeviceId: 'dev-selene',
        recipientUserId: 'user-atlas',
        ciphertext: 'c',
        nonce: 'n',
        messageKind: MessageKind.image,
      ),
    );

AttachmentTransferSnapshot _snapshot(AttachmentTransferPhase phase, {double progress = 0, bool canCancel = true}) =>
    AttachmentTransferSnapshot(
      clientMessageId: 'client-1',
      phase: phase,
      progress: progress,
      canRetry: phase == AttachmentTransferPhase.failed,
      canCancel: canCancel,
    );

Semantics _photoSemantics(WidgetTester tester) => tester.widget<Semantics>(find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == l10n.chatAttachmentKindPhoto));

void main() {
  late ScriptedMedia media;

  setUp(() {
    media = ScriptedMedia();
    // Decoded photos are kept by their attachment; each test's are its own.
    PaintingBinding.instance.imageCache.clear();
  });

  Future<void> show(
    WidgetTester tester, {
    AttachmentReference? attachment,
    ChatMessage? message,
    String? senderName,
    AttachmentTransferSnapshot? snapshot,
    VoidCallback? onCancel,
  }) async {
    final messenger = ScriptedMediaMessenger(media);
    await tester.pumpWidget(ProviderScope(
      overrides: [messengerControllerProvider.overrideWith((ref) => messenger)],
      child: MaterialApp(
        theme: VeilTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: MessagePhoto(
                conversationId: _chat,
                message: message ?? _message(),
                attachment: attachment ?? _pointer(),
                meta: const Text('9:52 AM'),
                unsupported: const Text('cannot open'),
                senderName: senderName,
                authorName: 'Selene',
                transferSnapshot: snapshot,
                onCancelAttachment: onCancel,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  // Real decodes run outside the test's fake clock.
  Future<void> letDecode(WidgetTester tester) async {
    for (var i = 0; i < 30 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Size photoSize(WidgetTester tester) => tester.getSize(find.byType(RawImage));

  group('before it opens: a 210 dp square tile', () {
    testWidgets('not here yet: the download glyph and the size; a tap fetches it', (tester) async {
      await show(tester);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(find.text('48 KB'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
      expect(tester.getSize(find.byType(AnimatedContainer)), const Size.square(photoTileExtent));
      expect(media.photoRequests.where((request) => request.$2), isEmpty, reason: 'fetched before a tap');

      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump();
      expect(media.photoRequests.last, (MediaKey(_chat, _pointer()), true));
    });

    testWidgets('on its way: a ring and the size, and no tap does anything', (tester) async {
      media.setStatus(_chat, _pointer(), MediaState.downloading, progress: 0.4);
      await show(tester);
      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, 0.4);
      expect(find.bySemanticsLabel(RegExp(l10n.chatDownloading)), findsOneWidget);
      expect(find.text('48 KB'), findsOneWidget);
      final asked = media.photoRequests.length;
      await tester.tap(find.byType(MessagePhoto));
      await tester.pump();
      expect(media.photoRequests.where((request) => request.$2), isEmpty);
      expect(media.photoRequests.length, asked);
    });

    testWidgets('the fetch failed: it says so and a tap tries again', (tester) async {
      media.setStatus(_chat, _pointer(), MediaState.failed);
      await show(tester);
      expect(find.text(l10n.chatDownloadFailed), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget, reason: 'the retry glyph');
      expect(find.text('Couldn\'t download. Tap to retry.'), findsOneWidget);
      await tester.tap(find.byType(MessagePhoto));
      await tester.pump();
      expect(media.photoRequests.last.$2, isTrue);
    });

    testWidgets('gone from the server: it says the photo is not available, and nothing is offered', (tester) async {
      media.setStatus(_chat, _pointer(), MediaState.gone);
      await show(tester);
      expect(find.text('Photo not available'), findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsNothing);
      await tester.tap(find.byType(MessagePhoto));
      await tester.pump();
      expect(media.photoRequests.where((request) => request.$2), isEmpty);
    });

    testWidgets('bytes this version cannot draw: the card that says so instead', (tester) async {
      media.setStatus(_chat, _pointer(), MediaState.unsupported);
      await show(tester);
      expect(find.text('cannot open'), findsOneWidget);
      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('a pointer this version does not open is never asked for', (tester) async {
      final old = AttachmentReference(
        attachmentId: 'att-1',
        storageKey: 'blob-1',
        contentType: 'image/png',
        sizeBytes: 512,
        sha256: 'd',
        encryptedKey: 'k',
        nonce: 'n',
      );
      await show(tester, attachment: old);
      expect(find.text('cannot open'), findsOneWidget);
    });
  });

  group('once it opens: the photo is the bubble', () {
    Future<void> showPhoto(WidgetTester tester, Uint8List bytes, {ChatMessage? message, String? senderName}) async {
      media
        ..photos[MediaKey(_chat, _pointer())] = bytes
        ..setStatus(_chat, _pointer(), MediaState.ready);
      await show(tester, message: message, senderName: senderName);
      await letDecode(tester);
      // The tile grows into the photo.
      await tester.pumpAndSettle();
    }

    testWidgets('a landscape photo fills 240 dp wide at its own aspect', (tester) async {
      await showPhoto(tester, solidPng(width: 640, height: 480));
      expect(photoSize(tester), const Size(240, 180));
      expect(find.text('9:52 AM'), findsOneWidget, reason: 'the meta strip under it');
      expect(tester.getTopLeft(find.text('9:52 AM')).dy, greaterThan(tester.getBottomLeft(find.byType(RawImage)).dy - 1));
    });

    testWidgets('a 4000 x 1000 panorama is held to 100 dp tall, cropped from the middle', (tester) async {
      await showPhoto(tester, solidPng(width: 4000, height: 1000));
      expect(photoSize(tester), const Size(240, 100));
      expect(tester.widget<RawImage>(find.byType(RawImage)).fit, BoxFit.cover);
    });

    testWidgets('a 500 x 4000 strip is held to 320 dp tall and 150 dp wide', (tester) async {
      await showPhoto(tester, solidPng(width: 500, height: 4000));
      expect(photoSize(tester), const Size(150, 320));
    });

    testWidgets('it is decoded no larger than its bubble on this screen', (tester) async {
      PhotoImageProvider.debugDecodes = 0;
      await showPhoto(tester, solidPng(width: 3000, height: 2000));
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      final ratio = tester.view.devicePixelRatio;
      expect(image.width, (240 * ratio).round());
      expect(image.height, (160 * ratio).round());
      expect(PhotoImageProvider.debugDecodes, 1);
    });

    testWidgets('a tap opens the viewer, titled with who sent it', (tester) async {
      await showPhoto(tester, solidPng(width: 64, height: 48));
      await tester.tap(find.byType(RawImage));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewerScreen), findsOneWidget);
      expect(find.text('Selene'), findsOneWidget);
    });

    testWidgets('in a group the sender is named in a strip above the photo', (tester) async {
      await showPhoto(tester, solidPng(width: 64, height: 48), senderName: 'Mara');
      expect(find.text('Mara'), findsOneWidget);
      expect(tester.getBottomLeft(find.text('Mara')).dy, lessThanOrEqualTo(tester.getTopLeft(find.byType(RawImage)).dy));
    });

    testWidgets('the lock drops the decoded photo; it comes back in place once unlocked', (tester) async {
      await showPhoto(tester, solidPng(width: 640, height: 480));
      media.statuses.clear();
      media.evict();
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(tester.getSize(find.byType(AnimatedContainer)), const Size(240, 180), reason: 'the bubble jumped');

      media.setStatus(_chat, _pointer(), MediaState.ready);
      await letDecode(tester);
      expect(find.byType(RawImage), findsOneWidget);
    });

    testWidgets('semantics: "Photo", a button whose tap opens it', (tester) async {
      final handle = tester.ensureSemantics();
      await showPhoto(tester, solidPng(width: 64, height: 48));
      final data = tester.getSemantics(find.bySemanticsLabel(RegExp('^${l10n.chatAttachmentKindPhoto}'))).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(_photoSemantics(tester).properties.hintOverrides?.onTapHint, l10n.chatOpenAction);
      handle.dispose();
    });

    testWidgets('semantics before it opens: a tap downloads it', (tester) async {
      await show(tester);
      expect(_photoSemantics(tester).properties.hintOverrides?.onTapHint, l10n.chatDownloadAction);
      expect(_photoSemantics(tester).properties.button, isTrue);
    });
  });

  group('the user\'s own photo', () {
    testWidgets('while it uploads: a scrim, the upload ring, and a cross that cancels it', (tester) async {
      var canceled = 0;
      media
        ..photos[MediaKey(_chat, _pointer())] = solidPng(width: 640, height: 480)
        ..setStatus(_chat, _pointer(), MediaState.ready);
      await show(tester,
          message: _message(mine: true, state: MessageDeliveryState.uploading),
          snapshot: _snapshot(AttachmentTransferPhase.uploading, progress: 0.25),
          onCancel: () => canceled += 1);
      await letDecode(tester);

      expect(find.byType(RawImage), findsOneWidget, reason: 'shown from the blob on this phone');
      expect(
        find.byWidgetPredicate((widget) => widget is ColoredBox && widget.color == const Color(0x66000000)),
        findsOneWidget,
      );
      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, 0.25);
      expect(find.bySemanticsLabel(RegExp(l10n.chatDeliveryUploading)), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(canceled, 1);

      // Not opened while it sends.
      await tester.tap(find.byType(RawImage), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewerScreen), findsNothing);
    });

    testWidgets('a send that failed: no scrim, the cross stays, and it says it was not sent', (tester) async {
      var canceled = 0;
      media
        ..photos[MediaKey(_chat, _pointer())] = solidPng(width: 640, height: 480)
        ..setStatus(_chat, _pointer(), MediaState.ready);
      await show(tester,
          message: _message(mine: true, state: MessageDeliveryState.failed),
          snapshot: _snapshot(AttachmentTransferPhase.failed),
          onCancel: () => canceled += 1);
      await letDecode(tester);

      expect(
        find.byWidgetPredicate((widget) => widget is ColoredBox && widget.color == const Color(0x66000000)),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(l10n.chatNotSentTapToRetry), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(canceled, 1);
    });

    testWidgets('sent: nothing over it, and a tap opens it as "You"', (tester) async {
      media
        ..photos[MediaKey(_chat, _pointer())] = solidPng(width: 64, height: 48)
        ..setStatus(_chat, _pointer(), MediaState.ready);
      await show(tester, message: _message(mine: true));
      await letDecode(tester);
      expect(find.byIcon(Icons.close), findsNothing);
      await tester.tap(find.byType(RawImage));
      await tester.pumpAndSettle();
      expect(find.text(l10n.viewerSenderYou), findsOneWidget);
    });
  });
}
