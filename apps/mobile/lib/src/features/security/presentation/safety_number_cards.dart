import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// A safety number in its groups of digits, under a label.
class SafetyNumberCard extends StatelessWidget {
  const SafetyNumberCard({super.key, required this.groups, this.label});

  final List<String> groups;

  /// Says which number this is while two are on screen.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label ?? l10n.safetyNumbersCardLabel,
            style: TextStyle(color: palette.textSubtle, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4),
          ),
          const SizedBox(height: VeilSpace.sm),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final g in groups)
                Text(
                  g,
                  style: TextStyle(
                    color: palette.text,
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 1.2,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Whether the contact counts as verified, as a pill, with their handle
/// beside it: what the "Verified on" card under it says, and the mark in
/// the chat. [warn] colours "unverified" as a warning, for a page that has
/// one up (a change to review, a directory that serves another key, a scan
/// that did not match).
class SafetyVerifiedStateRow extends StatelessWidget {
  const SafetyVerifiedStateRow({super.key, required this.handle, required this.verified, required this.warn});

  final String handle;
  final bool verified;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        VeilStatusPill(
          label: verified ? l10n.safetyNumbersVerified : l10n.safetyNumbersUnverified,
          tone: verified
              ? VeilBannerTone.good
              : warn
                  ? VeilBannerTone.warn
                  : VeilBannerTone.info,
        ),
        const SizedBox(width: VeilSpace.xs),
        Expanded(
          child: Text(
            '@$handle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.veilPalette.textMuted),
          ),
        ),
      ],
    );
  }
}

/// How to compare the number above it, and what a mismatch means: said
/// under the number, in line with the digits, before the button that
/// records the comparison.
class SafetyCompareNote extends StatelessWidget {
  const SafetyCompareNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xxs),
      child: VeilCopy(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.veilPalette.textMuted),
      ),
    );
  }
}

/// The QR code the peer scans to compare both identities in one step.
class SafetyQrCard extends StatelessWidget {
  const SafetyQrCard({super.key, required this.content, required this.palette});

  final String content;
  final VeilPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.safetyNumbersScanLabel,
              style: TextStyle(
                color: palette.textSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          Container(
            padding: const EdgeInsets.all(VeilSpace.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(VeilRadius.md),
            ),
            child: QrImageView(
              data: content,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilCopy(
            l10n.safetyNumbersQrNote,
            style: TextStyle(color: palette.textSubtle, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// When the pinned identity was verified, and what ends that.
class SafetyVerifiedCard extends StatelessWidget {
  const SafetyVerifiedCard({super.key, required this.verifiedOn});

  /// The day and time of the verification, already formatted.
  final String verifiedOn;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeilCopy(
            l10n.safetyNumbersVerifiedOn(verifiedOn),
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: VeilSpace.xs),
          VeilCopy(
            l10n.safetyNumbersVerifiedNote,
            style: TextStyle(color: palette.textSubtle, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Starting a fresh session with the contact's current keys: what it does,
/// and the button for it.
class SafetyNewSessionCard extends StatelessWidget {
  const SafetyNewSessionCard({super.key, required this.renewing, required this.onRenew});

  final bool renewing;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.safetyNumbersRotateEyebrow,
            style: TextStyle(
              color: palette.textSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: VeilSpace.xs),
          VeilCopy(
            l10n.safetyNumbersRotateBody,
            style: TextStyle(color: palette.textSubtle, fontSize: 13),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilButton(
            label: renewing ? l10n.safetyNumbersRotating : l10n.safetyNumbersRotateButton,
            tone: VeilButtonTone.secondary,
            onPressed: renewing ? null : onRenew,
          ),
        ],
      ),
    );
  }
}
