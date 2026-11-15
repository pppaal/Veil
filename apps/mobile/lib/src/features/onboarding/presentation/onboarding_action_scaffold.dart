import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// An onboarding screen whose text scrolls above controls that stay where
/// they are: what answers the text (the box to tick, the button that goes
/// on) is in reach wherever the reader is, on any screen height.
class OnboardingActionScaffold extends StatelessWidget {
  const OnboardingActionScaffold({
    super.key,
    this.title,
    this.grouped = false,
    this.listPadding = const EdgeInsets.all(VeilSpace.md),
    required this.children,
    required this.actions,
  });

  /// The bar's title, if the screen has one.
  final String? title;

  /// Whether the page is a grouped page (see [VeilShell.grouped]). Its
  /// pinned controls then sit on the page under a hairline, since the
  /// groups scroll under them.
  final bool grouped;

  /// Around what scrolls.
  final EdgeInsetsGeometry listPadding;

  /// What scrolls.
  final List<Widget> children;

  /// What stays under it, top to bottom.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final pinned = Padding(
      padding: EdgeInsets.only(top: grouped ? VeilSpace.sm : 0, bottom: VeilSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: actions,
      ),
    );
    return VeilShell(
      title: title,
      grouped: grouped,
      child: Column(
        children: [
          Expanded(child: ListView(padding: listPadding, children: children)),
          if (grouped)
            DecoratedBox(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.stroke, width: 0.5))),
              child: pinned,
            )
          else
            pinned,
        ],
      ),
    );
  }
}
