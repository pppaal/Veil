import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

/// What an action of the step in hand came to: why it failed, as a notice,
/// or what the server answered, as a line of text (green for an approval).
/// It appears under the controls after a tap that may have been made at
/// the foot of the screen, so it brings itself into view when it appears
/// and whenever its words change. Nothing moves while it is already on
/// screen, and a screen that opens with a result on it opens at its top.
class TransferStepResult extends StatefulWidget {
  const TransferStepResult({super.key, required this.message, this.title, this.tone = VeilTone.info});

  final String? title;
  final String message;
  final VeilTone tone;

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
    final failed = widget.tone == VeilTone.danger || widget.tone == VeilTone.warn;
    if (failed) {
      return VeilNotice(title: widget.title, message: widget.message, tone: widget.tone, margin: EdgeInsets.zero);
    }
    final palette = context.veilPalette;
    return Text(
      widget.message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: widget.tone == VeilTone.good ? palette.success : palette.textMuted,
          ),
    );
  }
}

/// The controls of the step in hand that are not fields (buttons, a
/// result), at the page's 16 gutter, 12 under what is above them.
class TransferControls extends StatelessWidget {
  const TransferControls({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.sm, VeilSpace.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const SizedBox(height: VeilSpace.xs),
            child,
          ],
        ],
      ),
    );
  }
}
