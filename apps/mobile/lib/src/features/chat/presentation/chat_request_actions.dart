import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/presentation/peer_names.dart';
import '../../safety/data/abuse_reports.dart';
import '../../safety/data/safety_providers.dart';
import '../../safety/presentation/block_actions.dart';
import '../../safety/presentation/report_sheet.dart';
import 'chat_request_bar.dart';
import 'chat_room_labels.dart';

/// What a message request offers and holds back (spec A5, A6). Until the
/// user accepts the chat, the request bar takes the composer's place, and
/// nothing that tells the other side what happened here goes out: no
/// screenshot notice, no reaction, no timer change. The screen offers none
/// of them; read receipts, typing and reactions (from the long press or a
/// chip under a message alike) are also held back by the messenger itself
/// (ReactionService). Block, Report and Leave use the routes they always
/// use, with the fields they always send.
mixin ChatRequestActions<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  String get conversationId;

  /// Whether this chat is a message request now. Read, not watched: for
  /// what a gesture or an event does.
  bool get inRequest => ref.read(contactTrustProvider).isRequest(conversationId);

  /// What takes the composer's place in a request; null in any other chat.
  /// [plainAccept] while a look-alike or claim banner is up. Called while
  /// the chat builds: it watches the trust layer and the names.
  Widget? requestComposer(ConversationPreview? conversation, {required bool plainAccept}) {
    final trust = ref.watch(contactTrustProvider);
    if (conversation == null || !trust.isRequest(conversationId)) return null;
    final l10n = AppLocalizations.of(context);
    final names = ref.watch(peerNamesProvider);
    // Read above the screen's shell, which keeps the slot out of the inset.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    if (conversation.type == ConversationType.group) {
      final localUserId = ref.read(messengerControllerProvider).localUserId;
      final title = conversationTitle(l10n, conversation, names, localUserId: localUserId);
      return ChatRequestBar(
        body: l10n.chatRequestGroupBody,
        acceptPrimary: !plainAccept,
        bottomInset: bottomInset,
        onLeave: () => unawaited(_leaveGroup(title)),
        onAccept: _accept,
      );
    }
    final userId = conversation.recipientBundle.userId;
    final handle = conversation.peerHandle;
    final name = names.peerName(conversation) ?? '@$handle';
    final known = userId.isNotEmpty && handle.isNotEmpty;
    return ChatRequestBar(
      body: l10n.chatRequestDirectBody(name),
      acceptPrimary: !plainAccept,
      bottomInset: bottomInset,
      onBlock: !known ? null : () => unawaited(confirmAndBlock(context, userId: userId, handle: handle, name: name)),
      onReport: !known
          ? null
          : () => unawaited(showReportSheet(
                context,
                ReportTarget(userId: userId, handle: handle, conversationId: conversationId, offerBlock: true),
                name: name,
              )),
      onAccept: _accept,
    );
  }

  void _accept() {
    VeilHaptics.light();
    unawaited(ref.read(contactTrustProvider).accept(conversationId));
  }

  // Asks first; on success the chat is gone from the list, so the user is
  // taken back to Chats. A failure says so and leaves the chat as it was.
  Future<void> _leaveGroup(String name) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chatLeaveGroupTitle(name)),
        content: Text(l10n.chatLeaveGroupBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const ValueKey('leave-confirm'),
            style: TextButton.styleFrom(foregroundColor: dialogContext.veilPalette.danger),
            onPressed: () {
              VeilHaptics.medium();
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(l10n.chatLeaveGroupConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final left = await ref.read(groupLeaveProvider).leave(conversationId);
    if (!mounted) return;
    if (left) {
      context.go('/conversations');
    } else {
      showVeilToast(context, l10n.chatLeaveGroupFailed);
    }
  }
}
