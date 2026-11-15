import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/trusted_devices.dart';

/// A device's last activity as the server keeps it: the UTC day only, so it
/// is shown as that day, never as a local time of day that never happened
/// (or the day before, west of UTC).
String deviceUtcDay(String locale, DateTime at) => '${DateFormat.MMMd(locale).format(at.toUtc())} (UTC)';

/// A moment on this device's clock: the day and the time.
String _localTime(String locale, DateTime at) {
  final local = at.toLocal();
  return '${DateFormat.MMMd(locale).format(local)}, ${DateFormat('HH:mm').format(local)}';
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

/// What kind of device it is, the one icon a device row carries.
IconData _platformIcon(String platform) => switch (platform) {
      'ios' => Icons.phone_iphone_outlined,
      'android' => Icons.phone_android_outlined,
      'macos' || 'windows' || 'linux' => Icons.laptop_outlined,
      _ => Icons.devices_other_outlined,
    };

/// A device's state as a word in its tone, or null for a device that is
/// simply trusted: only what is worth a look is said.
(String, VeilTone)? _status(AppLocalizations l10n, DeviceTrustState state) => switch (state) {
      DeviceTrustState.current => (l10n.settingsDeviceStateCurrent, VeilTone.info),
      DeviceTrustState.preferred => (l10n.settingsDeviceStatePreferred, VeilTone.info),
      DeviceTrustState.trusted => null,
      DeviceTrustState.stale => (l10n.settingsDeviceStateStale, VeilTone.warn),
      DeviceTrustState.revoked => (l10n.settingsDeviceStateRevoked, VeilTone.danger),
    };

Widget _kindIcon(String platform) => Icon(_platformIcon(platform), size: VeilIconSize.md);

/// One device of the account in the settings list: what kind it is, its
/// name, when it was last seen (or what it is, for this phone, or when it
/// was revoked), and its state as a word.
class DeviceRow extends StatelessWidget {
  const DeviceRow({super.key, required this.device, this.onTap});

  final TrustedDevice device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final subtitle = switch (device.trustState) {
      DeviceTrustState.current => _platformLabel(device.platform),
      DeviceTrustState.revoked when device.revokedAt != null =>
        l10n.settingsDeviceRevokedAt(_localTime(locale, device.revokedAt!)),
      _ => l10n.settingsDeviceSeen(deviceUtcDay(locale, device.lastSeenAt)),
    };
    return VeilRow(
      leading: _kindIcon(device.platform),
      // The name its owner gave it: drawn as typed.
      title: device.deviceName,
      subtitle: subtitle,
      status: _status(l10n, device.trustState),
      onTap: onTap,
    );
  }
}

/// One device on the devices screen, as one group: the device and its
/// state, what the server knows of when it was added, seen and approved,
/// and, for another device still trusted, the row that revokes it. A
/// preferred or a stale device says under the group what that means.
class DeviceDetailsGroup extends StatelessWidget {
  const DeviceDetailsGroup({super.key, required this.device, this.onRevoke});

  final TrustedDevice device;

  /// Null for this device and for one already revoked.
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final locale = l10n.localeName;
    final facts = [
      l10n.settingsDeviceCreated(_localTime(locale, device.createdAt)),
      l10n.settingsDeviceSeen(deviceUtcDay(locale, device.lastSeenAt)),
      if (device.lastSyncAt case final at?) l10n.settingsDeviceSynced(deviceUtcDay(locale, at)),
      l10n.settingsDeviceActivity(deviceUtcDay(locale, device.lastTrustedActivityAt)),
      if (device.trustedAt case final at?) l10n.settingsDeviceTrustedAt(_localTime(locale, at)),
      if (device.joinedFromDeviceId case final id?) l10n.settingsDeviceJoinedFrom(device.joinedFromDeviceName ?? id),
      if (device.revokedAt case final at?) l10n.settingsDeviceRevokedAt(_localTime(locale, at)),
    ];
    final note = switch (device.trustState) {
      DeviceTrustState.preferred => l10n.settingsDeviceNotePreferred,
      DeviceTrustState.stale => l10n.settingsDeviceNoteStale,
      _ => null,
    };
    final factStyle = theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted);

    return VeilGroup(
      footer: note,
      children: [
        VeilRow(
          leading: _kindIcon(device.platform),
          title: device.deviceName,
          subtitle: _platformLabel(device.platform),
          status: _status(l10n, device.trustState),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final fact in facts) Text(fact, style: factStyle)],
          ),
        ),
        if (onRevoke != null) VeilRow(title: l10n.settingsDeviceRevokeAction, destructive: true, onTap: onRevoke),
      ],
    );
  }
}
