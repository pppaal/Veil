import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/presence_typing_service.dart';
import 'chat_bar.dart';
import 'disappearing_timer_sheet.dart';
import 'presence_selector.dart';

/// A chat, content first: the bar (who it is with, the verified mark, the
/// safety number, search and the disappearing timer), the warnings that ask
/// for a decision, the messages in all the height that is left, and the
/// composer.
///
/// On a phone this is the whole screen. In the wide layout the same chat
/// fills the pane beside the conversation list ([pane]): its bar sits at the
/// top of the pane and has no back button, since the list is still there.
///
/// Search opens in the bar and closes with its back button, which drops the
/// query. [banners], [messages], [typing] and [composer] are the screen's
/// own widgets; this only places them.
class ChatPhoneScaffold extends StatefulWidget {
  const ChatPhoneScaffold({
    super.key,
    required this.conversation,
    required this.title,
    required this.presence,
    required this.peerVerified,
    required this.messageTtl,
    required this.searchController,
    required this.searching,
    required this.onPickTimer,
    required this.onOpenSafetyNumbers,
    required this.banners,
    required this.messages,
    required this.typing,
    required this.composer,
    this.pane = false,
  });

  final ConversationPreview? conversation;

  /// What the conversation is called (see conversationTitle).
  final String title;
  final PresenceTypingService presence;

  /// Whether every pinned device of the 1:1 peer was verified out of band.
  final bool peerVerified;

  /// The disappearing timer in force; null when messages stay.
  final Duration? messageTtl;
  final TextEditingController searchController;

  /// Whether the lookup for the current query is still running.
  final bool searching;
  final VoidCallback onPickTimer;
  final VoidCallback onOpenSafetyNumbers;
  final Widget banners;
  final Widget messages;
  final Widget typing;

  final Widget composer;

  /// Whether the chat is the second pane of the wide layout, not a screen.
  final bool pane;

  /// The widest a chat's messages and composer get in a pane: beyond it a
  /// line of bubbles would leave the middle of the pane empty.
  static const double paneContentWidth = 760;

  @override
  State<ChatPhoneScaffold> createState() => _ChatPhoneScaffoldState();
}

class _ChatPhoneScaffoldState extends State<ChatPhoneScaffold> {
  bool _searchOpened = false;
  final _searchFocus = FocusNode();

  // A query that arrived with the screen (a jump from the archive search)
  // shows its field too.
  bool get _searchOpen => _searchOpened || widget.searchController.text.trim().isNotEmpty;

  @override
  void didUpdateWidget(covariant ChatPhoneScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation?.id != widget.conversation?.id) _searchOpened = false;
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searchOpened = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    widget.searchController.clear();
    _searchFocus.unfocus();
    setState(() => _searchOpened = false);
  }

  void _leave() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      // Opened as the first screen (a notification, a restored session).
      GoRouter.maybeOf(context)?.go('/conversations');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final conversation = widget.conversation;
    final isDirect = conversation?.type == ConversationType.direct;
    final peerUserId = conversation?.recipientBundle.userId;
    final timerLabel = widget.messageTtl == null ? null : disappearingTimerLabel(l10n, widget.messageTtl);
    // A 1:1 names the peer's handle under their name; a group says how many
    // are in it.
    final detail = conversation == null
        ? null
        : isDirect
            ? (conversation.peerDisplayName == null ? null : '@${conversation.peerHandle}')
            : l10n.chatGroupMemberCount(conversation.members.length);

    final Widget? leading = _searchOpen
        ? VeilBackButton(onPressed: _closeSearch)
        : widget.pane
            ? null
            : VeilBackButton(onPressed: _leave);
    final Widget title = _searchOpen
        ? ChatBarSearchField(
            controller: widget.searchController,
            focusNode: _searchFocus,
            searching: widget.searching,
          )
        : PresenceSelector<bool>(
            presence: widget.presence,
            select: (presence) => isDirect && peerUserId != null && presence.isUserOnline(peerUserId),
            builder: (context, online) => ChatBarTitle(
              title: widget.title,
              detail: detail,
              verified: isDirect && widget.peerVerified,
              online: online,
              timerLabel: timerLabel,
              // A group has no handle of its own: its id stands in.
              avatarSeed: conversation == null ? null : (isDirect ? conversation.peerHandle : conversation.id),
              group: conversation != null && !isDirect,
            ),
          );
    final actions = _searchOpen
        ? null
        : [
            ChatBarActions(
              timerLabel: timerLabel,
              onOpenSafetyNumbers: widget.onOpenSafetyNumbers,
              onOpenSearch: _openSearch,
              onPickTimer: widget.onPickTimer,
            ),
          ];

    final body = Column(
      children: [
        // The composer takes what it needs first; the warnings and the
        // messages share the rest.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: _warningsMaxHeight(constraints.maxHeight)),
                  child: widget.banners,
                ),
                Expanded(child: widget.messages),
              ],
            ),
          ),
        ),
        widget.typing,
        // The composer strip runs the full width, over its own hairline.
        widget.composer,
      ],
    );

    if (!widget.pane) {
      return VeilShell(padding: EdgeInsets.zero, leading: leading, titleWidget: title, actions: actions, child: body);
    }
    // A pane brings its own material for its fields and ink: it does not
    // count on what it is placed in.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          ChatPaneBar(leading: leading, titleWidget: title, actions: actions),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: ChatPhoneScaffold.paneContentWidth),
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Warnings never push the messages off the screen: the messages keep
  /// room for a short one (96 px, or most of what is left when even that is
  /// scarce). Given less than they need, the warnings show as one row each
  /// (see ChatStatusBanners).
  static double _warningsMaxHeight(double available) => math.max(available - 96, available * 0.4);
}
