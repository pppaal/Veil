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

  /// A short state the number does not show ("Expired"): at the end of the
  /// title's line, or under the title when the two do not fit on one. It
  /// never takes width from [body].
  final String? status;
  final VeilBannerTone statusTone;

  /// A small action at the end of the title's line (reopening a finished
  /// step, closing it again). It takes no width from [body] either.
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
    // A title beside a button is centred on it; otherwise the line hangs
    // from the top, with a one-line title centred on the badge.
    final centred = trailing != null;
    final heading = VeilCopy(
      title,
      style: theme.textTheme.titleMedium?.copyWith(color: upcoming ? palette.textMuted : null),
    );

    // The number, the title and what goes with the title (a state, a small
    // action) share the first line. The words about the step start under
    // it, from the title's edge to the step's: nothing on the first line
    // takes width from them.
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
                  padding: EdgeInsets.only(top: centred || status != null ? 0 : 4),
                  child: status == null
                      ? heading
                      // The state shares the title's line while both fit and
                      // drops under the title when they do not.
                      : SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: VeilSpace.xs,
                            runSpacing: VeilSpace.xxs,
                            children: [heading, VeilStatusPill(label: status!, tone: statusTone)],
                          ),
                        ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (body != null)
            Padding(
              padding: const EdgeInsets.only(left: _badge + VeilSpace.sm, top: VeilSpace.xxs),
              child: VeilCopy(body!, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
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

/// What an action of a step came to: that it went through, or why it did
/// not. It is said in the step that was acted on, and it appears after a
/// tap that may have been made at the foot of the screen, so it brings
/// itself into view when it appears and whenever its words change. Nothing
/// moves while it is already on screen, and a screen that opens with a
/// result on it opens at its top.
class TransferStepResult extends StatefulWidget {
  const TransferStepResult({super.key, required this.message, this.title, this.tone = VeilBannerTone.info});

  final String? title;
  final String message;
  final VeilBannerTone tone;

  @override
  State<TransferStepResult> createState() => _TransferStepResultState();
}

class _TransferStepResultState extends State<TransferStepResult> {
  @override
  void initState() {
    super.initState();
    // A list that has been laid out before was on screen without this.
    final list = context.findAncestorStateOfType<ScrollableState>();
    if (list != null && list.position.hasContentDimensions) _reveal();
  }

  @override
  void didUpdateWidget(TransferStepResult oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Its foot first, then its head: whichever edge is off screen comes
      // in, and no further.
      for (final policy in const [
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ]) {
        Scrollable.ensureVisible(context, alignmentPolicy: policy);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return VeilInlineBanner(dense: true, title: widget.title, message: widget.message, tone: widget.tone);
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
