import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/call_history_providers.dart';

/// The calls the relay has on record for this account, newest first. This
/// build cannot place or take a call, so a row does what it can: it opens
/// the chat with that person. The line above the rows says so.
class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final callsAsync = ref.watch(callHistoryProvider);

    return VeilShell(
      title: l10n.navCalls,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(callHistoryProvider);
          await ref.read(callHistoryProvider.future);
        },
        child: callsAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: VeilSpace.xl),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (_, __) => ListView(
            children: [
              VeilInlineBanner(
                title: l10n.callsUnavailableTitle,
                message: l10n.callsUnavailableBody,
                tone: VeilBannerTone.danger,
              ),
            ],
          ),
          data: (calls) {
            if (calls.isEmpty) {
              return ListView(
                children: [
                  VeilEmptyState(
                    title: l10n.callsEmptyTitle,
                    body: l10n.callsEmptyBody,
                    icon: Icons.phone_disabled_rounded,
                  ),
                ],
              );
            }
            // The notice is the first item, so it scrolls away with the
            // rows and the list keeps the whole height.
            return ListView.separated(
              itemCount: calls.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: VeilSpace.sm),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return VeilInlineBanner(
                    dense: true,
                    icon: Icons.phone_disabled_rounded,
                    message: l10n.callsNotice,
                  );
                }
                return _CallRow(call: calls[index - 1]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _CallRow extends ConsumerWidget {
  const _CallRow({required this.call});

  final CallHistoryEntry call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final title = _title(l10n, ref);
    final isMissed = call.outcome == CallOutcome.missed;
    final duration = _formatDuration(call.duration);
    // Two phrases that each stay whole: on a narrow screen the time moves
    // to its own line instead of breaking in two.
    final outcome = duration.isEmpty ? _outcomeLabel(l10n) : '${_outcomeLabel(l10n)}  ·  $duration';
    final when = _formatTimestamp(l10n);
    final subtitleStyle = theme.textTheme.bodyMedium;

    return VeilListTileCard(
      title: title,
      subtitle: '$outcome  ·  $when',
      subtitleWidget: Wrap(
        spacing: VeilSpace.sm,
        children: [
          Text(outcome, style: subtitleStyle),
          Text(when, style: subtitleStyle),
        ],
      ),
      destructive: isMissed,
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.primarySoft,
          border: Border.all(color: palette.stroke),
        ),
        child: Text(
          title.replaceFirst('@', '').characters.first.toUpperCase(),
          style: theme.textTheme.titleMedium?.copyWith(color: isMissed ? palette.danger : palette.primary),
        ),
      ),
      // What kind of call it was. Nothing here places one.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_directionIcon, size: VeilIconSize.sm, color: isMissed ? palette.danger : palette.textSubtle),
          const SizedBox(width: VeilSpace.xs),
          Icon(
            call.media == CallMediaKind.video ? Icons.videocam_rounded : Icons.phone_rounded,
            size: VeilIconSize.sm,
            color: palette.textSubtle,
          ),
        ],
      ),
      onTap: () => context.push('/chat/${call.conversationId}'),
    );
  }

  // A person goes by the name their chat shows; a group or channel by the
  // name the relay keeps for it.
  String _title(AppLocalizations l10n, WidgetRef ref) {
    final handle = call.counterpartyHandle;
    if (handle == null) return call.counterparty ?? l10n.callsUnknownCounterparty;
    final conversation = ref.watch(messengerControllerProvider).conversationById(call.conversationId);
    return conversation?.peerDisplayName ?? '@$handle';
  }

  IconData get _directionIcon {
    if (call.outcome == CallOutcome.missed) return Icons.call_missed_rounded;
    return switch (call.direction) {
      CallDirection.incoming => Icons.call_received_rounded,
      CallDirection.outgoing => Icons.call_made_rounded,
    };
  }

  String _outcomeLabel(AppLocalizations l10n) => switch (call.outcome) {
        CallOutcome.missed => l10n.callsMissed,
        CallOutcome.declined => l10n.callsDeclined,
        CallOutcome.ringing => l10n.callsRinging,
        CallOutcome.completed => switch (call.direction) {
            CallDirection.incoming => l10n.callsIncoming,
            CallDirection.outgoing => l10n.callsOutgoing,
          },
      };

  String _formatDuration(Duration? duration) {
    if (duration == null || duration.inSeconds <= 0) return '';
    return '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(AppLocalizations l10n) {
    final startedAt = call.startedAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final callDay = DateTime(startedAt.year, startedAt.month, startedAt.day);
    final time = '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
    if (callDay == today) return l10n.callsToday(time);
    if (callDay == today.subtract(const Duration(days: 1))) return l10n.callsYesterday(time);
    return '${DateFormat.MMMd(l10n.localeName).format(startedAt)}, $time';
  }
}
