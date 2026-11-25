import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

// The parts of the safety number page: who it is about and the number.
// Plain parts on the page: no card around either.

/// Who the safety number is about: their avatar, name and handle, and
/// whether they are verified: "Verified" with a check in green, or "Not
/// verified" in grey.
class SafetyPeerHeader extends StatelessWidget {
  const SafetyPeerHeader({super.key, required this.name, required this.handle, required this.verified});

  /// The nickname the user gave them, or null: then the handle is the
  /// title, and is not repeated under it.
  final String? name;
  final String handle;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        VeilAvatar(name: name ?? handle, seed: handle, size: 56),
        const SizedBox(width: VeilSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name ?? '@$handle', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
              if (name != null)
                Text(
                  '@$handle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                ),
            ],
          ),
        ),
        const SizedBox(width: VeilSpace.xs),
        if (verified)
          const SafetyVerifiedMark()
        else
          Text(l10n.safetyNumbersUnverified, style: theme.textTheme.labelMedium?.copyWith(color: palette.textMuted)),
      ],
    );
  }
}

/// A safety number: its twelve groups of five digits in four columns, on
/// the page, under [header] when two numbers are on screen. (The name is
/// older than the look: there is no card.)
class SafetyNumberCard extends StatelessWidget {
  const SafetyNumberCard({super.key, required this.groups, this.header});

  final List<String> groups;

  /// Says which number this is while two are on screen.
  final String? header;

  static const double _columnGap = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final style = TextStyle(
      color: palette.text,
      fontFamily: 'monospace',
      fontSize: 20,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final painter = TextPainter(
      text: TextSpan(text: groups.isEmpty ? '' : groups.first, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
    )..layout();
    final groupWidth = painter.width.ceilToDouble();
    painter.dispose();
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[
            Semantics(
              header: true,
              child: Text(header!, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)),
            ),
            const SizedBox(height: 6),
          ],
          // Four columns, or fewer where four do not fit (very large text,
          // a dialog): each group as wide as five digits, so the columns
          // line up.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 4 * groupWidth + 3 * _columnGap),
            child: Wrap(
              spacing: _columnGap,
              runSpacing: VeilSpace.xxs,
              children: [
                for (final group in groups) SizedBox(width: groupWidth, child: Text(group, style: style)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Verified" with a check, in the success colour: the one state a list
/// labels. [chevron] ends a row that opens something.
class SafetyVerifiedMark extends StatelessWidget {
  const SafetyVerifiedMark({super.key, this.chevron = false});

  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 16, color: palette.success),
        const SizedBox(width: VeilSpace.xxs),
        Text(
          AppLocalizations.of(context).safetyNumbersVerified,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: palette.success),
        ),
        if (chevron) Icon(Icons.chevron_right, size: 20, color: palette.textSubtle),
      ],
    );
  }
}

/// The two quiet buttons under a number: copy this phone's code for the
/// contact to paste, and paste theirs to compare (null while it can't).
class SafetyCodeButtons extends StatelessWidget {
  const SafetyCodeButtons({super.key, required this.onCopy, required this.onPaste});

  final VoidCallback onCopy;
  final VoidCallback? onPaste;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: VeilSpace.xs,
      children: [
        TextButton(key: const ValueKey('safety-copy-code'), onPressed: onCopy, child: Text(l10n.safetyNumbersCopyCode)),
        TextButton(key: const ValueKey('safety-paste-code'), onPressed: onPaste, child: Text(l10n.safetyNumbersScanAction)),
      ],
    );
  }
}
