import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/trusted_devices.dart';

/// The day a device was last seen. The server keeps only the UTC day of a
/// device's activity, so it is shown as that day and never as a time of
/// day: a bare date already says it is a day, not a moment.
String deviceSeenDay(String locale, DateTime at) => DateFormat.MMMd(locale).format(at.toUtc());

/// The day of a moment on this phone's clock (when a device was added or
/// revoked).
String _localDay(String locale, DateTime at) => DateFormat.MMMd(locale).format(at.toLocal());

/// The one line under a device's name: what it is, for this phone; when it
/// was revoked, for one that is; when it was last seen, for the others.
String _deviceSubtitle(AppLocalizations l10n, TrustedDevice device) {
  final locale = l10n.localeName;
  return switch (device.trustState) {
    DeviceTrustState.current => _platformLabel(device.platform),
    DeviceTrustState.revoked when device.revokedAt != null =>
      l10n.settingsDeviceRevokedAt(_localDay(locale, device.revokedAt!)),
    _ => l10n.settingsDeviceSeen(deviceSeenDay(locale, device.lastSeenAt)),
  };
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

/// Where a [DeviceRow]'s text starts: the row's 16 gutter, the kind icon
/// and the theme's 12 gap after a leading. The hairlines between device
/// rows start here, under the text rather than under the icon.
const double deviceRowTextInset = VeilSpace.md + VeilIconSize.md + VeilSpace.sm;

/// One device of the account in the settings list: what kind it is, its
/// name, one line on when it was last seen (or what it is, for this phone,
/// or when it was revoked), and its state as a word.
class DeviceRow extends StatelessWidget {
  const DeviceRow({super.key, required this.device, this.onTap});

  final TrustedDevice device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilRow(
      leading: _kindIcon(device.platform),
      // The name its owner gave it: drawn as typed.
      title: device.deviceName,
      subtitle: _deviceSubtitle(l10n, device),
      status: _status(l10n, device.trustState),
      onTap: onTap,
    );
  }
}

/// One device on the devices screen, as one group: the device as the
/// settings list shows it, when it was added and which device approved it,
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
    final facts = [
      l10n.settingsDeviceCreated(_localDay(l10n.localeName, device.createdAt)),
      if (device.joinedFromDeviceId case final id?) l10n.settingsDeviceJoinedFrom(device.joinedFromDeviceName ?? id),
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
          subtitle: _deviceSubtitle(l10n, device),
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
