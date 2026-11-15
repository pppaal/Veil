import 'package:flutter/material.dart';

import 'veil_ui.dart';

/// The letter that stands for [name] where there is no picture: its first
/// character, without the `@` of a handle. A name with nothing to show
/// (empty, blank, a lone `@`) gets `#`, as the conversation card does.
String veilInitialOf(String name) {
  final trimmed = name.trim();
  final bare = trimmed.startsWith('@') ? trimmed.substring(1).trim() : trimmed;
  return bare.isEmpty ? '#' : bare.characters.first.toUpperCase();
}

/// A person or a group in a row or a header that has no picture: the
/// initial of [name] in a circle.
class VeilInitialBadge extends StatelessWidget {
  const VeilInitialBadge({super.key, required this.name, this.size = 44, this.danger = false});

  final String name;

  /// The diameter. A row uses 44; a header that names one person, larger.
  final double size;

  /// Draws the initial in the danger colour, for a row that reports
  /// something missed or failed.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final textTheme = Theme.of(context).textTheme;
    final large = size > 64;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.primarySoft,
        border: Border.all(color: large ? palette.strokeStrong : palette.stroke),
      ),
      // The name stands beside or under it; read aloud, the letter alone
      // would only repeat its start.
      child: ExcludeSemantics(
        child: Text(
          veilInitialOf(name),
          style: (large ? textTheme.headlineLarge : textTheme.titleMedium)
              ?.copyWith(color: danger ? palette.danger : palette.primary),
        ),
      ),
    );
  }
}
