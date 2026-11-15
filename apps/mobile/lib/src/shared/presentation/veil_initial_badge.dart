import 'package:flutter/material.dart';

import 'veil_avatar.dart';

export 'veil_avatar.dart' show veilInitialOf;

/// The avatar of the previous pass, kept so its screens compile until wave
/// 1 moves them to [VeilAvatar].
///
/// It knows only a display name, not the handle that picks a person's
/// colour, so a coloured disc here would disagree with the same person's
/// avatar in the lists. It draws the neutral disc with a person glyph
/// instead, the "no picture" look, until its callers pass the handle to
/// [VeilAvatar] themselves.
@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use VeilAvatar.')
class VeilInitialBadge extends StatelessWidget {
  const VeilInitialBadge({super.key, required this.name, this.size = 44, this.danger = false});

  final String name;
  final double size;

  /// Ignored: a failed state is a word, not a red letter.
  final bool danger;

  @override
  Widget build(BuildContext context) => VeilAvatar(name: name, seed: name, size: size, unknown: true);
}
