import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

// What a chat's bar is made of: its title, its actions and its search
// field. A phone shows them in the screen's bar; the wide layout shows the
// same ones at the top of the chat's pane (see ChatPaneBar).

/// Who a chat is with: the name with the verified mark, and under it one
/// line about them (online, their handle, how many are in a group) and the
/// disappearing timer when one is set.
class ChatBarTitle extends StatelessWidget {
  const ChatBarTitle({
    super.key,
    required this.title,
    required this.detail,
    required this.verified,
    required this.online,
    required this.timerLabel,
  });

  final String title;

  /// The line under the title when the peer is not online: their handle, or
  /// how many members a group has. Null when there is nothing to add.
  final String? detail;
  final bool verified;
  final bool online;

  /// The disappearing timer in force, or null when messages stay.
  final String? timerLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted, height: 1.2);
    final presence = online ? l10n.chatSubtitleOnline : detail;

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
                if (presence != null) const SizedBox(width: VeilSpace.xs),
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

/// The actions of a chat's bar: the safety number (a 1:1 opens the peer's,
/// a group the list of its members with each one's), the search, and the
/// disappearing timer, lit while one is set.
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
    final palette = context.veilPalette;
    final timerOn = timerLabel != null;
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
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: l10n.chatTimerTooltip(timerLabel ?? l10n.chatTtlOff),
          onPressed: onPickTimer,
          style: timerOn
              ? IconButton.styleFrom(
                  foregroundColor: palette.warning,
                  backgroundColor: palette.warning.withValues(alpha: 0.14),
                )
              : null,
          icon: Icon(timerOn ? Icons.timer_rounded : Icons.timer_outlined),
        ),
      ],
    );
  }
}

/// The search of a chat, in its bar: the query, a spinner while the lookup
/// runs, and a button that empties the field.
class ChatBarSearchField extends StatelessWidget {
  const ChatBarSearchField({super.key, required this.controller, required this.focusNode, required this.searching});

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Whether the lookup for the current query is still running.
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

/// The bar at the top of a pane of the wide layout, as tall as the screen
/// bar of a phone and laid out like it: [leading], then the title (a text,
/// or [titleWidget] in its place), then the actions. Two panes side by side
/// read as one bar under which each has its own content.
class ChatPaneBar extends StatelessWidget {
  const ChatPaneBar({super.key, this.title, this.titleWidget, this.leading, this.actions});

  static const double height = 52;

  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Container(
      height: height,
      padding: EdgeInsets.only(
        left: leading == null ? VeilSpace.lg : VeilSpace.xxs,
        right: actions == null ? VeilSpace.lg : VeilSpace.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.stroke.withValues(alpha: 0.45), width: 0.5)),
      ),
      // One fixed height, as the screen bar: past this size its text would
      // not fit it.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: VeilSpace.xxs)],
            Expanded(
              child: titleWidget ??
                  Text(
                    title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VeilTypography.headline.copyWith(color: palette.text),
                  ),
            ),
            if (actions != null) ...[const SizedBox(width: VeilSpace.xs), ...actions!],
          ],
        ),
      ),
    );
  }
}
