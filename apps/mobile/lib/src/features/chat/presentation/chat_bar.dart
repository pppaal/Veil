import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

// What a chat's bar is made of: its title, its actions and its search
// field. A phone shows them in the screen's bar; the wide layout shows the
// same ones at the top of the chat's pane (see ChatPaneBar).

/// Who a chat is with: their avatar, the name with the verified mark, and
/// under it one muted line: their handle or how many are in a group, then
/// the disappearing timer while one is set ("@jonas · ⏱ 1 day"). While the
/// app has no connection the line says "Connecting…" instead (Telegram).
/// Peers never see each other online, so the line never says it.
class ChatBarTitle extends StatelessWidget {
  const ChatBarTitle({
    super.key,
    required this.title,
    required this.detail,
    required this.verified,
    required this.timerLabel,
    this.connecting = false,
    this.avatarSeed,
    this.group = false,
  });

  final String title;

  /// The handle of a 1:1 peer, or how many members a group has. Null when
  /// there is nothing to add.
  final String? detail;
  final bool verified;

  /// Whether the app is waiting for its connection to the server.
  final bool connecting;

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
    final detail = connecting ? l10n.conversationsBarConnecting : this.detail;
    final timerLabel = connecting ? null : this.timerLabel;

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
        if (detail != null || timerLabel != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              if (detail != null)
                Flexible(
                  child: Text(
                    timerLabel == null ? detail : '$detail · ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                ),
              if (timerLabel != null) ...[
                Icon(Icons.timer_outlined, size: VeilIconSize.xs, color: palette.textMuted),
                const SizedBox(width: 2),
                // The glyph says the messages disappear; the words say when.
                // A screen reader hears both.
                Text(
                  timerLabel,
                  semanticsLabel: l10n.chatTimerTooltip(timerLabel),
                  maxLines: 1,
                  style: subtitleStyle,
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

/// One entry of a chat's menu: what it says and what it does, in plain
/// text with no glyph. A [destructive] one is drawn in the danger colour;
/// [divided] puts a line above it.
class ChatMenuEntry {
  const ChatMenuEntry({
    required this.key,
    required this.label,
    required this.onSelected,
    this.destructive = false,
    this.divided = false,
  });

  /// Names the entry, uniquely within a menu: 'timer', 'mute' or 'unmute',
  /// 'report', 'block' or 'unblock'. The menu finds a tapped entry by it,
  /// and tests find its item by the key 'chat-menu-' plus this.
  final String key;
  final String label;
  final VoidCallback onSelected;
  final bool destructive;
  final bool divided;
}

/// The actions of a chat's bar, plain icon buttons: the safety number (a
/// 1:1 opens the peer's, a group the list of its members with each one's),
/// the search, and a menu with the rest ([menu]: the disappearing timer,
/// notifications, reporting and blocking).
class ChatBarActions extends StatelessWidget {
  const ChatBarActions({
    super.key,
    required this.onOpenSafetyNumbers,
    required this.onOpenSearch,
    required this.menu,
  });

  final VoidCallback onOpenSafetyNumbers;
  final VoidCallback onOpenSearch;
  final List<ChatMenuEntry> menu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final textStyle = Theme.of(context).textTheme.bodyLarge;
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
        PopupMenuButton<String>(
          key: const ValueKey('chat-menu'),
          tooltip: l10n.chatMenuTooltip,
          position: PopupMenuPosition.under,
          color: palette.surfaceRaised,
          icon: const Icon(Icons.more_vert_outlined),
          // The items were built when the menu opened; this runs with the
          // menu of the latest build. An entry is found by its key, so one
          // that changed while the menu was open (Block turned Unblock, a
          // mute ended) does nothing rather than what took its place.
          onSelected: (key) {
            for (final entry in menu) {
              if (entry.key == key) return entry.onSelected();
            }
          },
          itemBuilder: (context) => [
            for (final entry in menu) ...[
              if (entry.divided) const PopupMenuDivider(height: 1),
              PopupMenuItem<String>(
                key: ValueKey('chat-menu-${entry.key}'),
                value: entry.key,
                height: 44,
                child: Text(entry.label, style: textStyle?.copyWith(color: entry.destructive ? palette.danger : null)),
              ),
            ],
          ],
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
                  // 44 square like the field, so the field keeps its height
                  // when the button appears on the first character.
                  : IconButton(
                      tooltip: l10n.chatSearchClearTooltip,
                      onPressed: controller.clear,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(44),
                        maximumSize: const Size.square(44),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
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
