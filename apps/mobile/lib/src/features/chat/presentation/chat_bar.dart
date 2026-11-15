import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

// What a chat's bar is made of: its title, its actions and its search
// field. A phone shows them in the screen's bar; the wide layout shows the
// same ones at the top of the chat's pane (see ChatPaneBar).

/// Who a chat is with: their avatar, the name with the verified mark, and
/// under it one muted line about them (online, their handle, how many are
/// in a group) and the disappearing timer when one is set.
class ChatBarTitle extends StatelessWidget {
  const ChatBarTitle({
    super.key,
    required this.title,
    required this.detail,
    required this.verified,
    required this.online,
    required this.timerLabel,
    this.avatarSeed,
    this.group = false,
  });

  final String title;

  /// The line under the title when the peer is not online: their handle, or
  /// how many members a group has. Null when there is nothing to add.
  final String? detail;
  final bool verified;
  final bool online;

  /// The disappearing timer in force, or null when messages stay.
  final String? timerLabel;

  /// What the avatar's colour is drawn from (the peer's handle); no avatar
  /// when null.
  final String? avatarSeed;

  /// A group chat: the neutral group avatar.
  final bool group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted, height: 1.2);
    final presence = online ? l10n.chatSubtitleOnline : detail;

    final text = Column(
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
                style: theme.textTheme.titleLarge?.copyWith(height: 1.2),
              ),
            ),
            if (verified) ...[
              const SizedBox(width: VeilSpace.xxs),
              Tooltip(
                message: l10n.chatPeerVerified,
                child: Icon(Icons.verified, size: 16, color: palette.success, semanticLabel: l10n.chatPeerVerified),
              ),
            ],
          ],
        ),
        if (presence != null || timerLabel != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              if (presence != null)
                Flexible(child: Text(presence, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle)),
              if (timerLabel != null) ...[
                if (presence != null) const SizedBox(width: VeilSpace.xs),
                Icon(Icons.timer_outlined, size: VeilIconSize.xs, color: palette.warning),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    l10n.chatTimerTooltip(timerLabel!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );

    final seed = avatarSeed;
    if (seed == null) return text;
    return Row(
      children: [
        VeilAvatar(name: title, seed: seed, size: 32, group: group),
        const SizedBox(width: VeilSpace.xs),
        Expanded(child: text),
      ],
    );
  }
}

/// The actions of a chat's bar, plain icon buttons: the safety number (a
/// 1:1 opens the peer's, a group the list of its members with each one's),
/// the search, and the disappearing timer.
class ChatBarActions extends StatelessWidget {
  const ChatBarActions({
    super.key,
    required this.timerLabel,
    required this.onOpenSafetyNumbers,
    required this.onOpenSearch,
    required this.onPickTimer,
  });

  /// The disappearing timer in force, or null when messages stay.
  final String? timerLabel;
  final VoidCallback onOpenSafetyNumbers;
  final VoidCallback onOpenSearch;
  final VoidCallback onPickTimer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: l10n.safetyNumbersTitle,
          onPressed: onOpenSafetyNumbers,
          icon: const Icon(Icons.verified_user_outlined),
        ),
        IconButton(
          tooltip: l10n.chatSearchTooltip,
          onPressed: onOpenSearch,
          icon: const Icon(Icons.search),
        ),
        IconButton(
          tooltip: l10n.chatTimerTooltip(timerLabel ?? l10n.chatTtlOff),
          onPressed: onPickTimer,
          icon: const Icon(Icons.timer_outlined),
        ),
      ],
    );
  }
}

/// The search of a chat, in its bar: the query in a grey field, a spinner
/// while the lookup runs, and a button that empties the field.
class ChatBarSearchField extends StatelessWidget {
  const ChatBarSearchField({super.key, required this.controller, required this.focusNode, required this.searching});

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Whether the lookup for the current query is still running.
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close, size: 20),
                    ),
        ),
      ),
    );
  }
}

/// The bar at the top of a pane of the wide layout, as tall as the screen
/// bar of a phone and laid out like it: [leading], then the title (a text
/// with an optional [subtitle] under it, or [titleWidget] in its place),
/// then the actions, over a hairline. Two panes side by side read as one
/// bar under which each has its own content.
class ChatPaneBar extends StatelessWidget {
  const ChatPaneBar({super.key, this.title, this.subtitle, this.titleWidget, this.leading, this.actions});

  static const double height = 52;

  final String? title;
  final String? subtitle;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final titleText = Text(title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge);
    return Container(
      height: height,
      padding: EdgeInsets.only(
        left: leading == null ? VeilSpace.md : VeilSpace.xxs,
        right: actions == null ? VeilSpace.md : VeilSpace.xxs,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.stroke, width: 0.5)),
      ),
      // One fixed height, as the screen bar: past this size its text would
      // not fit it.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: VeilSpace.xs)],
            Expanded(
              child: titleWidget ??
                  (subtitle == null
                      ? titleText
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            titleText,
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                            ),
                          ],
                        )),
            ),
            if (actions != null) ...[const SizedBox(width: VeilSpace.xs), ...actions!],
          ],
        ),
      ),
    );
  }
}
