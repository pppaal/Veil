import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

/// How a fact about this device or build stands.
enum SecuritySignalTone { good, warn, neutral }

/// One fact the security status reports: what it is about, how it stands,
/// and a sentence saying what that means.
class SecuritySignal {
  const SecuritySignal({
    required this.label,
    required this.value,
    required this.detail,
    required this.tone,
  });

  final String label;
  final String value;
  final String detail;
  final SecuritySignalTone tone;

  /// Whether this is something for the user to look at.
  bool get needsAttention => tone == SecuritySignalTone.warn;
}

/// A group of facts under one heading, as rows of one card: each row its
/// label with how it stands beside it, and the sentence under them.
class SecuritySignalGroup extends StatelessWidget {
  const SecuritySignalGroup({super.key, required this.title, required this.signals});

  final String title;
  final List<SecuritySignal> signals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: VeilSpace.xxs, bottom: VeilSpace.xs),
          child: VeilSectionLabel(title.toUpperCase()),
        ),
        VeilSurfaceCard(
          toned: true,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (index, signal) in signals.indexed) ...[
                if (index > 0)
                  Divider(height: 1, thickness: 0.5, indent: VeilSpace.md, endIndent: VeilSpace.md, color: palette.stroke),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: VeilCopy(signal.label, style: theme.textTheme.titleSmall)),
                          const SizedBox(width: VeilSpace.xs),
                          VeilStatusPill(
                            label: signal.value,
                            tone: switch (signal.tone) {
                              SecuritySignalTone.good => VeilBannerTone.good,
                              SecuritySignalTone.warn => VeilBannerTone.warn,
                              SecuritySignalTone.neutral => VeilBannerTone.info,
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: VeilSpace.xxs),
                      VeilCopy(
                        signal.detail,
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.45, color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
