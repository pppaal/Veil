import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_labels.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_attachment_views.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_read_glyph.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_time.dart';
import 'package:veil_mobile/src/features/chat/presentation/reaction_chips_row.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

// The parts a chat message is drawn from, one at a time.

final AppLocalizations l10n = AppLocalizationsEn();

Widget _app(Widget child) => MaterialApp(
      theme: VeilTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

AttachmentReference _reference(String contentType, int sizeBytes) => AttachmentReference(
      attachmentId: 'att-1',
      storageKey: 'blob-1',
      contentType: contentType,
      sizeBytes: sizeBytes,
      sha256: 'digest',
      encryptedKey: 'wrapped',
      nonce: 'nonce',
    );

AttachmentTransferSnapshot _transfer(
  AttachmentTransferPhase phase, {
  double progress = 0,
  String? filename,
  String? contentType,
  int? sizeBytes,
  String? errorMessage,
}) =>
    AttachmentTransferSnapshot(
      clientMessageId: 'client-1',
      phase: phase,
      progress: progress,
      filename: filename,
      contentType: contentType,
      sizeBytes: sizeBytes,
      errorMessage: errorMessage,
      canRetry: false,
      canCancel: false,
    );

double? _progressValue(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value;

void main() {
  group('MessageAttachmentCard', () {
    testWidgets('in a build that cannot open attachments: the name, the type and size, and the line that says so',
        (tester) async {
      await tester.pumpWidget(_app(MessageAttachmentCard(
        attachment: _reference('application/pdf', 3 * 1024 * 1024),
        name: 'lease-signed.pdf',
        resolving: false,
        downloadError: null,
        onResolve: null,
      )));

      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      // One card says it all, as WhatsApp's file card does.
      expect(find.text('lease-signed.pdf'), findsOneWidget);
      expect(find.text('PDF · 3 MB'), findsOneWidget);
      expect(find.text(l10n.chatAttachmentCannotOpen), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      // Nothing restates that the file is encrypted, and no pill or banner.
      expect(find.textContaining('Encrypted'), findsNothing);
      expect(find.byType(VeilNotice), findsNothing);
    });

    // A voice note the web app records is an audio file; the message's kind
    // says it is a voice message, as its Chats row does.
    testWidgets('a voice message is called one, with a microphone, whatever its file type', (tester) async {
      await tester.pumpWidget(_app(MessageAttachmentCard(
        attachment: _reference('audio/mp4', 57344),
        resolving: false,
        downloadError: null,
        onResolve: null,
        voice: true,
      )));
      expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
      expect(find.text('${l10n.chatAttachmentKindVoice} · 56 KB'), findsOneWidget);
      expect(find.text(l10n.chatAttachmentCannotOpen), findsOneWidget);

      await tester.pumpWidget(_app(MessageAttachmentCard(
        attachment: _reference('audio/mp4', 57344),
        resolving: false,
        downloadError: null,
        onResolve: null,
      )));
      expect(find.byIcon(Icons.audiotrack_outlined), findsOneWidget);
      expect(find.text('Audio · 56 KB'), findsOneWidget);
    });

    testWidgets('where a build can open them, a text button asks for the download ticket', (tester) async {
      var resolved = 0;
      await tester.pumpWidget(_app(MessageAttachmentCard(
        attachment: _reference('application/pdf', 3 * 1024 * 1024),
        resolving: false,
        downloadError: null,
        onResolve: () => resolved++,
      )));
      expect(find.text(l10n.chatAttachmentCannotOpen), findsNothing);
      await tester.tap(find.text(l10n.chatAttachmentResolveAction));
      expect(resolved, 1);
    });

    testWidgets('while a ticket resolves it cannot be asked for again, and a refusal says so', (tester) async {
      var resolved = 0;
      await tester.pumpWidget(_app(MessageAttachmentCard(
        attachment: _reference('image/png', 512),
        resolving: true,
        downloadError: 'ticket refused',
        onResolve: () => resolved++,
      )));

      expect(find.text('Photo · 512 B'), findsOneWidget);
      final resolve = tester.widget<TextButton>(find.widgetWithText(TextButton, l10n.chatAttachmentResolvingAction));
      expect(resolve.onPressed, isNull);
      expect(find.text(l10n.chatAttachmentTicketFailed), findsOneWidget);
      expect(find.text('ticket refused'), findsOneWidget);
      expect(resolved, 0);
    });

    testWidgets('a flat tile: grey only on the brand fill of an own bubble, never a border', (tester) async {
      Future<BoxDecoration?> tile({required bool framed}) async {
        await tester.pumpWidget(_app(MessageAttachmentCard(
          attachment: _reference('image/png', 512),
          resolving: false,
          downloadError: null,
          onResolve: null,
          framed: framed,
        )));
        final boxes = tester.widgetList<DecoratedBox>(
          find.descendant(of: find.byType(MessageAttachmentCard), matching: find.byType(DecoratedBox)),
        );
        return boxes.isEmpty ? null : boxes.first.decoration as BoxDecoration;
      }

      expect(await tile(framed: false), isNull, reason: 'in a grey bubble the bubble is the tile');
      final framed = await tile(framed: true);
      final palette = tester.element(find.byType(MessageAttachmentCard)).veilPalette;
      expect(framed?.color, palette.surfaceAlt);
      expect(framed?.border, isNull);
      expect(framed?.borderRadius, BorderRadius.circular(VeilRadius.md));
    });
  });

  group('AttachmentTransferPanel', () {
    Widget panel(AttachmentTransferSnapshot snapshot, {VoidCallback? onRetry, VoidCallback? onCancel}) => _app(
          AttachmentTransferPanel(
            snapshot: snapshot,
            color: Colors.white,
            mutedColor: Colors.white70,
            onRetry: onRetry,
            onCancel: onCancel,
          ),
        );

    testWidgets('an upload in flight shows its file, what is happening and its progress, and cancel where offered',
        (tester) async {
      var canceled = 0;
      await tester.pumpWidget(panel(
        _transfer(AttachmentTransferPhase.uploading, progress: 0.42, filename: 'scan.pdf', contentType: 'application/pdf'),
        onCancel: () => canceled++,
      ));

      expect(find.text('scan.pdf'), findsOneWidget);
      expect(find.text(l10n.chatPhaseDescUploading), findsOneWidget);
      expect(_progressValue(tester), 0.42);
      // The phase and the share done are words under the bar, not pills.
      expect(find.text(l10n.chatPhaseUploading), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.text(l10n.chatRetryUpload), findsNothing);
      expect(find.text(l10n.chatAttachmentStateBanner), findsNothing);

      await tester.tap(find.text(l10n.chatCancelAction));
      expect(canceled, 1);
    });

    testWidgets('a failed upload of an unnamed file says what failed and offers a retry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(panel(
        _transfer(AttachmentTransferPhase.failed, progress: 0.6, contentType: 'image/jpeg', errorMessage: 'upload refused'),
        onRetry: () => retried++,
      ));

      expect(find.text('Photo'), findsOneWidget);
      expect(find.text(l10n.chatPhaseFailed), findsOneWidget);
      // The error is the description and the notice's message.
      expect(find.text('upload refused'), findsNWidgets(2));
      expect(find.widgetWithText(VeilNotice, l10n.chatAttachmentStateBanner), findsOneWidget);
      expect(_progressValue(tester), 0.6);
      expect(find.text(l10n.chatCancelAction), findsNothing);

      await tester.tap(find.text(l10n.chatRetryUpload));
      expect(retried, 1);
    });

    testWidgets('a staged upload states its size; preparing and finalizing have no fixed progress',
        (tester) async {
      await tester.pumpWidget(panel(_transfer(AttachmentTransferPhase.staged, sizeBytes: 512)));
      expect(find.text(l10n.chatPhaseDescStaged(' 512 bytes.')), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(_progressValue(tester), 0);
      expect(find.byType(TextButton), findsNothing);

      for (final phase in [AttachmentTransferPhase.preparing, AttachmentTransferPhase.finalizing]) {
        await tester.pumpWidget(panel(_transfer(phase, progress: 0.5)));
        expect(_progressValue(tester), isNull, reason: '$phase');
      }
    });
  });

  group('MessageBubble meta', () {
    ChatMessage message({required MessageDeliveryState state, DateTime? expiresAt, bool mine = true}) => ChatMessage(
          id: 'msg-1',
          senderDeviceId: 'device-1',
          sentAt: DateTime(2026, 4, 7, 9, 17),
          isMine: mine,
          deliveryState: state,
          expiresAt: expiresAt,
          envelope: const CryptoEnvelope(
            version: 'v',
            conversationId: 'conv-1',
            senderDeviceId: 'device-1',
            recipientUserId: 'user-1',
            ciphertext: 'x',
            nonce: 'n',
            messageKind: MessageKind.text,
          ),
        );

    Future<void> pumpBubble(WidgetTester tester, String body, ChatMessage message, {VoidCallback? onRetry}) async {
      await tester.pumpWidget(MaterialApp(
        theme: VeilTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              child: MessageBubble(
                message: message,
                highlighted: false,
                sentAtFormat: MessageTimeFormat(AppLocalizationsEn(), use24HourFormat: true),
                decryptFuture: Future.value(DecryptedMessage(body: body, messageKind: MessageKind.text)),
                onResolveAttachment: (_) async {},
                onCancelAttachment: null,
                isResolvingAttachment: (_) => false,
                attachmentDownloadError: (_) => null,
                transferSnapshot: null,
                expiryNow: () => DateTime(2026, 4, 7, 9, 18),
                onRetryMessage: onRetry ?? () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    // The bubble is as wide as its widest line. On a short message that is
    // the meta, which must then fit on the one line it was measured for. A
    // read message shows Signal's two filled circles, and no word.
    for (final body in ['ok', 'Yes', 'Sure, see you then']) {
      testWidgets('a read "$body": its glyph sits on the line of the time, with no word', (tester) async {
        await pumpBubble(tester, body, message(state: MessageDeliveryState.read));
        final time = tester.getRect(find.text('09:17'));
        final read = tester.getRect(find.byType(MessageReadGlyph));
        expect(find.byType(MessageReadGlyph), findsOneWidget);
        expect(find.text(l10n.chatDeliveryRead), findsNothing);
        expect(read.center.dy, closeTo(time.center.dy, 1), reason: 'the glyph wrapped under the time');
        expect(read.left, greaterThan(time.right));
      });
    }

    testWidgets('sent, delivered and waiting each have their glyph', (tester) async {
      await pumpBubble(tester, 'ok', message(state: MessageDeliveryState.sent));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      await pumpBubble(tester, 'ok', message(state: MessageDeliveryState.delivered));
      expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
      await pumpBubble(tester, 'ok', message(state: MessageDeliveryState.pending));
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    // Read is two filled circles with the checks cut out in the bubble's
    // fill, in the box "delivered" takes, so the time stays put.
    testWidgets('read cuts its checks in the bubble fill, in the box delivered takes', (tester) async {
      await pumpBubble(tester, 'ok', message(state: MessageDeliveryState.delivered));
      final delivered = tester.getSize(
        find.ancestor(of: find.byIcon(Icons.check_circle_outline).first, matching: find.byType(SizedBox)).first,
      );
      await pumpBubble(tester, 'ok', message(state: MessageDeliveryState.read));
      final glyph = tester.widget<MessageReadGlyph>(find.byType(MessageReadGlyph));
      expect(glyph.cutColor, VeilBubble.fillOf(VeilPalette.dark, isMine: true));
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(tester.getSize(find.byType(MessageReadGlyph)), delivered);
    });

    // The bubble itself is the retry: there is no button in it. It keeps
    // its colour, with a red glyph beside it.
    testWidgets('a failed send says so under it, and a tap on the bubble retries it once', (tester) async {
      var retried = 0;
      await pumpBubble(tester, 'see you at 6', message(state: MessageDeliveryState.failed), onRetry: () => retried++);
      expect(find.text(l10n.chatNotSentTapToRetry), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      await tester.tap(find.text('see you at 6'));
      await tester.pump();
      expect(retried, 1);

      // A message that went out is not sent again by a tap.
      await pumpBubble(tester, 'see you at 6', message(state: MessageDeliveryState.sent), onRetry: () => retried++);
      expect(find.text(l10n.chatNotSentTapToRetry), findsNothing);
      await tester.tap(find.text('see you at 6'));
      await tester.pump();
      expect(retried, 1);
    });

    for (final mine in [true, false]) {
      testWidgets('a disappearing "ok" (${mine ? 'own' : 'theirs'}): the timer glyph sits on the line of the time',
          (tester) async {
        await pumpBubble(
          tester,
          'ok',
          message(state: MessageDeliveryState.sent, expiresAt: DateTime(2026, 4, 13, 9, 17), mine: mine),
        );
        final time = tester.getRect(find.text('09:17'));
        final timer = tester.getRect(find.byIcon(Icons.timer_outlined));
        expect(timer.center.dy, closeTo(time.center.dy, 1), reason: 'the time left wrapped under the time');
        expect(timer.left, greaterThan(time.right));
      });
    }
  });

  group('MessageReadGlyph', () {
    // Two filled circles stacked plainly fuse into one pill, and the second
    // hides the first check's long arm. Each check must lie whole inside
    // what is drawn of its own circle: the front disc, or the crescent left
    // of the back one outside the ring.
    test('each check lies whole inside what is drawn of its circle', () {
      final g = MessageReadGlyph.geometry(MessageReadGlyph.size);
      final half = g.stroke / 2;
      Iterable<Offset> along(List<Offset> points) sync* {
        for (var i = 0; i < points.length - 1; i++) {
          for (var t = 0.0; t <= 1.0; t += 0.05) {
            yield Offset.lerp(points[i], points[i + 1], t)!;
          }
        }
      }

      for (final p in along(g.frontCheck)) {
        expect((p - g.front).distance + half, lessThan(g.radius), reason: 'front check leaves its disc at $p');
      }
      for (final p in along(g.backCheck)) {
        expect((p - g.back).distance + half, lessThan(g.radius), reason: 'back check leaves its circle at $p');
        expect((p - g.front).distance - half, greaterThan(g.ring), reason: 'back check runs into the ring at $p');
      }
      expect(g.ring, greaterThan(g.radius), reason: 'no gap between the circles');
      expect(g.back.dx - g.front.dx, greaterThan(g.ring - g.radius + g.radius), reason: 'the circles barely overlap');
      final right = g.back.dx + g.radius;
      expect(g.front.dx - g.radius, greaterThanOrEqualTo(0));
      expect(right, lessThanOrEqualTo(MessageReadGlyph.size.width));
    });

    testWidgets('drawn, both checks show in the bubble fill and both discs in the glyph colour', (tester) async {
      const fill = Color(0xFF1F5FD6);
      const ink = Color(0xFFDCE7FB);
      const scale = 8.0;
      tester.view.physicalSize = MessageReadGlyph.size * scale;
      tester.view.devicePixelRatio = scale;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ColoredBox(
        color: fill,
        child: Align(alignment: Alignment.topLeft, child: MessageReadGlyph(color: ink, cutColor: fill)),
      ));
      final g = MessageReadGlyph.geometry(MessageReadGlyph.size);
      final renderView = tester.binding.renderViews.first;
      final bytes = await tester.runAsync(() async {
        final image = await (renderView.debugLayer! as OffsetLayer).toImage(renderView.paintBounds, pixelRatio: 1);
        final data = await image.toByteData();
        image.dispose();
        return data!;
      });
      final width = (MessageReadGlyph.size.width * scale).round();
      Color at(Offset p) {
        final i = ((p.dy * scale).floor() * width + (p.dx * scale).floor()) * 4;
        return Color.fromARGB(255, bytes!.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
      }

      // Each arm of each check is cut out along its length.
      for (final check in [g.frontCheck, g.backCheck]) {
        for (var i = 0; i < 2; i++) {
          for (final t in [0.25, 0.5, 0.75, 1.0]) {
            final p = Offset.lerp(check[i], check[i + 1], t)!;
            expect(at(p), fill, reason: 'a check arm is not cut out at $p');
          }
        }
      }
      // Above each check, the disc and the crescent are drawn.
      expect(at(g.front.translate(0, -g.radius * 0.75)), ink);
      expect(at(g.back.translate(g.radius * 0.45, -g.radius * 0.75)), ink);
    });
  });

  group('ReactionChipsRow', () {
    ChatMessage reacted(List<(String, String)> reactions) => ChatMessage(
          id: 'msg-1',
          senderDeviceId: 'device-peer',
          sentAt: DateTime.utc(2026, 4, 1, 9),
          envelope: const CryptoEnvelope(
            version: 'veil-envelope-v2',
            conversationId: 'conv-1',
            senderDeviceId: 'device-peer',
            recipientUserId: 'user-local',
            ciphertext: 'opaque',
            nonce: 'nonce',
            messageKind: MessageKind.text,
          ),
          reactions: [
            for (final (emoji, userId) in reactions)
              Reaction(messageId: 'msg-1', userId: userId, emoji: emoji, createdAt: DateTime.utc(2026, 4, 1, 9, 1)),
          ],
        );

    testWidgets('groups reactions by emoji, most used first, counts from two, and marks this user\'s',
        (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(_app(ReactionChipsRow(
        message: reacted([('👍', 'user-a'), ('❤️', 'user-b'), ('❤️', 'user-local')]),
        myUserId: 'user-local',
        onChipTap: tapped.add,
      )));

      final texts = tester
          .widgetList<Text>(find.descendant(of: find.byType(Wrap), matching: find.byType(Text)))
          .map((text) => text.data)
          .toList();
      // A single reaction shows its emoji alone, as WhatsApp's does.
      expect(texts, ['❤️', '2', '👍']);

      final palette = tester.element(find.byType(Wrap)).veilPalette;
      Color? fillOf(String emoji) => (tester
              .widget<Container>(find.ancestor(of: find.text(emoji), matching: find.byType(Container)).first)
              .decoration as BoxDecoration)
          .color;
      expect(fillOf('❤️'), palette.primarySoft);
      expect(fillOf('👍'), palette.surfaceAlt);

      await tester.tap(find.text('👍'));
      expect(tapped, ['👍']);
    });

    testWidgets('without a signed-in user no chip is marked, and no reactions draw nothing', (tester) async {
      await tester.pumpWidget(_app(ReactionChipsRow(
        message: reacted([('👍', 'user-local')]),
        myUserId: null,
        onChipTap: (_) {},
      )));
      final palette = tester.element(find.byType(Wrap)).veilPalette;
      final chip = tester.widget<Container>(find.ancestor(of: find.text('👍'), matching: find.byType(Container)).first);
      expect((chip.decoration as BoxDecoration).color, palette.surfaceAlt);

      await tester.pumpWidget(_app(ReactionChipsRow(message: reacted([]), myUserId: 'user-local', onChipTap: (_) {})));
      expect(find.byType(Wrap), findsNothing);
    });
  });

  group('labels', () {
    test('attachments are named and drawn by their content type', () {
      expect(attachmentLabel(l10n, 'video/mp4'), 'Video');
      expect(attachmentLabel(l10n, 'audio/ogg'), 'Audio');
      expect(attachmentLabel(l10n, 'application/zip'), 'File');
      expect(attachmentIcon('video/mp4'), Icons.videocam_outlined);
      expect(attachmentIcon('audio/ogg'), Icons.audiotrack_outlined);
      expect(attachmentIcon('application/zip'), Icons.insert_drive_file_outlined);
    });

    // Changed on purpose: kilobytes were written to one place ("56.0 KB"),
    // and so was a whole number of megabytes or gigabytes ("5.0 GB").
    test('sizes and durations read in their largest whole unit', () {
      expect(formatFileSize(1023), '1023 B');
      expect(formatFileSize(57344), '56 KB');
      expect(formatFileSize(1536), '2 KB');
      expect(formatFileSize(2411724), '2.3 MB');
      expect(formatFileSize(1024 * 1024), '1 MB');
      expect(formatFileSize(5 * 1024 * 1024 * 1024), '5 GB');
      expect(formatDurationLabel(l10n, const Duration(seconds: 10)), l10n.chatDurationSeconds(10));
      expect(formatDurationLabel(l10n, const Duration(minutes: 90)), l10n.chatDurationHours(1));
      expect(formatDurationLabel(l10n, const Duration(days: 2)), l10n.chatDurationDays(2));
    });

    test('a size moves up a unit when it rounds to 1024, never "1024 KB"', () {
      expect(formatFileSize(1048064), '1 MB');
      expect(formatFileSize(1024 * 1024 - 1), '1 MB');
      expect(formatFileSize(1024 * 1024 * 1024 - 1), '1 GB');
      expect(formatFileSize(1047552), '1023 KB');
    });
  });
}
