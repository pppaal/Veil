import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Where a step of the transfer stands.
enum StepRowState {
  /// Its turn has not come.
  upcoming,

  /// What the user does now: its controls are under the steps.
  current,

  /// Finished: a check mark in place of the number.
  done,
}

/// One numbered step of the transfer, as a row of the steps' group: a 24dp
/// disc with the number (blue for the step in hand, grey otherwise, a check
/// mark once it is done), the title, and one line about it. [status] is a
/// short state the disc does not show ("Expired"), a word at the end of the
/// title's line; [trailing] a small action there (reopening a finished
/// step). Neither takes width from [body].
class StepRow extends StatelessWidget {
  const StepRow({
    super.key,
    required this.number,
    required this.title,
    required this.state,
    this.body,
    this.status,
    this.statusTone = VeilTone.info,
    this.trailing,
  });

  final int number;
  final String title;
  final StepRowState state;
  final String? body;
  final String? status;
  final VeilTone statusTone;
  final Widget? trailing;

  /// The disc's width, which with the gap after it is where the hairlines
  /// between steps start.
  static const double disc = 24;

  /// The [VeilGroup.inset] of a group of steps: the text edge.
  static const double groupInset = VeilSpace.md + disc + VeilSpace.sm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final current = state == StepRowState.current;
    final upcoming = state == StepRowState.upcoming;

    final heading = Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(color: upcoming ? palette.textMuted : palette.text),
    );

    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: EdgeInsets.fromLTRB(VeilSpace.md, 11, trailing == null ? VeilSpace.md : VeilSpace.xxs, 11),
          child: Row(
            crossAxisAlignment: trailing == null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Container(
                width: disc,
                height: disc,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: current ? palette.primary : palette.surfaceAlt,
                ),
                child: state == StepRowState.done
                    ? Icon(Icons.check, size: VeilIconSize.xs, color: palette.textMuted)
                    : Text(
                        '$number',
                        style: theme.textTheme.labelMedium?.copyWith(color: current ? Colors.white : palette.textMuted),
                      ),
              ),
              const SizedBox(width: VeilSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status == null)
                      heading
                    else
                      // The state shares the title's line while both fit and
                      // goes under the title when they do not.
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: VeilSpace.xs,
                          runSpacing: 2,
                          children: [
                            heading,
                            Text(
                              status!,
                              style: theme.textTheme.labelMedium?.copyWith(color: veilToneColor(palette, statusTone)),
                            ),
                          ],
                        ),
                      ),
                    if (body != null) ...[
                      const SizedBox(height: 2),
                      Text(body!, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: VeilSpace.xs), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
