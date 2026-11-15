import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/trusted_devices.dart';

/// A device's last activity as the relay keeps it: the UTC day only, so it
/// is shown as that day, never as a local time of day that never happened
/// (or the day before, west of UTC).
String deviceUtcDay(String locale, DateTime at) => '${DateFormat.MMMd(locale).format(at.toUtc())} (UTC)';

/// A moment on this device's clock, with the day in the app's language.
String _localTime(String locale, DateTime at) {
  final local = at.toLocal();
  return '${DateFormat.MMMd(locale).format(local)} | ${DateFormat('HH:mm').format(local)}';
}

/// A platform's name, which is a trademark and written the same everywhere.
String _platformLabel(String platform) => switch (platform) {
      'ios' => 'iPhone / iPad',
      'android' => 'Android',
      'windows' => 'Windows',
      'macos' => 'macOS',
      'linux' => 'Linux',
      _ => platform,
    };

/// One device of the account: its name and state, when it was last heard
/// from, what its state means, and, for another device that is still
/// trusted, the button that revokes it.
class TrustedDeviceCard extends StatelessWidget {
  const TrustedDeviceCard({super.key, required this.device, this.onRevoke});

  final TrustedDevice device;

  /// Null for this device and for one already revoked.
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final locale = l10n.localeName;
    final (state, tone, note) = switch (device.trustState) {
      DeviceTrustState.current => (l10n.settingsDeviceStateCurrent, VeilBannerTone.good, l10n.settingsDeviceNoteCurrent),
      DeviceTrustState.preferred => (
          l10n.settingsDeviceStatePreferred,
          VeilBannerTone.info,
          l10n.settingsDeviceNotePreferred
        ),
      DeviceTrustState.trusted => (l10n.settingsDeviceStateTrusted, VeilBannerTone.info, l10n.settingsDeviceNoteTrusted),
      DeviceTrustState.stale => (l10n.settingsDeviceStateStale, VeilBannerTone.warn, l10n.settingsDeviceNoteStale),
      DeviceTrustState.revoked => (l10n.settingsDeviceStateRevoked, VeilBannerTone.danger, l10n.settingsDeviceNoteRevoked),
    };
    final facts = [
      l10n.settingsDeviceCreated(_localTime(locale, device.createdAt)),
      l10n.settingsDeviceSeen(deviceUtcDay(locale, device.lastSeenAt)),
      if (device.lastSyncAt case final at?) l10n.settingsDeviceSynced(deviceUtcDay(locale, at)),
      l10n.settingsDeviceActivity(deviceUtcDay(locale, device.lastTrustedActivityAt)),
      if (device.trustedAt case final at?) l10n.settingsDeviceTrustedAt(_localTime(locale, at)),
      if (device.joinedFromDeviceId case final id?) l10n.settingsDeviceJoinedFrom(device.joinedFromDeviceName ?? id),
      if (device.revokedAt case final at?) l10n.settingsDeviceRevokedAt(_localTime(locale, at)),
    ];

    return VeilSurfaceCard(
      padding: const EdgeInsets.all(VeilSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The name its owner gave it: drawn as typed.
                    Text(device.deviceName, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      _platformLabel(device.platform),
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: VeilSpace.xs),
              VeilStatusPill(label: state, tone: tone),
            ],
          ),
          const SizedBox(height: VeilSpace.sm),
          Wrap(
            spacing: VeilSpace.sm,
            runSpacing: VeilSpace.xxs,
            children: [
              for (final fact in facts)
                Text(fact, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)),
            ],
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilCopy(note, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.45)),
          if (onRevoke != null) ...[
            const SizedBox(height: VeilSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.danger,
                  side: BorderSide(color: palette.danger.withValues(alpha: 0.45)),
                  minimumSize: const Size(88, 44),
                ),
                onPressed: onRevoke,
                child: Text(l10n.settingsDeviceRevokeAction),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
