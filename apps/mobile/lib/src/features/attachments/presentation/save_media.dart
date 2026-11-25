import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/crypto/crypto_engine.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../chat/presentation/link_confirm_sheet.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/attachment_media_service.dart';
import '../../conversations/data/messenger_providers.dart';
import '../domain/attachment_rules.dart';
import '../data/attachment_opener.dart';

/// Asks before anything is saved outside the app, every time (D30): other
/// apps, and any cloud the user saves to, can open what is saved. True only
/// when the user chose Save.
Future<bool> confirmSave(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.chatSaveTitle),
      content: Text(l10n.chatSaveBody),
      actions: [
        TextButton(
          key: const ValueKey('save-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const ValueKey('save-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.chatSaveAction),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Saves [attachment] to the phone (D30): the dialog first, then a
/// decrypted copy under veil_open handed to the system save screen and
/// deleted as soon as that returns, then "Saved" or "Couldn't save. Try
/// again." (nothing when the user backed out). A [photo] is named by when
/// it was sent, a file by its own [name]. When the app locked, the screen
/// that asked went away, or the message expired while the copy was made,
/// nothing reaches the save screen and nothing is said. An Android app
/// (.apk, .xapk, .apks), whoever sent it, goes through the strong sheet
/// (confirmAppFile) before the dialog: every caller of Save, the
/// long-press menu's included, asks it.
Future<void> saveAttachment(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  required AttachmentReference attachment,
  required String name,
  bool photo = false,
  DateTime? expiresAt,
}) async {
  if (!photo && isAppFileName(name) && (!await confirmAppFile(context, name: name, saving: true) || !context.mounted)) {
    return;
  }
  if (!await confirmSave(context) || !context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final media = ref.read(messengerControllerProvider).media;
  final opener = ref.read(attachmentOpenerProvider);
  // Every lock (and sign-out) bumps evictions.
  final evictions = media.evictions;
  final path = await media.plaintextFileFor(conversationId, attachment,
      name: name, purpose: MediaCopyPurpose.save, photo: photo, expiresAt: expiresAt);
  // Checked with nothing awaited before the hand-over.
  if (!context.mounted || media.evictions != evictions || media.isExpired(expiresAt)) {
    if (path != null) await media.releaseCopy(path);
    return;
  }
  SaveOutcome outcome = SaveOutcome.failed;
  if (path != null) {
    try {
      outcome = await opener.save(path, fileName: p.basename(path));
    } finally {
      await media.releaseCopy(path);
    }
  }
  if (!context.mounted || outcome == SaveOutcome.canceled) return;
  showVeilToast(context, outcome == SaveOutcome.saved ? l10n.chatSaved : l10n.chatSaveFailed);
}

/// What a saved photo is called: when it was sent, on this phone's clock
/// ("photo-20260407-095201"); its extension comes from its bytes.
String photoFileName(DateTime sentAt) {
  final local = sentAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'photo-${local.year}${two(local.month)}${two(local.day)}-'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}';
}

/// The long-press menu's Save for [message] (D30), or null when there is
/// nothing to save: no photo or file that opened, a pointer this version
/// does not open, one the server no longer has, or a platform with no save
/// screen (fileHandOverAvailableProvider).
VoidCallback? mediaSaveAction(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  required ChatMessage message,
  required DecryptedMessage decrypted,
}) {
  if (!ref.read(fileHandOverAvailableProvider)) return null;
  final attachment = decrypted.attachment;
  final kind = decrypted.messageKind;
  if (!decrypted.isOk || attachment == null || (kind != MessageKind.image && kind != MessageKind.file)) return null;
  final state = ref.read(messengerControllerProvider).media.statusOf(conversationId, attachment).state;
  if (state == MediaState.unsupported || state == MediaState.gone) return null;
  final photo = kind == MessageKind.image;
  return () => unawaited(saveAttachment(
        context,
        ref,
        conversationId: conversationId,
        attachment: attachment,
        name: photo ? photoFileName(message.sentAt) : sanitizeFileName(decrypted.body),
        photo: photo,
        expiresAt: message.expiresAt,
      ));
}
