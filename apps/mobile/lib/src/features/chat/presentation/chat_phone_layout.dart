import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/presence_typing_service.dart';
import 'disappearing_timer_sheet.dart';
import 'presence_selector.dart';

/// A chat on a phone, content first: the bar (who it is with, the verified
/// mark, the safety number, search and the disappearing timer), the
/// warnings that ask for a decision, the messages in all the height that is
/// left, and the composer.
///
/// Search opens in the bar and closes with its back button, which drops the
/// query. [banners], [messages], [typing] and [composer] are the screen's
/// own widgets; this only places them.
class ChatPhoneScaffold extends StatefulWidget {
  const ChatPhoneScaffold({
    super.key,
    required this.conversation,
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
  });

  final ConversationPreview? conversation;
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
    final timerOn = widget.messageTtl != null;
    final palette = context.veilPalette;
    // Asked above the shell, whose body no longer knows about the keyboard.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    return VeilShell(
      padding: EdgeInsets.zero,
      leading: VeilBackButton(onPressed: _searchOpen ? _closeSearch : _leave),
      titleWidget: _searchOpen
          ? _BarSearchField(
              controller: widget.searchController,
              focusNode: _searchFocus,
              searching: widget.searching,
            )
          : PresenceSelector<bool>(
              presence: widget.presence,
              select: (presence) => isDirect && peerUserId != null && presence.isUserOnline(peerUserId),
              builder: (context, online) => ChatBarTitle(
                title: conversation?.peerDisplayName ??
                    (conversation == null ? l10n.chatTitleFallback : '@${conversation.peerHandle}'),
                handle: conversation?.peerDisplayName == null || !isDirect ? null : conversation?.peerHandle,
                verified: isDirect && widget.peerVerified,
                online: online,
                timerLabel: timerOn ? disappearingTimerLabel(l10n, widget.messageTtl) : null,
              ),
            ),
      actions: _searchOpen
          ? null
          : [
              // A 1:1 opens the peer's safety number, a group the list of
              // its members with each one's.
              IconButton(
                tooltip: l10n.safetyNumbersTitle,
                onPressed: widget.onOpenSafetyNumbers,
                icon: const Icon(Icons.verified_user_outlined),
              ),
              IconButton(
                tooltip: l10n.chatSearchTooltip,
                onPressed: _openSearch,
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: '${l10n.chatTtlSheetTitle}: '
                    '${timerOn ? disappearingTimerLabel(l10n, widget.messageTtl) : l10n.chatTtlOff}',
                onPressed: widget.onPickTimer,
                style: timerOn
                    ? IconButton.styleFrom(
                        foregroundColor: palette.warning,
                        backgroundColor: palette.warning.withValues(alpha: 0.14),
                      )
                    : null,
                icon: Icon(timerOn ? Icons.timer_rounded : Icons.timer_outlined),
              ),
            ],
      child: Column(
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
          Padding(
            // Right above the keyboard the composer needs less room under
            // it, and the messages and warnings need every pixel.
            padding: EdgeInsets.fromLTRB(VeilSpace.xs, VeilSpace.xs, VeilSpace.xs, keyboardUp ? VeilSpace.xxs : VeilSpace.xs),
            child: widget.composer,
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

/// Who a phone chat is with: the name with the verified mark, and under it
/// whether they are online, their handle, and the disappearing timer when
/// one is set.
class ChatBarTitle extends StatelessWidget {
  const ChatBarTitle({
    super.key,
    required this.title,
    required this.handle,
    required this.verified,
    required this.online,
    required this.timerLabel,
  });

  final String title;

  /// The peer's handle, when the title is their display name.
  final String? handle;
  final bool verified;
  final bool online;

  /// The disappearing timer in force, or null when messages stay.
  final String? timerLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted, height: 1.2);
    final presence = online ? l10n.chatSubtitleOnline : (handle == null ? null : '@$handle');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VeilTypography.headline.copyWith(color: palette.text, height: 1.2),
              ),
            ),
            if (verified) ...[
              const SizedBox(width: VeilSpace.xxs),
              Tooltip(
                message: l10n.chatPeerVerified,
                child: Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: palette.success,
                  semanticLabel: l10n.chatPeerVerified,
                ),
              ),
            ],
          ],
        ),
        if (presence != null || timerLabel != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              if (online) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: palette.success, shape: BoxShape.circle),
                ),
                const SizedBox(width: VeilSpace.xxs),
              ],
              if (presence != null)
                Flexible(
                  child: Text(
                    presence,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: online ? subtitleStyle?.copyWith(color: palette.success) : subtitleStyle,
                  ),
                ),
              if (timerLabel != null) ...[
                if (presence != null) Text('  ·  ', style: subtitleStyle),
                Icon(Icons.timer_outlined, size: 12, color: palette.warning),
                const SizedBox(width: 2),
                Text(timerLabel!, maxLines: 1, style: subtitleStyle?.copyWith(color: palette.warning)),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _BarSearchField extends StatelessWidget {
  const _BarSearchField({required this.controller, required this.focusNode, required this.searching});

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.sm),
          border: _border(palette.stroke),
          enabledBorder: _border(palette.stroke),
          focusedBorder: _border(palette.strokeStrong),
          hintText: l10n.chatSearchHint,
          suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: searching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.chatSearchClearTooltip,
                      style: IconButton.styleFrom(backgroundColor: Colors.transparent),
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
        ),
      ),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(VeilRadius.pill),
        borderSide: BorderSide(color: color),
      );
}
