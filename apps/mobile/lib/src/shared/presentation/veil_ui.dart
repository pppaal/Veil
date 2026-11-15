import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';

enum VeilBannerTone { info, good, warn, danger }

enum VeilButtonTone { primary, secondary, destructive, ghost }

extension VeilThemeContext on BuildContext {
  VeilPalette get veilPalette =>
      VeilPalette.forBrightness(Theme.of(this).brightness);

  /// Whether the screen is as narrow as a phone held upright. Panels tighten
  /// and decorative tiles step aside there, so that what the screen is for
  /// stays on the first screenful.
  bool get veilPhoneWidth => MediaQuery.sizeOf(this).width < 600;
}

final _hangul = RegExp(r'[\u1100-\u11FF\u3130-\u318F\uAC00-\uD7AF]');
final _word = RegExp(r'\S+');

/// [text] for a headline, with its Korean words kept whole where it wraps.
/// A line of Korean may break between any two syllables, which leaves the
/// last syllable of a headline alone on a line ("...됩니" / "다."). A word
/// joiner goes between the characters of each word that has Hangul in it,
/// so the line breaks at spaces; a word wider than the line still breaks.
/// Text without Hangul comes back as it is.
///
/// The result is for drawing only: give the widget the plain text as its
/// semantics label.
String veilKeepWordsWhole(String text) {
  if (!_hangul.hasMatch(text)) return text;
  return text.replaceAllMapped(_word, (match) {
    final word = match[0]!;
    return _hangul.hasMatch(word) ? word.characters.join('\u2060') : word;
  });
}

/// A piece of the app's own copy (a sentence from the ARB files), drawn
/// with its Korean words kept whole where it wraps and read out as the
/// plain text. The shared cards, banners, hero and empty states draw their
/// titles and bodies with it; a screen does the same for a paragraph of its
/// own.
///
/// Never for what a person wrote (a message, a name, a note): that text is
/// theirs to copy and search as they typed it, and goes into a plain [Text].
class VeilCopy extends StatelessWidget {
  const VeilCopy(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      veilKeepWordsWhole(text),
      semanticsLabel: text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

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
      VeilButtonTone.primary => FilledButton(
          onPressed: _wrapHaptic(onPressed),
          child: child,
        ),
      VeilButtonTone.secondary => OutlinedButton(
          onPressed: _wrapHaptic(onPressed),
          child: child,
        ),
      VeilButtonTone.destructive => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.veilPalette.danger,
            foregroundColor: context.veilPalette.canvas,
          ),
          onPressed: _wrapHaptic(onPressed, destructive: true),
          child: child,
        ),
      VeilButtonTone.ghost => TextButton(
          onPressed: _wrapHaptic(onPressed),
          child: child,
        ),
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

/// Spring-scale press wrapper. On tap-down the child scales to [scale] with a
/// short responsive curve, then relaxes back to 1.0 on release. This mirrors
/// the subtle "press" feedback you feel on iOS rows, tab items, and chips.
class VeilPressable extends StatefulWidget {
  const VeilPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.haptic = true,
    this.destructive = false,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final bool destructive;
  final HitTestBehavior behavior;

  @override
  State<VeilPressable> createState() => _VeilPressableState();
}

