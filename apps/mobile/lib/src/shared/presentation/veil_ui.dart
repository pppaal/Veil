import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_avatar.dart';
import 'veil_group.dart';
import 'veil_notice.dart';

export 'veil_avatar.dart';
export 'veil_bubble.dart';
export 'veil_composer.dart';
export 'veil_group.dart';
export 'veil_notice.dart';

// The shared widgets (docs/mobile-design-system.md, section 7): VeilShell
// (veil_shell.dart), VeilGroup and VeilRow, VeilButton, VeilAvatar,
// VeilNotice, VeilBubble, VeilComposer and VeilEmptyState, with the helpers
// VeilHaptics, VeilFirstThatFits and showVeilToast. Everything marked
// @Deprecated below is the previous pass's widget flattened to the new
// look, kept so the screens compile until wave 1 moves them; W0-TOKENS
// phase 2 deletes them.

/// The tone of a notice, a status word or a toast.
enum VeilTone { info, good, warn, danger }

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilTone.')
typedef VeilBannerTone = VeilTone;

enum VeilButtonTone { primary, secondary, destructive, ghost }

extension VeilThemeContext on BuildContext {
  VeilPalette get veilPalette => VeilPalette.forBrightness(Theme.of(this).brightness);

  /// Whether the screen is as narrow as a phone held upright.
  bool get veilPhoneWidth => MediaQuery.sizeOf(this).width < 600;
}

/// The colour a [tone] is drawn in: an icon, a status word. Information
/// ([VeilTone.info]) is muted, not coloured.
Color veilToneColor(VeilPalette palette, VeilTone tone) => switch (tone) {
      VeilTone.info => palette.textMuted,
      VeilTone.good => palette.success,
      VeilTone.warn => palette.warning,
      VeilTone.danger => palette.danger,
    };

/// A button in one of four tones. The theme does the look: a filled brand
/// button, an outlined one, a text button, and a text button in the danger
/// colour for what cannot be undone. No red fill exists.
class VeilButton extends StatelessWidget {
  const VeilButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = VeilButtonTone.primary,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final VeilButtonTone tone;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: VeilIconSize.sm),
              const SizedBox(width: VeilSpace.xs),
              Flexible(child: Text(label)),
            ],
          );

    final button = switch (tone) {
      VeilButtonTone.primary => FilledButton(onPressed: _wrapHaptic(onPressed), child: child),
      VeilButtonTone.secondary => OutlinedButton(onPressed: _wrapHaptic(onPressed), child: child),
      VeilButtonTone.destructive => TextButton(
          style: TextButton.styleFrom(foregroundColor: context.veilPalette.danger),
          onPressed: _wrapHaptic(onPressed, destructive: true),
          child: child,
        ),
      VeilButtonTone.ghost => TextButton(onPressed: _wrapHaptic(onPressed), child: child),
    };

    if (!expanded) {
      return button;
    }
    return SizedBox(width: double.infinity, child: button);
  }

  VoidCallback? _wrapHaptic(VoidCallback? handler, {bool destructive = false}) {
    if (handler == null) {
      return null;
    }
    return () {
      if (destructive) {
        VeilHaptics.medium();
      } else {
        VeilHaptics.light();
      }
      handler();
    };
  }
}

