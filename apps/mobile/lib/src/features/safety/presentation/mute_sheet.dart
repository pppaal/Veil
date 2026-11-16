import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/conversation_mutes.dart';
import '../data/safety_providers.dart';
import 'safety_feedback.dart';

String muteDurationLabel(AppLocalizations l10n, MuteDuration duration) => switch (duration) {
      MuteDuration.oneHour => l10n.muteOneHour,
      MuteDuration.eightHours => l10n.muteEightHours,
      MuteDuration.oneWeek => l10n.muteOneWeek,
      MuteDuration.always => l10n.muteAlways,
    };

/// Turns [conversationId]'s notifications off for a while: a sheet with
/// how long, which mutes at a tap. The screen behind it says for how long,
/// or that it failed, with a retry.
Future<void> showMuteSheet(BuildContext context, String conversationId) async {
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
  await _mute(SafetyFeedback.of(context), conversationId, duration);
}

Future<void> _mute(SafetyFeedback feedback, String conversationId, MuteDuration duration) async {
  final l10n = feedback.l10n;
  final muted = await feedback.read(conversationMutesProvider).mute(conversationId, duration);
  if (!muted) {
    feedback.say(
      l10n.muteFailed,
      retry: () => _mute(feedback, conversationId, duration),
    );
    return;
  }
  // Said as every safety outcome is: one line of text.
  feedback.say(
    duration == MuteDuration.always ? l10n.muteDoneAlways : l10n.muteDoneFor(muteDurationLabel(l10n, duration)),
  );
}

/// Turns [conversationId]'s notifications back on.
Future<void> unmuteConversation(BuildContext context, String conversationId) {
  VeilHaptics.selection();
  return _unmute(SafetyFeedback.of(context), conversationId);
}

Future<void> _unmute(SafetyFeedback feedback, String conversationId) async {
  final l10n = feedback.l10n;
  final unmuted = await feedback.read(conversationMutesProvider).unmute(conversationId);
  if (!unmuted) {
    feedback.say(l10n.muteFailed, retry: () => _unmute(feedback, conversationId));
    return;
  }
  feedback.say(l10n.muteUndone);
}
