import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/veil_theme.dart';

enum VeilBannerTone { info, good, warn, danger }

enum VeilButtonTone { primary, secondary, destructive, ghost }

extension VeilThemeContext on BuildContext {
  VeilPalette get veilPalette => VeilPalette.dark;
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
      HapticFeedback.selectionClick();
      if (destructive) {
        HapticFeedback.mediumImpact();
      }
      handler();
    };
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
            Text(
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

class VeilHeroPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;

    return Container(
      padding: const EdgeInsets.all(VeilSpace.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VeilRadius.xl),
        border: Border.all(color: palette.stroke),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF171F29),
            Color(0xFF111821),
            Color(0xFF0A0F15),
          ],
        ),
        boxShadow: VeilElevation.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: palette.primaryStrong,
              ),
            ),
            const SizedBox(height: VeilSpace.md),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineLarge?.copyWith(height: 1.04),
                    ),
                    const SizedBox(height: VeilSpace.sm),
                    Text(
                      body,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: VeilSpace.md),
                Flexible(child: trailing!),
              ],
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: VeilSpace.lg),
            bottom!,
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
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool toned;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Card(
      color: toned ? palette.surfaceAlt : null,
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
  });

  final String? title;
  final String message;
  final VeilBannerTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(tone);

    return AnimatedContainer(
      duration: VeilMotion.normal,
      curve: VeilMotion.emphasize,
      padding: const EdgeInsets.all(VeilSpace.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VeilRadius.md),
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
          const SizedBox(width: VeilSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: palette.foreground,
                        ),
                  ),
                  const SizedBox(height: VeilSpace.xxs),
                ],
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _BannerPalette _paletteFor(VeilBannerTone tone) {
    return switch (tone) {
      VeilBannerTone.info => const _BannerPalette(
          border: Color(0xFF355069),
          fill: Color(0x1F88A9C4),
          foreground: Color(0xFFA9C6DF),
        ),
      VeilBannerTone.good => const _BannerPalette(
          border: Color(0xFF27584B),
          fill: Color(0x1A4CC7A2),
          foreground: Color(0xFF8BE0C4),
        ),
      VeilBannerTone.warn => const _BannerPalette(
          border: Color(0xFF6D5631),
          fill: Color(0x1FFFC670),
          foreground: Color(0xFFFFD28D),
        ),
      VeilBannerTone.danger => const _BannerPalette(
          border: Color(0xFF6A3342),
          fill: Color(0x1FF57C96),
          foreground: Color(0xFFFFA8B7),
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
    final palette = switch (tone) {
      VeilBannerTone.info => const _BannerPalette(
          border: Color(0xFF355069),
          fill: Color(0x1F88A9C4),
          foreground: Color(0xFFA9C6DF),
        ),
      VeilBannerTone.good => const _BannerPalette(
          border: Color(0xFF27584B),
          fill: Color(0x1A4CC7A2),
          foreground: Color(0xFF8BE0C4),
        ),
      VeilBannerTone.warn => const _BannerPalette(
          border: Color(0xFF6D5631),
          fill: Color(0x1FFFC670),
          foreground: Color(0xFFFFD28D),
        ),
      VeilBannerTone.danger => const _BannerPalette(
          border: Color(0xFF6A3342),
          fill: Color(0x1FF57C96),
          foreground: Color(0xFFFFA8B7),
        ),
    };

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
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: switch (tone) {
          VeilBannerTone.good => const Color(0xFF173229),
          VeilBannerTone.warn => const Color(0xFF352815),
          VeilBannerTone.danger => const Color(0xFF3C1B25),
          VeilBannerTone.info => null,
        },
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
    this.leading,
    this.trailing,
    this.destructive = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final titleColor = destructive ? palette.danger : null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(VeilRadius.lg),
        onTap: onTap,
        child: ListTile(
          minTileHeight: 72,
          leading: leading,
          trailing: trailing,
            title: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: titleColor),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: VeilSpace.xxs),
              child: subtitleWidget ??
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
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
    this.onTap,
  });

  final String title;
  final String handle;
  final String subtitle;
  final String timestamp;
  final String? expiryLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final avatarGlyph = title.isNotEmpty ? title.characters.first.toUpperCase() : '#';

    return Semantics(
      button: true,
      label: 'Conversation with $title',
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(VeilRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(VeilSpace.lg),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(VeilRadius.md),
                    color: palette.primarySoft,
                    border: Border.all(color: palette.stroke),
                  ),
                  child: Text(
                    avatarGlyph,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: VeilSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: VeilSpace.xxs),
                      Text(
                        '@$handle',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: palette.textSubtle,
                            ),
                      ),
                      const SizedBox(height: VeilSpace.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          if (expiryLabel != null) ...[
                            const SizedBox(width: VeilSpace.xs),
                            Flexible(
                              child: VeilStatusPill(
                                label: expiryLabel!,
                                tone: VeilBannerTone.warn,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: VeilSpace.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timestamp,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: palette.textSubtle,
                          ),
                    ),
                    const SizedBox(height: VeilSpace.sm),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: palette.textSubtle,
                    ),
                  ],
                ),
              ],
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
  });

  final Widget child;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;

    return AnimatedContainer(
      duration: VeilMotion.normal,
      curve: VeilMotion.emphasize,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(VeilSpace.md),
      decoration: BoxDecoration(
        color: isMine ? palette.primarySoft : palette.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(VeilRadius.lg),
          topRight: const Radius.circular(VeilRadius.lg),
          bottomLeft: Radius.circular(isMine ? VeilRadius.lg : VeilSpace.xs),
          bottomRight: Radius.circular(isMine ? VeilSpace.xs : VeilRadius.lg),
        ),
        border: Border.all(
          color: isMine ? palette.strokeStrong : palette.stroke,
        ),
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
    this.helper,
    this.label = 'Send opaque text',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSubmit;
  final Widget trailing;
  final String? helper;
  final String label;

  @override
  Widget build(BuildContext context) {
    return VeilSurfaceCard(
      toned: true,
      padding: const EdgeInsets.all(VeilSpace.md),
      child: Column(
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            minLines: 1,
            maxLines: 5,
            enabled: enabled,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: label,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: VeilSpace.xs),
                child: Icon(Icons.lock_outline_rounded),
              ),
              prefixIconConstraints: const BoxConstraints(
                minHeight: 40,
                minWidth: 40,
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  helper ?? 'This message stays opaque to the relay.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.veilPalette.textMuted,
                      ),
                ),
              ),
              const SizedBox(width: VeilSpace.sm),
              trailing,
            ],
          ),
        ],
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
  });

  final String title;
  final String body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VeilSpace.lg,
            vertical: VeilSpace.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(VeilRadius.lg),
                  border: Border.all(color: palette.stroke),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF18202A), Color(0xFF10161D)],
                  ),
                ),
                child: Icon(icon, size: VeilIconSize.xl, color: palette.primary),
              ),
              const SizedBox(height: VeilSpace.lg),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: VeilSpace.xs),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                    ),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: VeilSpace.lg),
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: VeilSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(height: VeilSpace.lg),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: VeilSpace.xs),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.veilPalette.textMuted,
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

class VeilSkeletonLine extends StatelessWidget {
  const VeilSkeletonLine({
    super.key,
    this.width,
    this.height = 12,
  });

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VeilRadius.pill),
        gradient: LinearGradient(
          colors: [
            palette.surfaceAlt,
            palette.surfaceOverlay,
            palette.surfaceAlt,
          ],
        ),
      ),
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
          child: Text(
            complete ? '•' : '$step',
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
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: VeilSpace.xxs),
              Text(
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
                child: Text(label, style: Theme.of(context).textTheme.titleSmall),
              ),
              VeilStatusPill(label: value, tone: valueTone),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: VeilSpace.sm),
            Text(
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
  });

  final Color border;
  final Color fill;
  final Color foreground;
}