/// What a screen shows where its content would be and there is none: a
/// title, one line under it and at most one button, centred in the space
/// left. [icon], if any, is a plain 40dp glyph. [compact] (above an open
/// keyboard) is the title and the button only.
class VeilEmptyState extends StatelessWidget {
  const VeilEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.action,
    this.compact = false,
  });

  /// An empty state for something that failed to load.
  const VeilEmptyState.error({
    super.key,
    required this.title,
    required this.body,
    this.action,
    this.compact = false,
  }) : icon = Icons.error_outline;

  final String title;
  final String body;
  final IconData? icon;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final titleStyle = context.veilPhoneWidth ? theme.textTheme.titleLarge : theme.textTheme.headlineMedium;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: VeilSpace.xxl, vertical: compact ? VeilSpace.sm : VeilSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact && icon != null) ...[
                Icon(icon, size: VeilIconSize.xl, color: palette.textSubtle),
                const SizedBox(height: VeilSpace.md),
              ],
              Text(title, style: titleStyle, textAlign: TextAlign.center),
              if (!compact) ...[
                const SizedBox(height: VeilSpace.xs),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (action != null) ...[
                SizedBox(height: compact ? VeilSpace.sm : VeilSpace.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilEmptyState.error.')
class VeilErrorState extends StatelessWidget {
  const VeilErrorState({super.key, required this.title, required this.body, this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => VeilEmptyState.error(title: title, body: body, action: action);
}

/// A short message at the bottom of the screen for something that just
/// happened. The tone shows only as a leading icon; information has none.
void showVeilToast(BuildContext context, String message, {VeilTone tone = VeilTone.info}) {
  final palette = context.veilPalette;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          if (tone != VeilTone.info) ...[
            Icon(VeilNotice.iconFor(tone), size: 20, color: veilToneColor(palette, tone)),
            const SizedBox(width: VeilSpace.sm),
          ],
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Deprecated: the previous pass's widgets, flattened. Deleted in phase 2.
// ---------------------------------------------------------------------------

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use Text.')
class VeilCopy extends StatelessWidget {
  const VeilCopy(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow);
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use a TextField with labelText and helperText.')
class VeilFieldBlock extends StatelessWidget {
  const VeilFieldBlock({
    super.key,
    required this.label,
    required this.child,
    this.caption,
    this.trailing,
  });

  final String label;
  final Widget child;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ignore: deprecated_member_use_from_same_package
        VeilSectionLabel(label, trailing: trailing),
        const SizedBox(height: VeilSpace.xs),
        child,
        if (caption != null) ...[
          const SizedBox(height: VeilSpace.xs),
          Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: context.veilPalette.textMuted)),
        ],
      ],
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Screens open with their control.')
class VeilHeroPanel extends StatelessWidget {
  const VeilHeroPanel({
    super.key,
    required this.title,
    required this.body,
    this.eyebrow,
    this.trailing,
    this.bottom,
  });

  /// Ignored: there are no eyebrows.
  final String? eyebrow;
  final String title;
  final String body;

  /// Ignored.
  final Widget? trailing;

  /// Ignored: it held pills.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    // An emptied ARB value (a slogan wave 1 removes) draws nothing.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) Text(title, style: theme.textTheme.headlineMedium),
        if (title.isNotEmpty && body.isNotEmpty) const SizedBox(height: VeilSpace.xs),
        if (body.isNotEmpty) Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
      ],
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilGroup.')
class VeilSurfaceCard extends StatelessWidget {
  const VeilSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VeilSpace.md),
    this.toned = false,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool toned;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Material(
      color: toned || selected ? palette.surfaceAlt : palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VeilRadius.md)),
      child: Padding(padding: padding, child: child),
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilGroup.header.')
class VeilSectionLabel extends StatelessWidget {
  const VeilSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: context.veilPalette.textMuted)),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilNotice.')
class VeilInlineBanner extends StatelessWidget {
  const VeilInlineBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = VeilTone.info,
    this.icon,
    this.dense = false,
    this.actionLabel,
    this.onAction,
  });

  final String? title;
  final String message;
  final VeilTone tone;
  final IconData? icon;
  final bool dense;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return VeilNotice(
      title: title,
      message: message,
      tone: tone,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      margin: EdgeInsets.zero,
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilNotice(dense: true).')
class VeilNoticeRow extends StatelessWidget {
  const VeilNoticeRow({
    super.key,
    required this.title,
    this.message,
    this.tone = VeilTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  /// The height of a row whose text fits one line at the default size.
  static const double minHeight = VeilNotice.denseHeight;

  final String title;
  final String? message;
  final VeilTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return VeilNotice(
      title: title,
      message: message ?? title,
      tone: tone,
      icon: icon,
      dense: true,
      actionLabel: actionLabel,
      onAction: onAction,
      margin: EdgeInsets.zero,
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. State is a word in a tone colour: VeilRow.status.')
class VeilStatusPill extends StatelessWidget {
  const VeilStatusPill({super.key, required this.label, this.tone = VeilTone.info});

  final String label;
  final VeilTone tone;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: veilToneColor(context.veilPalette, tone)),
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use a Column with SizedBox(height: 8).')
class VeilActionCluster extends StatelessWidget {
  const VeilActionCluster({super.key, required this.children, this.spacing = VeilSpace.xs});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          children[i],
        ],
      ],
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use a Row with SizedBox(width: 8).')
class VeilActionRow extends StatelessWidget {
  const VeilActionRow({super.key, required this.children, this.spacing = VeilSpace.xs});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use showVeilToast.')
class VeilToast {
  static void show(BuildContext context, {required String message, VeilTone tone = VeilTone.info}) =>
      showVeilToast(context, message, tone: tone);
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. A value that matters is one row.')
class VeilMetricStrip extends StatelessWidget {
  const VeilMetricStrip({super.key, required this.items});

  /// Ignored: nothing is drawn.
  final List<VeilMetricItem> items;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2.')
class VeilMetricItem {
  const VeilMetricItem({required this.label, required this.value});

  final String label;
  final String value;
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use plain footer text, or VeilNotice where an action exists.')
class VeilDestructiveNotice extends StatelessWidget {
  const VeilDestructiveNotice({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return VeilNotice(title: title, message: body, tone: VeilTone.danger, margin: EdgeInsets.zero);
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilRow.')
class VeilListTileCard extends StatelessWidget {
  const VeilListTileCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.subtitleWidget,
    this.eyebrow,
    this.leading,
    this.trailing,
    this.destructive = false,
    this.selected = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget? subtitleWidget;

  /// Ignored: there are no eyebrows.
  final String? eyebrow;
  final Widget? leading;
  final Widget? trailing;
  final bool destructive;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Material(
      color: selected ? palette.surfaceAlt : Colors.transparent,
      child: VeilRow(
        title: title,
        subtitle: subtitleWidget == null ? subtitle : null,
        subtitleWidget: subtitleWidget,
        leading: leading,
        trailing: trailing,
        destructive: destructive,
        onTap: onTap,
      ),
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use ConversationRow (conversations/presentation).')
class VeilConversationCard extends StatelessWidget {
  const VeilConversationCard({
    super.key,
    required this.title,
    required this.handle,
    required this.subtitle,
    required this.timestamp,
    this.expiryLabel,
    this.selected = false,
    this.meta,
    this.onTap,
    required this.semanticLabel,
    this.dense = false,
    this.titleIcon,
    this.titleIconLabel,
  });

  final String title;
  final String handle;
  final String subtitle;
  final String timestamp;
  final String? expiryLabel;
  final bool selected;
  final Widget? meta;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool dense;

  /// A group's mark: the row then shows the neutral group avatar.
  final IconData? titleIcon;
  final String? titleIconLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted);

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: selected ? palette.surfaceAlt : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: dense ? 64 : 72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.xs),
                  child: Row(
                    children: [
                      VeilAvatar(name: title, seed: handle, size: 48, group: titleIcon != null),
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
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                if (timestamp.isNotEmpty) ...[
                                  const SizedBox(width: VeilSpace.xs),
                                  Text(timestamp, style: muted),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                                ),
                                if (expiryLabel != null) ...[
                                  const SizedBox(width: VeilSpace.xs),
                                  Icon(Icons.timer_outlined, size: VeilIconSize.xs, color: palette.textMuted),
                                  const SizedBox(width: VeilSpace.xxs),
                                  Text(expiryLabel!,
                                      style: theme.textTheme.labelSmall?.copyWith(color: palette.textMuted)),
                                ],
                              ],
                            ),
                            if (meta != null) ...[const SizedBox(height: VeilSpace.xxs), meta!],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 76),
                child: Divider(height: 0.5, thickness: 0.5, color: palette.stroke),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use a 20dp CircularProgressIndicator and one line.')
class VeilLoadingBlock extends StatelessWidget {
  const VeilLoadingBlock({super.key, required this.title, required this.body});

  final String title;

  /// Ignored: one line is enough while loading.
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VeilSpace.xxl, horizontal: VeilSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: VeilSpace.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: context.veilPalette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Nothing is shown while loading.')
class VeilSkeletonLine extends StatelessWidget {
  const VeilSkeletonLine({super.key, this.width, this.height = 12});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use StepRow (device_transfer/presentation).')
class VeilStepRow extends StatelessWidget {
  const VeilStepRow({
    super.key,
    required this.step,
    required this.title,
    required this.body,
    required this.active,
    this.complete = false,
  });

  final int step;
  final String title;
  final String body;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final current = active && !complete;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: current ? palette.primary : palette.surfaceAlt,
          ),
          child: complete
              ? Icon(Icons.check, size: VeilIconSize.xs, color: palette.textMuted)
              : Text(
                  '$step',
                  style: theme.textTheme.labelMedium?.copyWith(color: current ? Colors.white : palette.textMuted),
                ),
        ),
        const SizedBox(width: VeilSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilRow with status.')
class VeilValueRow extends StatelessWidget {
  const VeilValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueTone = VeilTone.info,
    this.detail,
  });

  final String label;
  final String value;
  final VeilTone valueTone;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return VeilRow(title: label, subtitle: detail, status: (value, valueTone));
  }
}
