import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';

// How the messages of a chat are laid out in runs and days (see
// ChatMessageList), and the small pieces the message area draws between
// and instead of them: the date above a day, and the loading line.

/// How far apart one sender's messages may be and still share a run.
const Duration chatRunWindow = Duration(minutes: 5);

/// Whether [message] is a reaction by its envelope: a reaction shows on its
/// target, not as a row, so the bubbles around it are neighbours. The
/// envelope's kind is the relay's word, so this only decides spacing; what
/// is drawn is decided by the decrypted kind.
bool chatReactionHint(ChatMessage message) => message.envelope.messageKind == MessageKind.reaction;

/// Whether [later] continues the run of [earlier]: the same sender, the
/// same day, within [chatRunWindow], with nothing between them (a notice,
/// or reactions under the earlier one, end a run). Like [chatReactionHint],
/// the envelope's word that a message is a notice only decides spacing.
bool sameChatRun(ChatMessage earlier, ChatMessage later) =>
    earlier.isMine == later.isMine &&
    earlier.senderDeviceId == later.senderDeviceId &&
    !earlier.isLocalNotice &&
    !later.isLocalNotice &&
    earlier.envelope.messageKind != MessageKind.system &&
    later.envelope.messageKind != MessageKind.system &&
    earlier.reactions.isEmpty &&
    sameChatDay(earlier.sentAt, later.sentAt) &&
    later.sentAt.difference(earlier.sentAt).abs() <= chatRunWindow;

/// Whether [a] and [b] fall on the same day where the phone is. With
/// [now], a day after now's counts as now's: a message stamped later than
/// this phone's clock reads is under "Today" (chatDayLabel), with today's,
/// not under a second "Today".
bool sameChatDay(DateTime a, DateTime b, {DateTime? now}) {
  final today = now == null ? null : DateTime(now.year, now.month, now.day);
  DateTime dayOf(DateTime at) {
    final local = at.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    return today != null && day.isAfter(today) ? today : day;
  }

  return dayOf(a) == dayOf(b);
}

/// What the message area shows while the history is on its way: a small
/// spinner and one line.
class ChatLoadingState extends StatelessWidget {
  const ChatLoadingState({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    // A spinner alone; [label] is what a screen reader hears.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VeilSpace.xxl),
        child: Semantics(
          label: label,
          child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
    );
  }
}

/// The date above the first message of a day, centred in small muted type
/// with no line: "Today", "Yesterday", a weekday within the week, then the
/// date.
class ChatDayDivider extends StatelessWidget {
  const ChatDayDivider({super.key, required this.day, required this.now, this.first = false});

  final DateTime day;

  /// The time on the phone's clock (wallClockProvider), which [day] is
  /// said relative to.
  final DateTime now;

  /// The first thing in the list, which needs less space above it.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? VeilSpace.xs : VeilSpace.md, bottom: VeilSpace.md),
      child: Semantics(
        header: true,
        child: Text(
          chatDayLabel(l10n, day, now: now),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.veilPalette.textMuted,
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
    );
  }
}

/// The words for the day of [day] as seen on [now]: "Today", "Yesterday",
/// the weekday for the six days before, the month and day this year, and
/// the full date before that. A message stamped later than this phone's
/// clock reads (a clock behind the server's) is under "Today", as its row in
/// Chats shows its time (MessageTimeFormat.listDate).
String chatDayLabel(AppLocalizations l10n, DateTime day, {required DateTime now}) {
  final local = day.toLocal();
  final date = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final daysAgo = (today.difference(date).inHours / 24).round();
  if (daysAgo <= 0) return l10n.chatDayToday;
  if (daysAgo == 1) return l10n.chatDayYesterday;
  if (daysAgo > 1 && daysAgo < 7) return DateFormat.EEEE(l10n.localeName).format(local);
  if (local.year == now.year) return DateFormat.MMMMd(l10n.localeName).format(local);
  return DateFormat.yMMMMd(l10n.localeName).format(local);
}
