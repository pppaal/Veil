import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

/// How a fact about this device or build stands: green for what protects
/// as it should, amber for what is weaker than it could be, red for what
/// is broken, muted for a plain fact.
enum SecuritySignalTone { good, warn, danger, neutral }

/// One fact the security screen reports: what it is about, how it stands
/// in a word or two, and, where the word needs it, a line saying why.
class SecuritySignal {
  const SecuritySignal({
    required this.label,
    required this.value,
    required this.tone,
    this.detail,
  });

  final String label;
  final String value;
  final SecuritySignalTone tone;
  final String? detail;

  VeilTone get veilTone => switch (tone) {
        SecuritySignalTone.good => VeilTone.good,
        SecuritySignalTone.warn => VeilTone.warn,
        SecuritySignalTone.danger => VeilTone.danger,
        SecuritySignalTone.neutral => VeilTone.info,
      };
}

/// A group of facts under one header: a row each, the fact's name with its
/// state as a word at the end of the same line, and under them, as wide as
/// the row, the line about it. A state too long to share the name's line
/// (larger text, a narrow phone) goes under the name, whole.
class SecuritySignalGroup extends StatelessWidget {
  const SecuritySignalGroup({super.key, required this.title, required this.signals});

  final String title;
  final List<SecuritySignal> signals;

  @override
  Widget build(BuildContext context) {
    return VeilGroup(
      header: title,
      children: [for (final signal in signals) SecuritySignalRow(signal)],
    );
  }
}

/// One fact of a [SecuritySignalGroup].
class SecuritySignalRow extends StatelessWidget {
  const SecuritySignalRow(this.signal, {super.key});

  final SecuritySignal signal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: VeilSpace.xs,
                  runSpacing: 2,
                  children: [
                    Text(signal.label, style: theme.textTheme.titleMedium),
                    Text(
                      signal.value,
                      style: theme.textTheme.labelMedium?.copyWith(color: veilToneColor(palette, signal.veilTone)),
                    ),
                  ],
                ),
              ),
              if (signal.detail != null) ...[
                const SizedBox(height: 2),
                Text(signal.detail!, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
