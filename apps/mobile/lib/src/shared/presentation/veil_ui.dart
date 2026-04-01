import 'package:flutter/material.dart';

enum VeilBannerTone { info, good, warn, danger }

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

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.65)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF151D27), Color(0xFF0E141B), Color(0xFF0B1016)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!,
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 2.6,
                color: theme.colorScheme.primary.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 10),
                    Text(body, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 16),
                trailing!,
              ],
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 20),
            bottom!,
          ],
        ],
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
            style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 1.6),
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
    final palette = switch (tone) {
      VeilBannerTone.info => const _BannerPalette(
          border: Color(0xFF37506C),
          fill: Color(0x1F6D96B6),
          foreground: Color(0xFF9CC5EA),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
        color: palette.fill,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _defaultIconFor(tone), size: 18, color: palette.foreground),
          const SizedBox(width: 12),
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
                  const SizedBox(height: 4),
                ],
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
          border: Color(0xFF37506C),
          fill: Color(0x1F6D96B6),
          foreground: Color(0xFF9CC5EA),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
        color: palette.fill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
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
  });

  final String title;
  final String body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outline),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 18),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
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
    final theme = Theme.of(context);
    final indicatorColor = complete
        ? const Color(0xFF8BE0C4)
        : active
            ? theme.colorScheme.primary
            : theme.colorScheme.outline;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: indicatorColor.withValues(alpha: complete ? 0.18 : 0.12),
            border: Border.all(color: indicatorColor),
          ),
          child: Text(
            complete ? '•' : '$step',
            style: theme.textTheme.labelMedium?.copyWith(
              color: indicatorColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: active || complete
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 4),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
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
