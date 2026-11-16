import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_first_fit.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/conversation_peer_bindings.dart';
import '../../conversations/data/veil_messenger_controller.dart';

/// What sits between a chat's bar and its messages: a banner only while the
/// user has to decide something (an identity change or held account that
/// pauses the 1:1, a key change of the peer's that waits in another chat),
/// each with its action inside it. A send that failed says so on its
/// bubble, the connection is the bar's subtitle and an error is a toast, as
/// in Signal: a quiet chat shows nothing here.
///
/// Given less height than its notices need, it shows each warning as one
/// full-bleed row (title and action), and only when even those do not fit
/// do the rows scroll.
class ChatStatusBanners extends StatelessWidget {
  const ChatStatusBanners({
    super.key,
    required this.controller,
    required this.conversationId,
    required this.conversation,
    required this.onReviewIdentity,
    required this.onAcknowledgeHold,
  });

  final VeilMessengerController controller;
  final String conversationId;
  final ConversationPreview? conversation;
  final VoidCallback onReviewIdentity;
  final void Function(PeerAccountHold hold, String handle) onAcknowledgeHold;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notices = _notices(l10n);
    if (notices.isEmpty) return const SizedBox.shrink();
    return VeilFirstThatFits(
      children: [
        // A gap under the last notice as over the first: a message scrolled
        // up to the notices stops short of them and never touches one (a
        // grey bubble cut off under a grey notice reads as one shape).
        Padding(
          padding: const EdgeInsets.symmetric(vertical: VeilSpace.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, notice) in notices.indexed) ...[
                if (index > 0) const SizedBox(height: VeilSpace.xs),
                VeilNotice(
                  title: notice.title,
                  message: notice.message,
                  tone: notice.tone,
                  dense: notice.oneLine,
                  actionLabel: notice.actionLabel,
                  onAction: notice.onAction,
                ),
              ],
            ],
          ),
        ),
        // With the keyboard up on a small phone the notices above would be
        // cut off, the action of the first among them: each warning then
        // keeps its title and its action in one row. A strip of page under
        // the rows, outside their scrolling, keeps the messages off them.
        Padding(
          padding: const EdgeInsets.only(bottom: VeilSpace.xxs),
          child: _ScrollingRows(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VeilGroup(
                  // Grey rows edge to edge: a line that started at the text
                  // would leave a notch of page colour at the start.
                  inset: 0,
                  children: [
                    for (final notice in notices)
                      VeilNotice(
                        dense: true,
                        title: notice.title,
                        message: notice.message,
                        tone: notice.tone,
                        actionLabel: notice.actionLabel,
                        onAction: notice.onAction,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The warnings, most pressing first.
  List<_Notice> _notices(AppLocalizations l10n) {
    final conversation = this.conversation;
    final isDirect = conversation?.type == ConversationType.direct;
    final accountHold = isDirect ? controller.peerAccountHoldFor(conversationId) : null;
    final changeHere = isDirect && controller.pendingIdentityChangeFor(conversationId) != null;
    // The peer presented another key in a conversation they share with the
    // user (a group), which holds it for review. This 1:1 still talks to
    // the key it pinned, and says where the question is open.
    final changeElsewhere = conversation != null &&
        isDirect &&
        !changeHere &&
        controller.pendingIdentityChangeAbout(conversation.recipientBundle.userId) != null;

    return [
      // Only a 1:1 conversation pauses; a group just leaves the device out.
      if (changeHere)
        _Notice(
          title: l10n.chatIdentityChangedTitle,
          message: l10n.chatIdentityChangedBody,
          tone: VeilTone.warn,
          actionLabel: l10n.chatIdentityChangedReview,
          onAction: onReviewIdentity,
        ),
      // One line and its action: the decision waits in the group.
      if (changeElsewhere)
        _Notice(
          title: null,
          message: l10n.chatIdentityChangedElsewhereTitle,
          tone: VeilTone.warn,
          oneLine: true,
          actionLabel: l10n.chatIdentityChangedReview,
          onAction: onReviewIdentity,
        ),
      // Listed under a handle this device knows as another account, under
      // the user's own handle as another account, or under one no honest
      // relay issues: nothing is sent or opened until the user says this is
      // the account they want to talk to.
      if (accountHold != null)
        _Notice(
          title: switch (accountHold.reason) {
            PeerAccountHoldReason.otherAccount => l10n.chatAccountHoldOtherTitle,
            PeerAccountHoldReason.unissuedHandle => l10n.chatAccountHoldUnissuedTitle,
            PeerAccountHoldReason.ownHandle => l10n.chatAccountHoldOwnTitle,
          },
          message: switch (accountHold.reason) {
            PeerAccountHoldReason.otherAccount =>
              l10n.chatAccountHoldOtherBody(accountHold.known?.handle ?? conversation?.peerHandle ?? ''),
            PeerAccountHoldReason.unissuedHandle => l10n.chatAccountHoldUnissuedBody,
            PeerAccountHoldReason.ownHandle => l10n.chatAccountHoldOwnBody(conversation?.peerHandle ?? ''),
          },
          tone: VeilTone.warn,
          actionLabel: l10n.chatAccountHoldAcknowledge,
          onAction: () => onAcknowledgeHold(accountHold, conversation?.peerHandle ?? ''),
        ),
    ];
  }
}

/// The one-row warnings in the height they are given: they scroll, under a
/// scrollbar that stays in view, when there are more than fit.
class _ScrollingRows extends StatefulWidget {
  const _ScrollingRows({required this.child});

  final Widget child;

  @override
  State<_ScrollingRows> createState() => _ScrollingRowsState();
}

class _ScrollingRowsState extends State<_ScrollingRows> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(controller: _scroll, child: widget.child),
    );
  }
}

class _Notice {
  const _Notice({
    required this.title,
    required this.message,
    required this.tone,
    this.oneLine = false,
    this.actionLabel,
    this.onAction,
  });

  /// Null for a notice whose one line says it all.
  final String? title;
  final String message;
  final VeilTone tone;

  /// Drawn as one row even with room for more.
  final bool oneLine;
  final String? actionLabel;
  final VoidCallback? onAction;
}
