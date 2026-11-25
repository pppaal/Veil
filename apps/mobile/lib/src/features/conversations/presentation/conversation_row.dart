import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

/// One chat in the Chats list: a full-bleed 72dp row (64 [dense]) with the
/// avatar, the name and the time on the first line, and the last message
/// with the unread count or the timer glyph on the second. An unread chat
/// (one with unread messages, or [markedUnread]) has its name in bold, its
/// last message in the text colour and its time in the text colour at 600,
/// as Signal draws it. A chat marked unread with nothing counted shows the
/// badge as an empty disc. A [muted] chat shows the muted glyph there, and
/// its unread count in grey ([greyBadge] greys it without the glyph, and so
/// does a message [request], which the Chats tab does not count). The
/// list puts the rows in a VeilGroup, whose hairlines start at the text edge
/// ([textInset], 76).
///
/// [semanticLabel] is what a screen reader calls the row; the avatar says
/// nothing. A long press opens the row's menu ([onLongPress]), whose actions
/// a screen reader also offers ([semanticActions]).
class ConversationRow extends StatelessWidget {
  const ConversationRow({
    super.key,
    required this.title,
    required this.seed,
    required this.snippet,
    required this.timestamp,
    required this.semanticLabel,
    this.unreadCount = 0,
    this.unreadLabel,
    this.markedUnread = false,
    this.markedUnreadLabel,
    this.snippetIcon,
    this.snippetIconAt = 0,
    this.timerLabel,
    this.muted = false,
    this.mutedLabel,
    this.greyBadge = false,
    this.request = false,
    this.group = false,
    this.selected = false,
    this.dense = false,
    this.titleIcon,
    this.titleIconLabel,
    this.onTap,
    this.onLongPress,
    this.semanticActions,
  });

  final String title;

  /// What the avatar's colour is drawn from: the handle, or a group's id.
  final String seed;

  /// The last message, or what waits to be sent.
  final String snippet;
  final String timestamp;
  final String semanticLabel;

  /// Messages not read yet; a badge shows the count when there are any.
  final int unreadCount;

  /// What a screen reader says about [unreadCount].
  final String? unreadLabel;

  /// The user marked the chat unread; a screen reader says
  /// [markedUnreadLabel] while nothing is counted.
  final bool markedUnread;
  final String? markedUnreadLabel;

  /// A glyph in [snippet], before its character at [snippetIconAt]: a photo
  /// or a file, after any "Omar: " that leads the line.
  final IconData? snippetIcon;
  final int snippetIconAt;

  /// Set when the chat's messages disappear: the row shows the timer glyph,
  /// and a screen reader says this.
  final String? timerLabel;

  /// The chat raises no notification for now; a screen reader says
  /// [mutedLabel].
  final bool muted;
  final String? mutedLabel;

  /// The unread count is grey without the muted glyph: a 1:1 whose peer is
  /// blocked.
  final bool greyBadge;

  /// A chat not accepted yet: its count is grey, as a muted chat's, and its
  /// snippet quotes nothing (conversationPreview's request).
  final bool request;

  /// A group chat: the neutral group avatar.
  final bool group;

  /// The chat open beside the list in the wide layout.
  final bool selected;

  /// The 64dp row of a narrow phone.
  final bool dense;

  /// A small glyph before the name, if any.
  final IconData? titleIcon;
  final String? titleIconLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Map<CustomSemanticsAction, VoidCallback>? semanticActions;

  /// Where the hairline under the row starts: the text edge.
  static const double textInset = VeilSpace.md + 48 + VeilSpace.sm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final counted = unreadCount > 0;
    final unread = counted || markedUnread;
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final snippetStyle = unread ? muted?.copyWith(color: palette.text) : muted;
    final label = [
      semanticLabel,
      if (counted && unreadLabel != null) unreadLabel!,
      if (!counted && markedUnread && markedUnreadLabel != null) markedUnreadLabel!,
      if (timerLabel != null) timerLabel!,
      if (this.muted && mutedLabel != null) mutedLabel!,
    ].join(', ');
    final icon = snippetIcon;
    final at = snippetIconAt.clamp(0, snippet.length);

    return Semantics(
      button: true,
      label: label,
      customSemanticsActions: semanticActions,
      child: Material(
        color: selected ? palette.surfaceAlt : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: dense ? 64 : 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.xs),
              child: Row(
                children: [
                  VeilAvatar(name: title, seed: seed, size: 48, group: group),
                  const SizedBox(width: VeilSpace.sm),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (titleIcon != null) ...[
                              Icon(titleIcon, size: 16, color: palette.textMuted, semanticLabel: titleIconLabel),
                              const SizedBox(width: VeilSpace.xxs),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: unread ? FontWeight.w700 : null,
                                ),
                              ),
                            ),
                            if (timestamp.isNotEmpty) ...[
                              const SizedBox(width: VeilSpace.xs),
                              Text(
                                timestamp,
                                style: unread ? muted?.copyWith(color: palette.text, fontWeight: FontWeight.w600) : muted,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (icon != null && at == 0) ...[
                              Icon(icon, size: 16, color: palette.textMuted),
                              const SizedBox(width: VeilSpace.xxs),
                            ],
                            Expanded(
                              child: icon == null || at == 0
                                  ? Text(snippet, maxLines: 1, overflow: TextOverflow.ellipsis, style: snippetStyle)
                                  : Text.rich(
                                      TextSpan(children: [
                                        TextSpan(text: snippet.substring(0, at)),
                                        WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsetsDirectional.only(end: VeilSpace.xxs),
                                            child: Icon(icon, size: 16, color: palette.textMuted),
                                          ),
                                        ),
                                        TextSpan(text: snippet.substring(at)),
                                      ]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: snippetStyle,
                                    ),
                            ),
                            if (timerLabel != null) ...[
                              const SizedBox(width: VeilSpace.xs),
                              Icon(Icons.timer_outlined, size: VeilIconSize.xs, color: palette.textMuted),
                            ],
                            if (this.muted) ...[
                              const SizedBox(width: VeilSpace.xs),
                              Icon(Icons.notifications_off_outlined, size: VeilIconSize.xs, color: palette.textMuted),
                            ],
                            if (unread) ...[
                              const SizedBox(width: VeilSpace.xs),
                              // The row's label says it in words.
                              ExcludeSemantics(
                                child: UnreadBadge(count: counted ? unreadCount : null, muted: this.muted || greyBadge || request),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The count of unread messages: a brand pill, at least 20x20, with the
/// number in white ("999+" past 999). A [muted] chat's is grey: the muted
/// text colour with the number in the page colour, the pair body text has
/// the other way round. With no [count] it is a 20x20 disc with no number:
/// a chat the user marked unread.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, this.muted = false});

  final int? count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
          color: muted ? palette.canvas : Colors.white,
        );
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? palette.textMuted : palette.primary,
        borderRadius: BorderRadius.circular(VeilRadius.pill),
      ),
      child: switch (count) {
        null => const SizedBox(width: 8, height: 20),
        final count => Text(count > 999 ? '999+' : '$count', style: style, textAlign: TextAlign.center),
      },
    );
  }
}
