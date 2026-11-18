import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/attachment_media_service.dart';
import '../../conversations/data/messenger_providers.dart';
import '../data/attachment_decrypt.dart' show isDrawablePhoto;
import '../data/attachment_opener.dart';
import '../domain/attachment_rules.dart';
import 'photo_viewer_screen.dart';
import 'save_media.dart';

/// Opens a received or sent file (D28): fetched first when its blob is not
/// on the phone, decrypted into its own folder under veil_open, then shown
/// in the viewer when its bytes are a JPEG, PNG or WebP within the render
/// limits; on iOS an image or a video the viewer cannot show goes to Save
/// instead (Quick Look would offer to save it to Photos, which the app has
/// no permission for); anything else opens in another app as the type its
/// extension names. Where nothing can be handed to another app (the
/// desktop alpha, fileHandOverAvailableProvider) only a photo opens, in the
/// viewer, and anything else says this version cannot open it, before any
/// download when its name says it is no photo. Nothing is handed on when the
/// app locked, or the chat that asked went away, while the file was being
/// fetched or decrypted.
Future<void> openFileAttachment(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  required ChatMessage message,
  required AttachmentReference attachment,
  required String name,
  String? authorName,
}) async {
  final l10n = AppLocalizations.of(context);
  final media = ref.read(messengerControllerProvider).media;
  final opener = ref.read(attachmentOpenerProvider);
  final handOver = ref.read(fileHandOverAvailableProvider);
  if (!handOver && !contentTypeForName(name).startsWith('image/')) {
    showVeilToast(context, l10n.chatAttachmentCannotOpen);
    return;
  }
  // Every lock (and sign-out) bumps evictions.
  final evictions = media.evictions;
  bool locked() => media.evictions != evictions;
  final path = await media.plaintextFileFor(conversationId, attachment,
      name: name, purpose: MediaCopyPurpose.open, expiresAt: message.expiresAt);
  if (path == null) {
    // A failed or gone fetch says so on the card; a cancelled one needs no
    // words.
    if (context.mounted && !locked() && media.statusOf(conversationId, attachment).state == MediaState.ready) {
      showVeilToast(context, l10n.chatOpenFileFailed);
    }
    return;
  }
  final file = File(path);
  final List<int> head;
  Uint8List? bytes;
  try {
    // Only the head is read to tell what it is; all of it only for the viewer.
    head = await file.openRead(0, 64).fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
    if (sniffImageType(head) != null) bytes = await file.readAsBytes();
  } on FileSystemException {
    // The copy went while it was read (its message expired, or its blob was
    // taken): nothing to open. Caught here, so its path, which holds the
    // file's name, never reaches the crash log (D14).
    await media.releaseCopy(path);
    if (context.mounted && !locked()) showVeilToast(context, l10n.chatOpenFileFailed);
    return;
  }
  if (bytes != null) {
    if (await isDrawablePhoto(bytes)) {
      await media.releaseCopy(path);
      if (!context.mounted || locked()) return;
      await showPhotoViewer(
        context,
        conversationId: conversationId,
        messageId: message.id,
        attachment: attachment,
        bytes: bytes,
        title: message.isMine ? l10n.viewerSenderYou : (authorName ?? ''),
        sentAt: message.sentAt,
        expiresAt: message.expiresAt,
        fileName: name,
      );
      return;
    }
  }
  if (!handOver) {
    await media.releaseCopy(path);
    if (context.mounted && !locked()) showVeilToast(context, l10n.chatAttachmentCannotOpen);
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.iOS && isImageOrVideoForQuickLook(head, name)) {
    await media.releaseCopy(path);
    if (!context.mounted || locked()) return;
    await saveAttachment(context, ref,
        conversationId: conversationId, attachment: attachment, name: name, expiresAt: message.expiresAt);
    return;
  }
  // Last checks before the hand-over. The channel checks the lock once more
  // right before the platform call; expiry is not checked again there, but
  // an expired message's sweep deletes the copy, so it is no longer there.
  if (!context.mounted || locked() || media.isExpired(message.expiresAt)) return media.releaseCopy(path);
  final outcome = await opener.open(path, mimeType: contentTypeForName(name));
  // On Android the other app may still be reading it: the copy goes with
  // the sweep, its message's expiry, or the next start.
  if (outcome != OpenOutcome.opened) await media.releaseCopy(path);
  if (!context.mounted) return;
  if (outcome == OpenOutcome.noApp) showVeilToast(context, l10n.chatOpenFileNoApp);
  if (outcome == OpenOutcome.failed) showVeilToast(context, l10n.chatOpenFileFailed);
}
