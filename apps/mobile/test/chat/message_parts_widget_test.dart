import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_labels.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_attachment_views.dart';
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
    testWidgets('names the kind and size of the file and asks for a download ticket', (tester) async {
      var resolved = 0;
      await tester.pumpWidget(_app(MessageAttachmentCard(
        attachment: _reference('application/pdf', 3 * 1024 * 1024),
        resolving: false,
        downloadError: null,
        onResolve: () => resolved++,
      )));

      expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);
      expect(find.text('Encrypted document'), findsOneWidget);
      expect(find.text('3.0 MB · application/pdf'), findsOneWidget);
      expect(find.text(l10n.chatAttachmentTicketFailed), findsNothing);
      expect(find.text(l10n.chatRetrySend), findsNothing);

      await tester.tap(find.text(l10n.chatAttachmentResolveAction));
      expect(resolved, 1);
    });

    testWidgets('while a ticket resolves it cannot be asked for again; a refusal and a failed send show',
        (tester) async {
      var resolved = 0;
      var retried = 0;
      await tester.pumpWidget(_app(MessageAttachmentCard(
        attachment: _reference('image/png', 512),
        resolving: true,
        downloadError: 'ticket refused',
        onResolve: () => resolved++,
        onRetry: () => retried++,
      )));

      expect(find.text('Encrypted image'), findsOneWidget);
      expect(find.text('512 B · image/png'), findsOneWidget);
      final resolve = tester.widget<VeilButton>(find.widgetWithText(VeilButton, l10n.chatAttachmentResolvingAction));
      expect(resolve.onPressed, isNull);
      expect(find.text(l10n.chatAttachmentTicketFailed), findsOneWidget);
      expect(find.text('ticket refused'), findsOneWidget);

      await tester.tap(find.text(l10n.chatRetrySend));
      expect(retried, 1);
      expect(resolved, 0);
    });
  });

  group('AttachmentTransferPanel', () {
    testWidgets('an upload in flight shows its file, phase and progress, and cancel only where offered',
        (tester) async {
      var canceled = 0;
      await tester.pumpWidget(_app(AttachmentTransferPanel(
        snapshot: _transfer(AttachmentTransferPhase.uploading,
            progress: 0.42, filename: 'scan.pdf', contentType: 'application/pdf'),
        onCancel: () => canceled++,
      )));

      expect(find.text('scan.pdf'), findsOneWidget);
      expect(find.text(l10n.chatPhaseUploading), findsOneWidget);
      expect(find.text(l10n.chatPhaseDescUploading), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(_progressValue(tester), 0.42);
      expect(find.text(l10n.chatRetryUpload), findsNothing);
      expect(find.text(l10n.chatAttachmentStateBanner), findsNothing);

      await tester.tap(find.text(l10n.chatCancelAction));
      expect(canceled, 1);
    });

    testWidgets('a failed upload of an unnamed file says what failed and offers a retry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(_app(AttachmentTransferPanel(
        snapshot: _transfer(AttachmentTransferPhase.failed,
            progress: 0.6, contentType: 'image/jpeg', errorMessage: 'upload refused'),
        onRetry: () => retried++,
      )));

      expect(find.text('Encrypted image'), findsOneWidget);
      expect(find.text(l10n.chatPhaseFailed), findsOneWidget);
      // The error is the description and the banner's message.
      expect(find.text('upload refused'), findsNWidgets(2));
      expect(find.text(l10n.chatAttachmentStateBanner), findsOneWidget);
      expect(_progressValue(tester), 0.6);
      expect(find.text(l10n.chatCancelAction), findsNothing);

      await tester.tap(find.text(l10n.chatRetryUpload));
      expect(retried, 1);
    });

    testWidgets('a staged upload states its size; preparing and finalizing have no fixed progress',
        (tester) async {
      await tester.pumpWidget(_app(AttachmentTransferPanel(
        snapshot: _transfer(AttachmentTransferPhase.staged, sizeBytes: 512),
      )));
      expect(find.text(l10n.chatPhaseDescStaged(' 512 bytes.')), findsOneWidget);
      expect(find.text('Encrypted file'), findsOneWidget);
      expect(_progressValue(tester), 0);
      expect(find.byType(VeilButton), findsNothing);

      for (final phase in [AttachmentTransferPhase.preparing, AttachmentTransferPhase.finalizing]) {
        await tester.pumpWidget(_app(AttachmentTransferPanel(snapshot: _transfer(phase, progress: 0.5))));
        expect(_progressValue(tester), isNull, reason: '$phase');
      }
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

    testWidgets('groups reactions by emoji, most used first, and marks the ones this user added to',
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
      expect(texts, ['❤️', '2', '👍', '1']);

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
      expect(attachmentLabel(l10n, 'video/mp4'), 'Encrypted video');
      expect(attachmentLabel(l10n, 'audio/ogg'), 'Encrypted audio');
      expect(attachmentLabel(l10n, 'application/zip'), 'Encrypted file');
      expect(attachmentIcon('video/mp4'), Icons.videocam_rounded);
      expect(attachmentIcon('audio/ogg'), Icons.audiotrack_rounded);
      expect(attachmentIcon('application/zip'), Icons.insert_drive_file_rounded);
    });

    test('sizes and durations read in their largest whole unit', () {
      expect(formatFileSize(1023), '1023 B');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(5 * 1024 * 1024 * 1024), '5.0 GB');
      expect(formatDurationLabel(l10n, const Duration(seconds: 10)), l10n.chatDurationSeconds(10));
      expect(formatDurationLabel(l10n, const Duration(minutes: 90)), l10n.chatDurationHours(1));
      expect(formatDurationLabel(l10n, const Duration(days: 2)), l10n.chatDurationDays(2));
    });

    test('with the relay down, the banner names what waits, failed sends first', () {
      String recovery({int failed = 0, int queued = 0, int uploading = 0}) => networkRecoveryMessage(
            l10n: l10n,
            failedCount: failed,
            queuedCount: queued,
            uploadingCount: uploading,
            nextRetryAt: null,
          );
      expect(recovery(failed: 1, queued: 2, uploading: 3), l10n.chatNetworkRecoveryFailed(1, l10n.chatRetryResumes));
      expect(recovery(queued: 2, uploading: 3), l10n.chatNetworkRecoveryUploading(3, l10n.chatRetryResumes));
      expect(recovery(queued: 2), l10n.chatNetworkRecoveryQueued(2, l10n.chatRetryResumes));
    });
  });
}
