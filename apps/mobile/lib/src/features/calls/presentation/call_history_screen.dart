import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/call_history_providers.dart';

class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({super.key});

  IconData _mediaIcon(CallMediaKind kind) {
    return switch (kind) {
      CallMediaKind.voice => Icons.phone_rounded,
      CallMediaKind.video => Icons.videocam_rounded,
    };
  }

  IconData _directionIcon(CallDirection direction, CallOutcome outcome) {
    if (outcome == CallOutcome.missed) {
      return Icons.call_missed_rounded;
    }
    return switch (direction) {
      CallDirection.incoming => Icons.call_received_rounded,
      CallDirection.outgoing => Icons.call_made_rounded,
    };
  }

  String _directionLabel(CallDirection direction, CallOutcome outcome) {
    if (outcome == CallOutcome.missed) {
      return 'Missed';
    }
    if (outcome == CallOutcome.declined) {
      return 'Declined';
    }
    if (outcome == CallOutcome.ringing) {
      return 'Ringing';
    }
    return switch (direction) {
      CallDirection.incoming => 'Incoming',
      CallDirection.outgoing => 'Outgoing',
    };
  }

  String _formatDuration(Duration? duration) {
    if (duration == null || duration.inSeconds <= 0) {
      return '';
    }
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(DateTime startedAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final callDay = DateTime(startedAt.year, startedAt.month, startedAt.day);
    final hh = startedAt.hour.toString().padLeft(2, '0');
    final mm = startedAt.minute.toString().padLeft(2, '0');
    if (callDay == today) {
      return 'Today, $hh:$mm';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (callDay == yesterday) {
      return 'Yesterday, $hh:$mm';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[startedAt.month - 1]} ${startedAt.day}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.veilPalette;
    final callsAsync = ref.watch(callHistoryProvider);

    return VeilShell(
      title: 'Calls',
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
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: VeilSpace.md),
              VeilInlineBanner(
                title: 'Call history unavailable',
                message: error.toString(),
                tone: VeilBannerTone.danger,
              ),
            ],
          ),
          data: (calls) {
            if (calls.isEmpty) {
              return ListView(
                children: const [
                  VeilEmptyState(
                    title: 'No call history',
                    body: 'Calls you make or receive will appear here.',
                    icon: Icons.phone_outlined,
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: calls.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: VeilSpace.sm),
              itemBuilder: (context, index) {
                final call = calls[index];
                final isMissed = call.outcome == CallOutcome.missed;
                final titleColor = isMissed ? palette.danger : null;
                final durationLabel = _formatDuration(call.duration);
                final subtitle =
                    '${_directionLabel(call.direction, call.outcome)}'
                    '${durationLabel.isNotEmpty ? '  \u00b7  $durationLabel' : ''}'
                    '  \u00b7  ${_formatTimestamp(call.startedAt)}';

                return VeilListTileCard(
                  title: call.counterparty,
                  subtitle: subtitle,
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
                      call.counterparty.characters.first.toUpperCase(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: titleColor ?? palette.primary,
                          ),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _directionIcon(call.direction, call.outcome),
                        size: VeilIconSize.sm,
                        color: isMissed ? palette.danger : palette.textSubtle,
                      ),
                      const SizedBox(width: VeilSpace.xs),
                      Icon(
                        _mediaIcon(call.media),
                        size: VeilIconSize.sm,
                        color: palette.textSubtle,
                      ),
                    ],
                  ),
                  onTap: () {
                    VeilToast.show(
                      context,
                      message: 'Call feature requires WebRTC integration',
                      tone: VeilBannerTone.warn,
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
