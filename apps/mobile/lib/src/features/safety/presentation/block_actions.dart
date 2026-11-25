import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/safety_providers.dart';
import 'safety_feedback.dart';

// Blocking and unblocking an account. Blocking asks first, in a dialog that
// says what a block does; unblocking does not: it gives back what a block
// took away. A failure says so in one line with a retry. [announce] says
// it worked as well, where nothing else on screen changes to show it (the
// contacts sheet); a chat shows it in place of its composer. Each names
// the person as the screen it was opened from does (`name`): their
// nickname, or the handle with its "@" (Signal's "Block %1$s?").

/// Asks before blocking [handle]'s account, called [name], then blocks it.
/// True once it is blocked.
Future<bool> confirmAndBlock(
  BuildContext context, {
  required String userId,
  required String handle,
  required String name,
  bool announce = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // A name and a handle are their owner's words: drawn as typed.
      title: Text(l10n.blockConfirmTitle(name)),
      content: Text(l10n.blockConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const ValueKey('block-confirm'),
          style: TextButton.styleFrom(foregroundColor: dialogContext.veilPalette.danger),
          onPressed: () {
            VeilHaptics.medium();
            Navigator.of(dialogContext).pop(true);
          },
          child: Text(l10n.blockAction),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  return blockAccount(SafetyFeedback.of(context), userId: userId, handle: handle, name: name, announce: announce);
}

/// Blocks [handle]'s account, called [name], without asking: the user
/// already said so.
Future<bool> blockAccount(
  SafetyFeedback feedback, {
  required String userId,
  required String handle,
  required String name,
  bool announce = false,
}) async {
  final l10n = feedback.l10n;
  final blocked = await feedback.read(blockedAccountsProvider).block(userId, handle: handle);
  if (!blocked) {
    feedback.say(
      l10n.blockFailed(name),
      retry: () => blockAccount(feedback, userId: userId, handle: handle, name: name, announce: announce),
    );
  } else if (announce) {
    feedback.say(l10n.blockDone(name));
  }
  return blocked;
}

/// Unblocks the account [userId], called [name].
Future<bool> unblockAccount(
  BuildContext context, {
  required String userId,
  required String name,
  bool announce = false,
}) {
  VeilHaptics.light();
  return _unblock(SafetyFeedback.of(context), userId: userId, name: name, announce: announce);
}

Future<bool> _unblock(
  SafetyFeedback feedback, {
  required String userId,
  required String name,
  required bool announce,
}) async {
  final l10n = feedback.l10n;
  final unblocked = await feedback.read(blockedAccountsProvider).unblock(userId);
  if (!unblocked) {
    feedback.say(
      l10n.unblockFailed(name),
      retry: () => _unblock(feedback, userId: userId, name: name, announce: announce),
    );
  } else if (announce) {
    feedback.say(l10n.unblockDone(name));
  }
  return unblocked;
}