class _VeilPressableState extends State<VeilPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 180),
    value: 0,
    lowerBound: 0,
    upperBound: 1,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: widget.scale,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: VeilMotion.springResponsive,
      reverseCurve: VeilMotion.springGentle,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() => _controller.forward();
  void _release() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled && !reduceMotion ? (_) => _press() : null,
      onTapUp: enabled && !reduceMotion ? (_) => _release() : null,
      onTapCancel: enabled && !reduceMotion ? _release : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) {
                widget.destructive ? VeilHaptics.medium() : VeilHaptics.light();
              }
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: reduceMotion
          ? widget.child
          : ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

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
    return VeilSurfaceCard(
      toned: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeilSectionLabel(label, trailing: trailing),
          const SizedBox(height: VeilSpace.sm),
          child,
          if (caption != null) ...[
            const SizedBox(height: VeilSpace.sm),
            VeilCopy(
              caption!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.veilPalette.textMuted,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class VeilHeroPanel extends StatefulWidget {
  const VeilHeroPanel({
    super.key,
    required this.title,
    required this.body,
    this.eyebrow,
    this.trailing,
    this.bottom,
  });

  final String? eyebrow;
  final String title;
  final String body;
  final Widget? trailing;
  final Widget? bottom;

  @override
  State<VeilHeroPanel> createState() => _VeilHeroPanelState();
}

class _VeilHeroPanelState extends State<VeilHeroPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Widget _staggered(int index, Widget child) {
    final start = (index * 0.12).clamp(0.0, 0.8);
    final end = (start + 0.6).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: VeilMotion.emphasize),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) {
        return Opacity(
          opacity: curve.value,
          child: Transform.translate(
            offset: Offset(0, (1 - curve.value) * 12),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    // On a phone the panel introduces the screen without taking it over.
    final compact = context.veilPhoneWidth;

    return Container(
      padding: EdgeInsets.all(compact ? VeilSpace.lg : VeilSpace.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? VeilRadius.lg : VeilRadius.xl),
        border: Border.all(color: palette.stroke),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.surfaceRaised,
            palette.surfaceAlt,
            palette.canvasAlt,
          ],
        ),
        boxShadow: VeilElevation.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.eyebrow != null) ...[
            _staggered(
              0,
              Text(
                widget.eyebrow!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: palette.primaryStrong,
                ),
              ),
            ),
            SizedBox(height: compact ? VeilSpace.sm : VeilSpace.md),
          ],
          _staggered(
            1,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VeilCopy(
                        widget.title,
                        style: compact
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.headlineLarge?.copyWith(height: 1.04),
                      ),
                      SizedBox(height: compact ? VeilSpace.xs : VeilSpace.sm),
                      VeilCopy(
                        widget.body,
                        style: (compact ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                // Sized by itself: as a flexible child it took half the row
                // from the title whatever its own width.
                if (widget.trailing != null) ...[
                  const SizedBox(width: VeilSpace.md),
                  widget.trailing!,
                ],
              ],
            ),
          ),
          if (widget.bottom != null) ...[
            SizedBox(height: compact ? VeilSpace.md : VeilSpace.lg),
            _staggered(2, widget.bottom!),
          ],
        ],
      ),
    );
  }
}

class VeilSurfaceCard extends StatelessWidget {
  const VeilSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VeilSpace.lg),
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
    return Card(
      color: selected
          ? palette.surfaceRaised
          : toned
              ? palette.surfaceAlt
              : null,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class VeilSectionLabel extends StatelessWidget {
  const VeilSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class VeilInlineBanner extends StatelessWidget {
  const VeilInlineBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = VeilBannerTone.info,
    this.icon,
    this.dense = false,
    this.actionLabel,
    this.onAction,
  });

  final String? title;
  final String message;
  final VeilBannerTone tone;
  final IconData? icon;

  /// Tighter padding and smaller body text, for a phone screen whose
  /// content must keep most of the height.
  final bool dense;

  /// A button inside the banner, under its message, that acts on it.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _paletteFor(tone, theme.brightness);
    final hasAction = actionLabel != null;
    final messageStyle = dense
        ? theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.4)
        : theme.textTheme.bodyMedium;

    return AnimatedContainer(
      duration: VeilMotion.normal,
      curve: VeilMotion.emphasize,
      padding: dense
          ? EdgeInsets.fromLTRB(VeilSpace.sm, VeilSpace.sm - 2, VeilSpace.sm, hasAction ? 0 : VeilSpace.sm - 2)
          : const EdgeInsets.all(VeilSpace.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(dense ? VeilRadius.sm : VeilRadius.md),
        border: Border.all(color: palette.border),
        color: palette.fill,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon ?? _defaultIconFor(tone),
              size: VeilIconSize.sm,
              color: palette.foreground,
            ),
          ),
          SizedBox(width: dense ? VeilSpace.xs : VeilSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  VeilCopy(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: palette.foreground,
                    ),
                  ),
                  SizedBox(height: dense ? 2 : VeilSpace.xxs),
                ],
                VeilCopy(message, style: messageStyle?.copyWith(color: palette.text)),
                if (hasAction)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: palette.foreground,
                        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm),
                      ),
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

