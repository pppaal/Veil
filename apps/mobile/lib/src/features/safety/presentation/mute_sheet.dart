import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/conversation_mutes.dart';
import '../data/safety_providers.dart';

String muteDurationLabel(AppLocalizations l10n, MuteDuration duration) => switch (duration) {
      MuteDuration.oneHour => l10n.muteOneHour,
      MuteDuration.eightHours => l10n.muteEightHours,
      MuteDuration.oneWeek => l10n.muteOneWeek,
      MuteDuration.always => l10n.muteAlways,
    };

/// Turns [conversationId]'s notifications off for a while: a sheet with
/// how long, which mutes at a tap. The screen behind it says for how long,
/// or that it failed, with a retry.
Future<void> showMuteSheet(BuildContext context, WidgetRef ref, String conversationId) async {
  VeilHaptics.selection();
  final l10n = AppLocalizations.of(context);
  final duration = await showModalBottomSheet<MuteDuration>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: VeilSpace.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.md, 0, VeilSpace.md, VeilSpace.xs),
              child: Text(l10n.muteTitle, style: Theme.of(sheetContext).textTheme.titleLarge),
            ),
            VeilGroup(
              children: [
                for (final option in MuteDuration.values)
                  VeilRow(
                    key: ValueKey('mute-${option.name}'),
                    title: muteDurationLabel(l10n, option),
                    // A tap mutes: no row leads anywhere.
                    trailing: const SizedBox.shrink(),
                    onTap: () => Navigator.of(sheetContext).pop(option),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (duration == null || !context.mounted) return;
  await _mute(context, ref, conversationId, duration);
}

Future<void> _mute(BuildContext context, WidgetRef ref, String conversationId, MuteDuration duration) async {
  final l10n = AppLocalizations.of(context);
  final muted = await ref.read(conversationMutesProvider).mute(conversationId, duration);
  if (!context.mounted) return;
  if (!muted) {
    showVeilToast(
      context,
      l10n.muteFailed,
      tone: VeilTone.warn,
      actionLabel: l10n.commonRetry,
      onAction: () {
        if (context.mounted) _mute(context, ref, conversationId, duration);
      },
    );
    return;
  }
  showVeilToast(
    context,
    duration == MuteDuration.always ? l10n.muteDoneAlways : l10n.muteDoneFor(muteDurationLabel(l10n, duration)),
  );
}

/// Turns [conversationId]'s notifications back on.
Future<void> unmuteConversation(BuildContext context, WidgetRef ref, String conversationId) async {
  final l10n = AppLocalizations.of(context);
  VeilHaptics.selection();
  final unmuted = await ref.read(conversationMutesProvider).unmute(conversationId);
  if (!context.mounted) return;
  if (!unmuted) {
    showVeilToast(
      context,
      l10n.muteFailed,
      tone: VeilTone.warn,
      actionLabel: l10n.commonRetry,
      onAction: () {
        if (context.mounted) unmuteConversation(context, ref, conversationId);
      },
    );
    return;
  }
  showVeilToast(context, l10n.muteUndone);
}
