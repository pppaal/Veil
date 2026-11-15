import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

/// Rows that belong together, drawn as one card with a hairline between
/// them: a section of a settings-like screen. The [label] names the section
/// above the card; the [footer] is a note under it.
///
/// A screen of groups reads as a list, where a card per row reads as a
/// dashboard. Rows are [VeilGroupRow]s, or any widget that keeps the
/// card's own padding (a selector, say).
class VeilGroup extends StatelessWidget {
  const VeilGroup({super.key, required this.children, this.label, this.footer});

  final String? label;
  final List<Widget> children;

  /// A sentence of the app's own copy under the card.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: VeilSpace.xxs, bottom: VeilSpace.xs),
            child: Semantics(
              header: true,
              child: Text(label!, style: theme.textTheme.labelLarge?.copyWith(color: palette.textMuted)),
            ),
          ),
        Material(
          color: palette.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VeilRadius.md),
            side: BorderSide(color: palette.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, child) in children.indexed) ...[
                if (index > 0) Divider(height: 1, thickness: 0.5, indent: VeilSpace.md, color: palette.stroke),
                child,
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(VeilSpace.xxs, VeilSpace.xs, VeilSpace.xxs, 0),
            child: VeilCopy(footer!, style: theme.textTheme.bodySmall?.copyWith(color: palette.textSubtle)),
          ),
      ],
    );
  }
}

/// One row of a [VeilGroup]: what it is, a line on what it does, and where
/// it leads or what it switches.
///
/// With [onTap] and no [trailing] the row ends in a chevron: it opens
/// something. A row with a control in [trailing] (a switch) changes the
/// setting in place. [destructive] draws the icon and the title in the
/// danger colour, for an action that cannot be undone.
class VeilGroupRow extends StatelessWidget {
  const VeilGroupRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.icon,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final String title;

  /// The app's own copy under the title; its Korean words stay whole where
  /// it wraps. What a person wrote (a name, a handle) goes into
  /// [subtitleWidget] instead.
  final String? subtitle;
  final Widget? subtitleWidget;

  /// Shown before the title; [leading] takes its place (an avatar).
  final IconData? icon;
  final Widget? leading;

  /// A short word at the end of the row, before the chevron: the state the
  /// row leads to ("3 devices"), or what a tap does ("Edit").
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final accent = destructive ? palette.danger : null;
    final hasSubtitle = subtitle != null || subtitleWidget != null;

    final row = ConstrainedBox(
      // 56 px for a row with one line: a tap target with room to spare.
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.sm),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: VeilSpace.sm),
            ] else if (icon != null) ...[
              Icon(icon, size: VeilIconSize.md, color: accent ?? palette.textMuted),
              const SizedBox(width: VeilSpace.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(fontSize: 15, color: accent)),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 2),
                    subtitleWidget ??
                        VeilCopy(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            height: 1.4,
                            color: palette.textMuted,
                          ),
                        ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: VeilSpace.xs),
              Text(value!, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, color: palette.textMuted)),
            ],
            if (trailing != null) ...[
              const SizedBox(width: VeilSpace.xs),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: VeilSpace.xxs),
              Icon(Icons.chevron_right_rounded, size: VeilIconSize.md, color: palette.textSubtle),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: () {
        destructive ? VeilHaptics.medium() : VeilHaptics.light();
        onTap!();
      },
      child: row,
    );
  }
}

/// A [VeilGroupRow] that switches a setting in place. The whole row takes
/// the tap, and a screen reader hears one control: the title, the line
/// under it and whether it is on.
class VeilGroupSwitchRow extends StatelessWidget {
  const VeilGroupSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: VeilGroupRow(
        title: title,
        subtitle: subtitle,
        icon: icon,
        onTap: onChanged == null ? null : () => onChanged(!value),
        trailing: ExcludeFocus(child: Switch.adaptive(value: value, onChanged: onChanged)),
      ),
    );
  }
}