// A tone's colours on the theme's surfaces. The fill is a tint of the
// surface, so what is written on it is light on the dark theme and dark on
// the light one: the bright tone colours do not read on a pale tint.
_BannerPalette _paletteFor(VeilBannerTone tone, Brightness brightness) {
  final light = brightness == Brightness.light;
  final text = light ? const Color(0xE6000000) : const Color(0xE6FFFFFF);
  return switch (tone) {
    VeilBannerTone.info => _BannerPalette(
        border: const Color(0x660A84FF),
        fill: const Color(0x1F0A84FF),
        foreground: light ? const Color(0xFF0058B8) : const Color(0xFF4FA6FF),
        text: text,
      ),
    VeilBannerTone.good => _BannerPalette(
        border: const Color(0x6630D158),
        fill: const Color(0x1F30D158),
        foreground: light ? const Color(0xFF1A7A37) : const Color(0xFF30D158),
        text: text,
      ),
    VeilBannerTone.warn => _BannerPalette(
        border: const Color(0x66FF9F0A),
        fill: const Color(0x1FFF9F0A),
        foreground: light ? const Color(0xFF8F5200) : const Color(0xFFFF9F0A),
        text: text,
      ),
    VeilBannerTone.danger => _BannerPalette(
        border: const Color(0x66FF453A),
        fill: const Color(0x1FFF453A),
        foreground: light ? const Color(0xFFC0261B) : const Color(0xFFFF453A),
        text: text,
      ),
  };
}

IconData _defaultIconFor(VeilBannerTone tone) {
  return switch (tone) {
    VeilBannerTone.info => Icons.radar_outlined,
    VeilBannerTone.good => Icons.verified_outlined,
    VeilBannerTone.warn => Icons.warning_amber_rounded,
    VeilBannerTone.danger => Icons.priority_high_rounded,
  };
}

/// A [VeilInlineBanner] cut down to one row, for where there is no height
/// for the banner: the icon, the title and, at the end of the same row, the
/// action. Beside an action a long title takes a second line rather than
/// be cut short; a row with no action shows as much of its message after
/// the title as fits the line.
///
/// The row is a strip across the full width with no gap around it, 44 px
/// tall at the default text size, so that two of them fit where one banner
/// would not.
class VeilNoticeRow extends StatelessWidget {
  const VeilNoticeRow({
    super.key,
    required this.title,
    this.message,
    this.tone = VeilBannerTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  /// The height of a row whose text fits one line at the default size.
  static const double minHeight = 44;

  final String title;
  final String? message;
  final VeilBannerTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _paletteFor(tone, theme.brightness);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(color: palette.foreground);
    final hasAction = actionLabel != null;

    return Container(
      constraints: const BoxConstraints(minHeight: minHeight),
      padding: EdgeInsets.only(left: VeilSpace.md, right: hasAction ? VeilSpace.xxs : VeilSpace.md),
      decoration: BoxDecoration(color: palette.fill),
      // Drawn over the fill, so that the line between two rows costs no
      // height.
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Icon(icon ?? _defaultIconFor(tone), size: VeilIconSize.sm, color: palette.foreground),
          const SizedBox(width: VeilSpace.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: veilKeepWordsWhole(title),
                style: titleStyle,
                children: [
                  if (!hasAction && message != null)
                    TextSpan(
                      text: '  ${veilKeepWordsWhole(message!)}',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, color: palette.text),
                    ),
                ],
              ),
              semanticsLabel: !hasAction && message != null ? '$title  $message' : title,
              maxLines: hasAction ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasAction)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: palette.foreground,
                minimumSize: const Size(minHeight, minHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm),
              ),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class VeilStatusPill extends StatelessWidget {
  const VeilStatusPill({
    super.key,
    required this.label,
    this.tone = VeilBannerTone.info,
  });

  final String label;
  final VeilBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(tone, Theme.of(context).brightness);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VeilSpace.sm,
        vertical: VeilSpace.xs - 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VeilRadius.pill),
        border: Border.all(color: palette.border),
        color: palette.fill,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.foreground,
            ),
      ),
    );
  }
}

class VeilActionCluster extends StatelessWidget {
  const VeilActionCluster({
    super.key,
    required this.children,
    this.spacing = VeilSpace.sm,
  });

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

class VeilActionRow extends StatelessWidget {
  const VeilActionRow({
    super.key,
    required this.children,
    this.spacing = VeilSpace.sm,
  });

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

class VeilToast {
  static void show(
    BuildContext context, {
    required String message,
    VeilBannerTone tone = VeilBannerTone.info,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    // The toast's text takes the theme's text colour, so its ground is a
    // dark tint on the dark theme and a pale one on the light theme.
    final light = Theme.of(context).brightness == Brightness.light;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: VeilCopy(message),
        backgroundColor: switch (tone) {
          VeilBannerTone.good => light ? const Color(0xFFE2F5E8) : const Color(0xFF173229),
          VeilBannerTone.warn => light ? const Color(0xFFFFF0DA) : const Color(0xFF352815),
          VeilBannerTone.danger => light ? const Color(0xFFFDE4E2) : const Color(0xFF3C1B25),
          VeilBannerTone.info => null,
        },
      ),
    );
  }
}

class VeilMetricStrip extends StatelessWidget {
  const VeilMetricStrip({
    super.key,
    required this.items,
  });

