import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Where a step of the transfer stands.
enum TransferStepState {
  /// Its turn has not come: the title and one line, no controls.
  upcoming,

  /// What the user does now: its controls are shown.
  current,

  /// Finished: a check mark and one line.
  done,
}

/// One numbered step of the transfer: its number (a check mark once it is
/// done), its title, a line about it, and under those the controls it
/// takes while it is the step to do.
class TransferStep extends StatelessWidget {
  const TransferStep({
    super.key,
    required this.number,
    required this.title,
    required this.state,
    this.body,
    this.status,
    this.statusTone = VeilBannerTone.info,
    this.trailing,
    this.children = const [],
  });

  final int number;
  final String title;
  final TransferStepState state;

  /// A line under the title, in the app's own words.
  final String? body;

  /// A short state beside the title that the number does not show
  /// ("Expired").
  final String? status;
  final VeilBannerTone statusTone;

  /// A small action at the end of the title's row (reopening a finished
  /// step).
  final Widget? trailing;

  /// The step's controls, each as wide as the step.
  final List<Widget> children;

  static const double _badge = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final done = state == TransferStepState.done;
    final upcoming = state == TransferStepState.upcoming;
    final mark = done
        ? palette.success
        : upcoming
            ? palette.strokeStrong
            : palette.primary;
    // A title alone beside a button is centred on it; anything taller hangs
    // from the top, with a one-line title centred on the badge.
    final centred = trailing != null && body == null;

    return VeilSurfaceCard(
      toned: true,
      padding: const EdgeInsets.all(VeilSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: centred ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Container(
                width: _badge,
                height: _badge,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mark.withValues(alpha: 0.12),
                  border: Border.all(color: mark),
                ),
                child: done
                    ? Icon(Icons.check_rounded, size: VeilIconSize.sm, color: mark)
                    : Text(
                        '$number',
                        style: theme.textTheme.labelLarge?.copyWith(color: upcoming ? palette.textSubtle : mark),
                      ),
              ),
              const SizedBox(width: VeilSpace.sm),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: centred ? 0 : 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VeilCopy(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(color: upcoming ? palette.textMuted : null),
                      ),
                      if (body != null) ...[
                        const SizedBox(height: VeilSpace.xxs),
                        VeilCopy(body!, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
                      ],
                    ],
                  ),
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: VeilSpace.xs),
                VeilStatusPill(label: status!, tone: statusTone),
              ],
              if (trailing != null) trailing!,
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: VeilSpace.sm),
            ...children,
          ],
        ],
      ),
    );
  }
}

/// What the user carries from one device to the other (the transfer code,
/// the claim code), in a box of its own: [code] can be selected, and
/// [notes] say what else is known about it.
class TransferCodeBox extends StatelessWidget {
  const TransferCodeBox({super.key, required this.code, this.codeStyle, this.notes = const []});

  final String code;

  /// The code's style; the theme's body style when null.
  final TextStyle? codeStyle;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(VeilSpace.sm),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(VeilRadius.sm),
        border: Border.all(color: palette.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(code, style: codeStyle ?? theme.textTheme.bodyMedium),
          for (final note in notes) ...[
            const SizedBox(height: VeilSpace.xxs),
            TransferStepNote(note),
          ],
        ],
      ),
    );
  }
}

/// A fact about the step in hand, said under its controls in the muted
/// body style.
class TransferStepNote extends StatelessWidget {
  const TransferStepNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return VeilCopy(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.veilPalette.textMuted),
    );
  }
}
