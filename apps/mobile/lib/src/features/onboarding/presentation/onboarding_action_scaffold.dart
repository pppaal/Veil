import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

/// An onboarding screen whose text scrolls above a bar that stays where it
/// is: the control that answers the text (agree, I understand) is in reach
/// wherever the reader is, on any screen height.
class OnboardingActionScaffold extends StatelessWidget {
  const OnboardingActionScaffold({
    super.key,
    this.title,
    required this.children,
    required this.actions,
  });

  /// The bar's title, if the screen has one.
  final String? title;

  /// What scrolls.
  final List<Widget> children;

  /// What stays under it, top to bottom.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return VeilShell(
      title: title,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(VeilSpace.lg),
              children: children,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.stroke, width: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.sm, VeilSpace.lg, VeilSpace.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: actions,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
