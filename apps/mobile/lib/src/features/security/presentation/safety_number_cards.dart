import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

// The parts of the safety number page: who it is about, the number, and the
// code to scan. Plain parts on the page: no card around any of them.

/// Who the safety number is about: their avatar, name and handle, and
/// whether they are verified, as a word.
class SafetyPeerHeader extends StatelessWidget {
  const SafetyPeerHeader({super.key, required this.name, required this.handle, required this.verified});

  final String name;
  final String handle;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        VeilAvatar(name: name, seed: handle, size: 56),
        const SizedBox(width: VeilSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
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
        Text(
          verified ? l10n.safetyNumbersVerified : l10n.safetyNumbersUnverified,
          style: theme.textTheme.labelMedium?.copyWith(color: verified ? palette.success : palette.textMuted),
        ),
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

/// The QR code the contact scans to compare both identities in one step,
/// on a white panel in both themes, and what it holds.
class SafetyQrCard extends StatelessWidget {
  const SafetyQrCard({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Container(
          width: 220,
          height: 220,
          padding: const EdgeInsets.all(VeilSpace.sm),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(VeilRadius.md)),
          child: QrImageView(data: content, version: QrVersions.auto, backgroundColor: Colors.white),
        ),
        const SizedBox(height: VeilSpace.xs),
        Text(
          l10n.safetyNumbersQrNote,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.veilPalette.textMuted),
        ),
      ],
    );
  }
}
