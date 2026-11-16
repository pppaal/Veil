import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../conversations/data/conversation_models.dart';
import '../../safety/data/abuse_reports.dart';
import '../../safety/data/safety_providers.dart';
import '../../safety/presentation/block_actions.dart';
import '../../safety/presentation/blocked_composer_line.dart';
import '../../safety/presentation/mute_sheet.dart';
import '../../safety/presentation/report_sheet.dart';
import 'chat_bar.dart';

/// What a chat offers to keep someone out of it: its menu (the timer,
/// muting, and in a 1:1 reporting and blocking the peer), the line that
/// takes the composer's place while the peer is blocked, and reporting a
/// message from its long-press sheet.
mixin ChatSafetyMenu<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  String get conversationId;

  /// The entries of the chat's menu. Called while the chat builds: it
  /// watches whether the chat is muted and the peer blocked.
  List<ChatMenuEntry> chatMenuEntries(ConversationPreview? conversation, {required VoidCallback onPickTimer}) {
    final l10n = AppLocalizations.of(context);
    final muted = ref.watch(conversationMutesProvider).isMuted(conversationId);
    final peer = _directPeer(conversation);
    final blocked = peer != null && ref.watch(blockedAccountsProvider).isBlocked(peer.userId);
    return [
      ChatMenuEntry(key: 'timer', label: l10n.chatTtlSheetTitle, icon: Icons.timer_outlined, onSelected: onPickTimer),
      if (muted)
        ChatMenuEntry(
          key: 'unmute',
          label: l10n.muteUnmute,
          icon: Icons.notifications_outlined,
          onSelected: () => unmuteConversation(context, conversationId),
        )
      else
        ChatMenuEntry(
          key: 'mute',
          label: l10n.muteTitle,
          icon: Icons.notifications_off_outlined,
          onSelected: () => showMuteSheet(context, conversationId),
        ),
      if (peer != null) ...[
        ChatMenuEntry(
          key: 'report',
          label: l10n.reportAction,
          icon: Icons.flag_outlined,
          onSelected: () => showReportSheet(
            context,
            ReportTarget(userId: peer.userId, handle: peer.handle, conversationId: conversationId, offerBlock: true),
          ),
        ),
        if (blocked)
          ChatMenuEntry(
            key: 'unblock',
            label: l10n.unblockAction,
            icon: Icons.block_outlined,
            onSelected: () => unblockAccount(context, userId: peer.userId, handle: peer.handle),
          )
        else
          ChatMenuEntry(
            key: 'block',
            label: l10n.blockAction,
            icon: Icons.block_outlined,
            destructive: true,
            onSelected: () => confirmAndBlock(context, userId: peer.userId, handle: peer.handle),
          ),
      ],
    ];
  }

  /// Whether [conversation] is a 1:1 with someone the user blocked: the
  /// server refuses what is sent there, reactions included.
  bool peerBlocked(ConversationPreview? conversation) {
    final peer = _directPeer(conversation);
    return peer != null && ref.read(blockedAccountsProvider).isBlocked(peer.userId);
  }

  /// What takes the composer's place in a 1:1 whose peer the user blocked;
  /// null in any other chat.
  Widget? blockedComposer(ConversationPreview? conversation) {
    final peer = _directPeer(conversation);
    if (peer == null || !ref.watch(blockedAccountsProvider).isBlocked(peer.userId)) return null;
    return BlockedComposerLine(
      onUnblock: () => unblockAccount(context, userId: peer.userId, handle: peer.handle),
    );
  }

  /// Reports [message] from its long-press sheet: the peer of a 1:1, or the
  /// member of a group who wrote it ([groupSenderUserId], as this device
  /// pinned their device). Null when it can't be reported: a message of
  /// ours, a notice this device wrote, or one whose writer is not known.
  VoidCallback? messageReport(
    ChatMessage message,
    ConversationPreview? conversation, {
    required String? Function(ChatMessage message) groupSenderUserId,
    required String? Function(ChatMessage message) groupSenderHandle,
  }) {
    if (message.isMine || message.isLocalNotice || conversation == null) return null;
    final ReportTarget target;
    final peer = _directPeer(conversation);
    if (peer != null) {
      target = ReportTarget(
        userId: peer.userId,
        handle: peer.handle,
        conversationId: conversationId,
        messageId: message.id,
        offerBlock: true,
      );
    } else if (conversation.type == ConversationType.group) {
      final userId = groupSenderUserId(message);
      final handle = groupSenderHandle(message);
      if (userId == null || handle == null) return null;
      target = ReportTarget(userId: userId, handle: handle, conversationId: conversationId, messageId: message.id);
    } else {
      return null;
    }
    return () => showReportSheet(context, target);
  }

  ({String userId, String handle})? _directPeer(ConversationPreview? conversation) {
    if (conversation == null || conversation.type != ConversationType.direct) return null;
    final userId = conversation.recipientBundle.userId;
    if (userId.isEmpty || conversation.peerHandle.isEmpty) return null;
    return (userId: userId, handle: conversation.peerHandle);
  }
}
