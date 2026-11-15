import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

/// Leaves the screen: back to the one under it, or to the conversation list
/// when it was opened as the first screen (a link, a restored session) and
/// there is nothing under it.
void veilLeaveScreen(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    GoRouter.maybeOf(context)?.go('/conversations');
  }
}

/// The body of a screen for something this build cannot do: what is
/// missing, that nothing happened, and one button that leaves.
///
/// It is the whole of such a screen. A screen that can do part of its job
/// shows that part and says the rest in a banner instead.
class VeilUnavailable extends StatelessWidget {
  const VeilUnavailable({
    super.key,
    required this.title,
    required this.body,
    required this.closeLabel,
    this.icon = Icons.block_rounded,
    this.header,
  });

  final String title;
  final String body;

  /// The label of the button that leaves the screen.
  final String closeLabel;
  final IconData icon;

  /// Shown above the words in place of [icon]: who or what the screen was
  /// opened for.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    // Centred while it fits, and scrolling when larger text or a short
    // screen leaves it no room.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (header != null) ...[
                  header,
                  const SizedBox(height: VeilSpace.md),
                ],
                VeilEmptyState(
                  compact: header != null,
                  icon: icon,
                  title: title,
                  body: body,
                  action: VeilButton(
                    expanded: false,
                    tone: VeilButtonTone.secondary,
                    label: closeLabel,
                    onPressed: () => veilLeaveScreen(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
