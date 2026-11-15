import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_shell.dart';
import 'veil_ui.dart';

/// Rows that belong together. On a grouped page (a [VeilShell] with
/// `grouped: true`) they sit in a `surface` container with 16dp side
/// margins, rounded by 10; on a white page there is no container and the
/// rows run full-bleed. Either way a 0.5dp hairline separates the rows,
/// inset to the text edge ([inset]: 16, or 56/72 where rows have a leading
/// avatar). [header] and [footer] are small muted lines above and below.
class VeilGroup extends StatelessWidget {
  const VeilGroup({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.inset = VeilSpace.md,
    @Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use header.') this.label,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  /// Where the hairlines between rows start, from the group's edge.
  final double inset;

  final String? label;

  /// Whether [context] is inside a [VeilGroup]: a notice there draws as a
  /// row, without its own margin and corners.
  static bool isInside(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_VeilGroupScope>() != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final grouped = VeilShell.groupedOf(context);
    final dark = theme.brightness == Brightness.dark;
    final hairline = grouped && dark ? palette.strokeStrong : palette.stroke;
    final side = grouped ? VeilSpace.md : 0.0;
    final header = this.header ?? label;
    final textStyle = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted);

    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0)
            Padding(
              padding: EdgeInsetsDirectional.only(start: inset),
              child: Divider(height: 0.5, thickness: 0.5, color: hairline),
            ),
          child,
        ],
      ],
    );

    return _VeilGroupScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: EdgeInsets.fromLTRB(side + VeilSpace.md, VeilSpace.md, side + VeilSpace.md, 6),
              child: Semantics(header: true, child: Text(header, style: textStyle)),
            ),
          if (grouped)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: Material(
                color: palette.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VeilRadius.md)),
                child: rows,
              ),
            )
          else
            rows,
          if (footer != null)
            Padding(
              padding: EdgeInsets.fromLTRB(side + VeilSpace.md, 6, side + VeilSpace.md, VeilSpace.md),
              child: Text(footer!, style: textStyle),
            ),
        ],
      ),
    );
  }
}

class _VeilGroupScope extends InheritedWidget {
  const _VeilGroupScope({required super.child});

  @override
  bool updateShouldNotify(_VeilGroupScope oldWidget) => false;
}

/// One row of a list or a [VeilGroup]: what it is, a line under it, and
/// where it leads or what it switches.
///
/// With [onTap] and no [trailing] the row ends in a chevron: it opens
/// something. [value] is a short muted word at the end ("On", "2",
/// "@alex"); [status] is a word in a tone colour ("Verified" in green,
/// "Stale" in amber) with no fill and no border. [onSwitch] puts a switch
/// at the end and the whole row toggles it. [destructive] draws the title
/// in the danger colour, with no chevron.
///
/// [VeilRow.field] hosts a borderless text field inside a group.
class VeilRow extends StatelessWidget {
  const VeilRow({
    super.key,
    required String this.title,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.trailing,
    this.value,
    this.status,
    this.destructive = false,
    this.onTap,
    this.switchValue,
    this.onSwitch,
  })  : field = null,
        assert(onSwitch == null || switchValue != null, 'a switch row needs its value');

  /// A row holding a text field the screen builds: no fill, no border, the
  /// hint and text at the row's text edge, [title] (if any) before it.
  const VeilRow.field({
    super.key,
    required Widget this.field,
    this.title,
    this.trailing,
  })  : subtitle = null,
        subtitleWidget = null,
        leading = null,
        value = null,
        status = null,
        destructive = false,
        onTap = null,
        switchValue = null,
        onSwitch = null;

  final String? title;
  final String? subtitle;

  /// Takes the place of [subtitle]: a line that is not plain text (a
  /// handle beside a mark, say).
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;
  final String? value;
  final (String, VeilTone)? status;
  final bool destructive;
  final VoidCallback? onTap;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitch;
  final Widget? field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final field = this.field;
    if (field != null) return _buildField(context, field);

    final hasSubtitle = subtitle != null || subtitleWidget != null;
    final minHeight = leading != null ? 60.0 : (hasSubtitle ? 52.0 : 44.0);
    final isSwitch = onSwitch != null;
    final chevron = onTap != null && trailing == null && !destructive && !isSwitch;

    final trailingParts = <Widget>[
      if (value != null) Text(value!, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
      if (status != null)
        Text(
          status!.$1,
          style: theme.textTheme.labelMedium?.copyWith(color: veilToneColor(palette, status!.$2)),
        ),
      if (trailing != null) trailing!,
      if (isSwitch)
        ExcludeFocus(
          child: Switch.adaptive(value: switchValue!, onChanged: onSwitch),
        ),
      if (chevron) Icon(Icons.chevron_right, size: 20, color: palette.textSubtle),
    ];

    final tile = ListTile(
      minTileHeight: minHeight,
      leading: leading,
      title: Text(
        title!,
        style: theme.textTheme.titleMedium?.copyWith(color: destructive ? palette.danger : null),
      ),
      subtitle: !hasSubtitle
          ? null
          : subtitleWidget ??
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
              ),
      trailing: trailingParts.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, part) in trailingParts.indexed) ...[
                  if (index > 0) const SizedBox(width: VeilSpace.xs),
                  part,
                ],
              ],
            ),
      onTap: isSwitch
          ? () => onSwitch!(!switchValue!)
          : onTap == null
              ? null
              : () {
                  destructive ? VeilHaptics.medium() : VeilHaptics.light();
                  onTap!();
                },
    );
    // The row draws its own ink: on a page or in a sheet a coloured box may
    // sit between it and the nearest Material, which would hide the ink.
    final row = Material(type: MaterialType.transparency, child: tile);
    return isSwitch ? MergeSemantics(child: row) : row;
  }

  Widget _buildField(BuildContext context, Widget field) {
    final theme = Theme.of(context);
    final borderless = theme.inputDecorationTheme.copyWith(
      filled: false,
      fillColor: Colors.transparent,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 11),
      isDense: true,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
        child: Row(
          children: [
            if (title != null) ...[
              Text(title!, style: theme.textTheme.titleMedium),
              const SizedBox(width: VeilSpace.sm),
            ],
            Expanded(child: Theme(data: theme.copyWith(inputDecorationTheme: borderless), child: field)),
            if (trailing != null) ...[const SizedBox(width: VeilSpace.xs), trailing!],
          ],
        ),
      ),
    );
  }
}
