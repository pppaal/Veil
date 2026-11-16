import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_notice.dart';

export 'veil_avatar.dart';
export 'veil_bubble.dart';
export 'veil_composer.dart';
export 'veil_group.dart';
export 'veil_notice.dart';

// The shared widgets (docs/mobile-design-system.md, section 7): VeilShell
// (veil_shell.dart), VeilGroup and VeilRow, VeilButton, VeilAvatar,
// VeilNotice, VeilBubble, VeilComposer and VeilEmptyState, with the helpers
// VeilHaptics, VeilFirstThatFits and showVeilToast.

/// The tone of a notice, a status word or a toast.
enum VeilTone { info, good, warn, danger }

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

/// A short message at the bottom of the screen for something that just
/// happened. The tone shows only as a leading icon; information has none.
/// [actionLabel] and [onAction] add one text button, such as Retry after
/// something failed.
///
/// Every toast closes by itself, one with a button too (Flutter would keep
/// that until it is tapped): it is drawn above every screen, so one left
/// standing follows the user from screen to screen. One with a button
/// stays longer, and with a screen reader on it waits to be dismissed, as
/// the platform does.
void showVeilToast(
  BuildContext context,
  String message, {
  VeilTone tone = VeilTone.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final palette = context.veilPalette;
  final messenger = ScaffoldMessenger.of(context);
  final action = actionLabel == null || onAction == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      action: action,
      duration: action == null ? const Duration(seconds: 4) : const Duration(seconds: 8),
      persist: action != null && MediaQuery.accessibleNavigationOf(context),
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
