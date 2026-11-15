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
