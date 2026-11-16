import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/safety_providers.dart';

// Blocking and unblocking an account. Blocking asks first, in a dialog that
// says what a block does; unblocking does not: it gives back what a block
// took away. A failure says so in one line with a retry. [announce] says
// it worked as well, where nothing else on screen changes to show it (the
// contacts sheet); a chat shows it in place of its composer.

/// Asks before blocking [handle]'s account, then blocks it. True once it
/// is blocked.
Future<bool> confirmAndBlock(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String handle,
  bool announce = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // A handle is its owner's word: drawn as typed.
      title: Text(l10n.blockConfirmTitle(handle)),
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
  return blockAccount(context, ref, userId: userId, handle: handle, announce: announce);
}

/// Blocks [handle]'s account without asking: the user already said so.
Future<bool> blockAccount(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String handle,
  bool announce = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final blocked = await ref.read(blockedAccountsProvider).block(userId, handle: handle);
  if (!context.mounted) return blocked;
  if (!blocked) {
    showVeilToast(
      context,
      l10n.blockFailed(handle),
      tone: VeilTone.warn,
      actionLabel: l10n.commonRetry,
      onAction: () {
        if (context.mounted) blockAccount(context, ref, userId: userId, handle: handle, announce: announce);
      },
    );
  } else if (announce) {
    showVeilToast(context, l10n.blockDone(handle), tone: VeilTone.good);
  }
  return blocked;
}

/// Unblocks [handle]'s account.
Future<bool> unblockAccount(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String handle,
  bool announce = false,
}) async {
  final l10n = AppLocalizations.of(context);
  VeilHaptics.light();
  final unblocked = await ref.read(blockedAccountsProvider).unblock(userId);
  if (!context.mounted) return unblocked;
  if (!unblocked) {
    showVeilToast(
      context,
      l10n.unblockFailed(handle),
      tone: VeilTone.warn,
      actionLabel: l10n.commonRetry,
      onAction: () {
        if (context.mounted) unblockAccount(context, ref, userId: userId, handle: handle, announce: announce);
      },
    );
  } else if (announce) {
    showVeilToast(context, l10n.unblockDone(handle), tone: VeilTone.good);
  }
  return unblocked;
}