  final List<VeilMetricItem> items;

  /// How many tiles go on each row of a phone-width strip of [count] tiles:
  /// at most three to a row, and as even as the count allows, so no tile is
  /// left alone on a row of its own (four tiles are two and two, seven are
  /// three, two and two).
  static List<int> phoneRows(int count) {
    if (count <= 0) return const [];
    final rows = (count / 3).ceil();
    return [for (var row = 0; row < rows; row++) count ~/ rows + (row < count % rows ? 1 : 0)];
  }

  @override
  Widget build(BuildContext context) {
    if (!context.veilPhoneWidth) {
      return Wrap(
        spacing: VeilSpace.sm,
        runSpacing: VeilSpace.sm,
        children: [for (final item in items) _tile(context, item, minWidth: 112)],
      );
    }

    // A phone has no room for tiles at their own width side by side: they
    // would wrap two and one. Each row shares the width instead.
    var next = 0;
    return Column(
      children: [
        for (final (index, size) in phoneRows(items.length).indexed) ...[
          if (index > 0) const SizedBox(height: VeilSpace.xs),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (column, item) in items.sublist(next, next += size).indexed) ...[
                  if (column > 0) const SizedBox(width: VeilSpace.xs),
                  Expanded(child: _tile(context, item, compact: true)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, VeilMetricItem item, {double minWidth = 0, bool compact = false}) {
    final theme = Theme.of(context);
    return VeilSurfaceCard(
      toned: true,
      padding: EdgeInsets.symmetric(horizontal: compact ? VeilSpace.sm : VeilSpace.md, vertical: VeilSpace.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.label.toUpperCase(),
              maxLines: compact ? 1 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: theme.textTheme.labelMedium?.copyWith(color: context.veilPalette.textSubtle),
            ),
            const SizedBox(height: VeilSpace.xxs),
            VeilCopy(
              item.value,
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class VeilMetricItem {
  const VeilMetricItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class VeilDestructiveNotice extends StatelessWidget {
  const VeilDestructiveNotice({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Container(
      padding: const EdgeInsets.all(VeilSpace.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VeilRadius.lg),
        border: Border.all(color: palette.danger.withValues(alpha: 0.45)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.danger.withValues(alpha: 0.12),
            palette.surface,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VeilRadius.sm),
              color: palette.danger.withValues(alpha: 0.14),
              border: Border.all(color: palette.danger.withValues(alpha: 0.45)),
            ),
            child: Icon(
              Icons.priority_high_rounded,
              size: VeilIconSize.md,
              color: palette.danger,
            ),
          ),
          const SizedBox(width: VeilSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VeilCopy(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: VeilSpace.xs),
                VeilCopy(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

  /// The line under the title: the app's own copy, or a handle. Its Korean
  /// words stay whole where it wraps; text a person wrote goes into
  /// [subtitleWidget] instead.
  final String subtitle;
  final Widget? subtitleWidget;
  final String? eyebrow;
  final Widget? leading;
  final Widget? trailing;
  final bool destructive;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final titleColor = destructive ? palette.danger : null;

    return AnimatedContainer(
      duration: VeilMotion.normal,
      curve: VeilMotion.emphasize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VeilRadius.lg),
        boxShadow: selected ? VeilElevation.raised : null,
      ),
      child: Card(
        color: selected ? palette.surfaceRaised : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VeilRadius.lg),
          side: BorderSide(
            color: selected ? palette.strokeStrong : palette.stroke,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(VeilRadius.lg),
          onTap: onTap,
          child: ListTile(
            minTileHeight: 72,
            leading: leading,
            trailing: trailing,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: palette.textSubtle,
                        ),
                  ),
                  const SizedBox(height: VeilSpace.xxs),
                ],
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: titleColor),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: VeilSpace.xxs),
              child: subtitleWidget ??
                  VeilCopy(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

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

  /// What a screen reader says for the row, in the user's language: that
  /// it is a conversation, and with whom. The title alone does not say it.
  final String semanticLabel;

  /// A lower row with a smaller avatar, for a phone's list.
  final bool dense;

  /// A small mark before the title (a group), with what it stands for.
  final IconData? titleIcon;
  final String? titleIconLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final avatarGlyph = title.isNotEmpty ? title.characters.first.toUpperCase() : '#';
    final avatarHash = handle.hashCode;
    final avatarColors = [
      [const Color(0xFF6C8CFF), const Color(0xFF8B5CF6)],
      [const Color(0xFF5CE0B0), const Color(0xFF3B82F6)],
      [const Color(0xFFFF7B93), const Color(0xFFFF6B6B)],
      [const Color(0xFFFFBE6D), const Color(0xFFFF8C42)],
      [const Color(0xFF8B5CF6), const Color(0xFFEC4899)],
      [const Color(0xFF06B6D4), const Color(0xFF6C8CFF)],
    ][avatarHash.abs() % 6];

    final radius = dense ? VeilRadius.md : VeilRadius.lg;
    final avatarSize = dense ? 46.0 : 52.0;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: AnimatedContainer(
        duration: VeilMotion.normal,
        curve: VeilMotion.emphasize,
        margin: EdgeInsets.symmetric(vertical: dense ? 2 : 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: selected ? VeilElevation.raised : null,
        ),
        child: Material(
          color: selected ? palette.surfaceRaised : palette.surface,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            splashColor: palette.primarySoft,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? VeilSpace.sm : VeilSpace.md,
                vertical: dense ? VeilSpace.sm : VeilSpace.sm + 2,
              ),
              child: Row(
                children: [
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: avatarColors,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: avatarColors[0].withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      avatarGlyph,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: VeilSpace.sm + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (titleIcon != null) ...[
                              Icon(
                                titleIcon,
                                size: VeilIconSize.xs + 2,
                                color: palette.textMuted,
                                semanticLabel: titleIconLabel,
                              ),
                              const SizedBox(width: VeilSpace.xxs),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: VeilSpace.xs),
                            Text(
                              timestamp,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: selected
                                        ? palette.primaryStrong
                                        : palette.textSubtle,
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: palette.textMuted,
                                      fontSize: 13,
                                    ),
                              ),
                            ),
                            if (expiryLabel != null) ...[
                              const SizedBox(width: VeilSpace.xs),
                              VeilStatusPill(
                                label: expiryLabel!,
                                tone: VeilBannerTone.warn,
                              ),
                            ],
                          ],
                        ),
                        if (meta != null) ...[
                          const SizedBox(height: 6),
                          meta!,
                        ],
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

class VeilMessageBubbleCard extends StatelessWidget {
  const VeilMessageBubbleCard({
    super.key,
    required this.child,
    required this.isMine,
    this.highlighted = false,
  });

  final Widget child;
  final bool isMine;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;

    return AnimatedContainer(
      duration: VeilMotion.normal,
      curve: VeilMotion.springGentle,
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(
        horizontal: VeilSpace.md,
        vertical: VeilSpace.sm,
      ),
      decoration: BoxDecoration(
        gradient: highlighted
            ? null
            : isMine
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.primary,
                      Color.lerp(palette.primary, palette.accent, 0.5) ??
                          palette.primary,
                    ],
                  )
                : null,
        color: highlighted
            ? palette.surfaceRaised
            : isMine
                ? null
                : palette.surfaceAlt,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(isMine ? 22 : 6),
          bottomRight: Radius.circular(isMine ? 6 : 22),
        ),
        border: Border.all(
          color: highlighted
              ? palette.primaryStrong
              : isMine
                  ? palette.primary.withValues(alpha: 0.4)
                  : palette.stroke,
          width: 0.5,
        ),
        boxShadow: isMine
            ? [
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class VeilComposer extends StatelessWidget {
  const VeilComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmit,
    required this.trailing,
    required this.label,
    this.leading,
    this.helper,
    this.dense = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSubmit;
  final Widget trailing;

  /// Less padding above and below the draft, for where height is scarce
  /// (above an open keyboard): at the default text size the draft is then
  /// exactly as tall as the send button.
  final bool dense;

  /// A control before the draft (attach), in place of the lock mark.
  final Widget? leading;
  final String? helper;

  /// The hint in the empty draft, in the user's language.
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Material(
      color: palette.surfaceAlt,
      borderRadius: BorderRadius.circular(VeilRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          leading == null ? VeilSpace.sm : VeilSpace.xxs,
          VeilSpace.xs,
          VeilSpace.xs,
          VeilSpace.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VeilRadius.xl),
          border: Border.all(color: palette.stroke, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            leading ??
                Padding(
                  padding: EdgeInsets.only(bottom: dense ? VeilSpace.sm - 2 : VeilSpace.sm),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: VeilIconSize.sm,
                    color: palette.textSubtle,
                  ),
                ),
            SizedBox(width: leading == null ? VeilSpace.xs : VeilSpace.xxs),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                enabled: enabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: label,
                  hintStyle: TextStyle(color: palette.textSubtle),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: dense ? VeilSpace.sm - 2 : VeilSpace.sm,
                  ),
                  // Never under the 44 px a tap target needs.
                  constraints: dense ? const BoxConstraints(minHeight: 44) : null,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: VeilSpace.xs),
            trailing,
          ],
        ),
      ),
    );
  }
}

class VeilEmptyState extends StatelessWidget {
  const VeilEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.compact = false,
  });

  final String title;
  final String body;
  final IconData icon;
  final Widget? action;

  /// Without the icon and most of the space around it, for where there is
  /// little height: above an open keyboard, say.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: VeilSpace.lg,
            vertical: compact ? VeilSpace.sm : VeilSpace.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) ...[
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(VeilRadius.lg),
                    border: Border.all(color: palette.stroke),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [palette.surfaceRaised, palette.canvasAlt],
                    ),
                  ),
                  child: Icon(icon, size: VeilIconSize.xl, color: palette.primary),
                ),
                const SizedBox(height: VeilSpace.lg),
              ],
              VeilCopy(
                title,
                style: compact ? theme.textTheme.titleLarge : theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: compact ? VeilSpace.xxs : VeilSpace.xs),
              VeilCopy(
                body,
                style: (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.copyWith(
                  color: palette.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
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

class VeilErrorState extends StatelessWidget {
  const VeilErrorState({
    super.key,
    required this.title,
    required this.body,
    this.action,
  });

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return VeilEmptyState(
      title: title,
      body: body,
      icon: Icons.error_outline_rounded,
      action: action,
    );
  }
}

class VeilLoadingBlock extends StatelessWidget {
  const VeilLoadingBlock({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: VeilSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.primary.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                    ),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.primary,
                        boxShadow: [
                          BoxShadow(
                            color: palette.primary.withValues(alpha: 0.55),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: VeilSpace.lg),
              VeilCopy(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: VeilSpace.xs),
              VeilCopy(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VeilSkeletonLine extends StatefulWidget {
  const VeilSkeletonLine({
    super.key,
    this.width,
    this.height = 12,
  });

  final double? width;
  final double height;

  @override
  State<VeilSkeletonLine> createState() => _VeilSkeletonLineState();
}

class _VeilSkeletonLineState extends State<VeilSkeletonLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VeilRadius.pill),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _shimmer.value, 0),
              end: Alignment(1.0 + 2.0 * _shimmer.value, 0),
              colors: [
                palette.surfaceAlt,
                palette.surfaceOverlay,
                palette.surfaceAlt,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

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
    final palette = context.veilPalette;
    final indicatorColor = complete
        ? palette.success
        : active
            ? palette.primary
            : palette.strokeStrong;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: indicatorColor.withValues(alpha: 0.12),
            border: Border.all(color: indicatorColor),
          ),
          child: complete
              ? Icon(
                  Icons.check_rounded,
                  size: VeilIconSize.sm,
                  color: indicatorColor,
                )
              : Text(
                  '$step',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: indicatorColor,
                      ),
                ),
        ),
        const SizedBox(width: VeilSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VeilCopy(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: VeilSpace.xxs),
              VeilCopy(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class VeilValueRow extends StatelessWidget {
  const VeilValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueTone = VeilBannerTone.info,
    this.detail,
  });

  final String label;
  final String value;
  final VeilBannerTone valueTone;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return VeilSurfaceCard(
      toned: true,
      padding: const EdgeInsets.all(VeilSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: VeilCopy(label, style: Theme.of(context).textTheme.titleSmall),
              ),
              const SizedBox(width: VeilSpace.xs),
              VeilStatusPill(label: value, tone: valueTone),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: VeilSpace.sm),
            VeilCopy(
              detail!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.veilPalette.textMuted,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BannerPalette {
  const _BannerPalette({
    required this.border,
    required this.fill,
    required this.foreground,
    required this.text,
  });

  final Color border;
  final Color fill;

  /// The icon, the title and an action.
  final Color foreground;

  /// The message under the title.
  final Color text;
}
