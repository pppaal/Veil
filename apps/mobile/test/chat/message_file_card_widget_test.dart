import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_opener.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_viewer_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_file_card.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_transfer_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger_providers.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';

import '../support/fake_attachment_opener.dart';
import '../support/media_fixtures.dart';
import '../support/scripted_media.dart';

// A file message, state by state (D27, D28, D31): where it stands in its
// circle, the sender's name cut in the middle, the type from the extension,
// a tap that fetches it or opens it.

final AppLocalizations l10n = AppLocalizationsEn();
const _chat = 'conv-1';

AttachmentReference _pointer({String contentType = 'application/pdf', int sizeBytes = 2411724}) =>
    AttachmentReference(
      attachmentId: '00000000-0000-4000-8000-000000000001',
      storageKey: '',
      contentType: contentType,
      sizeBytes: sizeBytes,
      sha256: 'digest',
      encryptedKey: 'key',
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
        messageKind: MessageKind.file,
      ),
    );

void main() {
  late ScriptedMedia media;
  late FakeAttachmentOpener opener;
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('veil-card-');
    media = ScriptedMedia(openRoot: root);
    opener = FakeAttachmentOpener();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> show(
    WidgetTester tester, {
    String name = 'lease.pdf',
    AttachmentReference? attachment,
    ChatMessage? message,
    AttachmentTransferSnapshot? snapshot,
    VoidCallback? onCancel,
    double width = 280,
  }) async {
    final messenger = ScriptedMediaMessenger(media);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        messengerControllerProvider.overrideWith((ref) => messenger),
        attachmentOpenerProvider.overrideWithValue(opener),
      ],
      child: MaterialApp(
        theme: VeilTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: MessageFileCard(
                conversationId: _chat,
                message: message ?? _message(),
                attachment: attachment ?? _pointer(),
                name: name,
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

  // An open reads the copy and the photo header outside the fake clock.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  void ready({List<int>? plaintext}) {
    media
      ..plaintexts[MediaKey(_chat, _pointer())] = Uint8List.fromList(plaintext ?? pdfBytes('lease'))
      ..setStatus(_chat, _pointer(), MediaState.ready);
  }

  MiddleEllipsisText nameText(WidgetTester tester) => tester.widget<MiddleEllipsisText>(find.byType(MiddleEllipsisText));

  group('where it stands', () {
    testWidgets('not here yet: the download glyph, the name, the type and size; one tap fetches and opens it',
        (tester) async {
      // What the fetch and the decrypt will hand back.
      media.plaintexts[MediaKey(_chat, _pointer())] = Uint8List.fromList(pdfBytes('lease'));
      await show(tester);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(nameText(tester).text, 'lease.pdf');
      expect(find.text('PDF · 2.3 MB'), findsOneWidget);
      expect(media.copies, isEmpty, reason: 'a file never comes by itself');

      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(media.copies, [(MediaKey(_chat, _pointer()), MediaCopyPurpose.open)],
          reason: 'the tap did not fetch it for opening');
      expect(opener.opened.single.bytes, pdfBytes('lease'), reason: 'a second tap was needed to open it');
    });

    testWidgets('a fetch that does not finish opens nothing, and the card says why, not a toast', (tester) async {
      await show(tester);
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(media.copies, hasLength(1));
      expect(opener.opened, isEmpty);
      expect(find.text(l10n.chatOpenFileFailed), findsNothing);
    });

    testWidgets('on its way: a ring with a cross that stops it', (tester) async {
      media.setStatus(_chat, _pointer(), MediaState.downloading, progress: 0.6);
      await show(tester);
      expect(tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).value, 0.6);
      expect(find.byTooltip(l10n.chatCancelDownload), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(media.cancels, [MediaKey(_chat, _pointer())]);
    });

    testWidgets('the fetch failed: it says so under the size, and a tap tries again', (tester) async {
      media.setStatus(_chat, _pointer(), MediaState.failed);
      await show(tester);
      expect(find.text('Couldn\'t download. Tap to retry.'), findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget, reason: 'D31: the download glyph');
      expect(find.byIcon(Icons.refresh), findsNothing);
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(media.copies, hasLength(1), reason: 'the tap did not try again');
    });

    testWidgets('gone from the server: "File not available", and a tap does nothing', (tester) async {
      media.setStatus(_chat, _pointer(), MediaState.gone);
      await show(tester);
      expect(find.text('File not available'), findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsNothing);
      await tester.tap(find.byType(MessageFileCard));
      await tester.pump();
      expect(media.downloads, isEmpty);
      expect(media.copies, isEmpty);
    });

    testWidgets('here: the file glyph, and nothing under the size', (tester) async {
      ready();
      await show(tester);
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsNothing);
      expect(find.textContaining('download'), findsNothing);
    });
  });

  group('the name and the type', () {
    testWidgets('a long name is cut in the middle, keeping its real extension', (tester) async {
      const name = 'Lease agreement for the flat on Elm Street signed final.pdf';
      await show(tester, name: name, width: 390);
      final render = tester.renderObject<RenderMiddleEllipsisText>(find.byType(MiddleEllipsisText));
      final shown = render.shownText;
      expect(shown, contains('…'));
      expect(shown, endsWith('.pdf'));
      expect(shown, startsWith('Lease'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the type comes from the extension, never from what the sender claims', (tester) async {
      await show(tester, name: 'notes.txt', attachment: _pointer(contentType: 'image/png', sizeBytes: 900));
      expect(find.text('TXT · 900 B'), findsOneWidget);
    });

    testWidgets('a bidi override is taken out of the name; the type is its real extension', (tester) async {
      await show(tester, name: '../../evil\u202Efdp.sh');
      final shown = nameText(tester).text;
      expect(shown, isNot(contains('\u202E')));
      expect(find.text('SH · 2.3 MB'), findsOneWidget);
    });

    testWidgets('a line separator cannot end the name early and hide its real extension', (tester) async {
      await show(tester, name: 'invoice.pdf\u2028\u2028\u2029.exe');
      expect(nameText(tester).text, 'invoice.pdf   .exe');
      expect(find.text('EXE · 2.3 MB'), findsOneWidget);
    });

    testWidgets('a name cut in the middle keeps no space after the ellipsis', (tester) async {
      const name = 'Lease agreement for the flat on Elm Street signed final.pdf';
      await show(tester, name: name, width: 300);
      final shown = tester.renderObject<RenderMiddleEllipsisText>(find.byType(MiddleEllipsisText)).shownText;
      expect(shown, contains('…'));
      expect(shown, isNot(contains('… ')));
      expect(shown, endsWith('final.pdf'));
    });

    testWidgets('semantics: the name, then the type and size, and what a tap does', (tester) async {
      await show(tester);
      final semantics = tester.widget<Semantics>(find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == 'lease.pdf, PDF · 2.3 MB'));
      expect(semantics.properties.hintOverrides?.onTapHint, l10n.chatDownloadAction);
      expect(semantics.properties.button, isTrue);
    });

    for (final (state, words) in [
      (MediaState.gone, 'File not available'),
      (MediaState.failed, 'Couldn\'t download. Tap to retry.'),
    ]) {
      testWidgets('semantics when ${state.name}: a screen reader hears "$words" too', (tester) async {
        final handle = tester.ensureSemantics();
        media.setStatus(_chat, _pointer(), state);
        await show(tester);
        final label = tester.getSemantics(find.byType(MessageFileCard)).label;
        expect(label, startsWith('lease.pdf, PDF · 2.3 MB'));
        expect(label, contains(words), reason: 'state is always also text, for a screen reader too');
        handle.dispose();
      });
    }
  });

  group('opening it (D28)', () {
    testWidgets('a PDF opens in another app as application/pdf, its bytes as sent', (tester) async {
      ready();
      await show(tester);
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(opener.opened, hasLength(1));
      expect(opener.opened.single.as, 'application/pdf');
      expect(opener.opened.single.bytes, pdfBytes('lease'));
      expect(media.copies.single.$2, MediaCopyPurpose.open);
    });

    testWidgets('the app locks while the copy is read: nothing reaches another app, and the copy goes',
        (tester) async {
      ready();
      await show(tester);
      await tester.tap(find.byType(MessageFileCard));
      // The lock lands before the copy is handed on.
      media.evict();
      await drain(tester);
      expect(media.copies, hasLength(1));
      expect(opener.opened, isEmpty, reason: 'a decrypted file was handed on after the lock');
      expect(media.released, hasLength(1), reason: 'the copy was left behind');
      expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    testWidgets('kind file claiming image/png but named .pdf opens as a PDF', (tester) async {
      media
        ..plaintexts[MediaKey(_chat, _pointer(contentType: 'image/png'))] = pdfBytes('x')
        ..setStatus(_chat, _pointer(contentType: 'image/png'), MediaState.ready);
      await show(tester, attachment: _pointer(contentType: 'image/png'));
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(opener.opened.single.as, 'application/pdf');
    });

    testWidgets('no app for it: the copy goes and a toast says so', (tester) async {
      opener.openOutcome = OpenOutcome.noApp;
      ready();
      await show(tester);
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(find.text('No app found to open this file'), findsOneWidget);
      expect(media.released, [opener.opened.single.path]);
      expect(File(opener.opened.single.path).existsSync(), isFalse);
    });

    testWidgets('the app failed: the copy goes and a toast says so', (tester) async {
      opener.openOutcome = OpenOutcome.failed;
      ready();
      await show(tester);
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(find.text('Couldn\'t open the file'), findsOneWidget);
      expect(media.released, hasLength(1));
    });

    testWidgets('opened on Android: the copy stays for the app reading it', (tester) async {
      ready();
      await show(tester);
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(media.released, isEmpty);
      expect(File(opener.opened.single.path).existsSync(), isTrue);
    });

    testWidgets('a file whose bytes are a PNG opens in the viewer, not another app', (tester) async {
      ready(plaintext: solidPng(width: 40, height: 30));
      await show(tester, name: 'scan.png');
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewerScreen), findsOneWidget);
      expect(find.text('Selene'), findsOneWidget);
      expect(opener.opened, isEmpty);
      expect(media.released, hasLength(1), reason: 'the copy outlived the viewer opening');
    });

    testWidgets('on iOS a HEIC never reaches another app: the Save dialog asks instead', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      ready(plaintext: heicHead());
      await show(tester, name: 'IMG_0001.heic');
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      await tester.pumpAndSettle();
      expect(opener.opened, isEmpty);
      expect(find.text(l10n.chatSaveTitle), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('the user\'s own file', () {
    testWidgets('while it sends: the upload ring and a cross that cancels it', (tester) async {
      var canceled = 0;
      await show(
        tester,
        message: _message(mine: true, state: MessageDeliveryState.uploading),
        snapshot: const AttachmentTransferSnapshot(
            clientMessageId: 'c', phase: AttachmentTransferPhase.uploading, progress: 0.3, canRetry: false, canCancel: true),
        onCancel: () => canceled += 1,
      );
      expect(tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).value, 0.3);
      expect(find.byTooltip(l10n.chatCancelAction), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(canceled, 1);
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(media.copies, isEmpty, reason: 'opened while it sends');
    });

    testWidgets('sent: ready to open from this phone, with no fetch', (tester) async {
      ready();
      await show(tester, message: _message(mine: true));
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
      await tester.tap(find.byType(MessageFileCard));
      await drain(tester);
      expect(media.downloads, isEmpty);
      expect(opener.opened, hasLength(1));
    });
  });
}
