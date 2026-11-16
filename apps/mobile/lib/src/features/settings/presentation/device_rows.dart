import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/trusted_devices.dart';

/// A day as a device line says it: "today", "yesterday", or "Apr 2". The
/// server keeps only the UTC day of a device's activity, so [utc] days
/// are compared in UTC and never shown with a time; a day this phone
/// recorded (when a device was added) is compared on its own clock.
String deviceDay(AppLocalizations l10n, DateTime at, {bool utc = true, DateTime? now}) {
  final day = utc ? at.toUtc() : at.toLocal();
  final clock = now ?? DateTime.now();
  final today = utc ? clock.toUtc() : clock.toLocal();
  final days = DateTime.utc(today.year, today.month, today.day).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  // Inside a sentence ("Last active today"), so in lower case.
  if (days == 0) return l10n.chatDayToday.toLowerCase();
  if (days == 1) return l10n.chatDayYesterday.toLowerCase();
  return DateFormat.MMMd(l10n.localeName).format(day);
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

/// The one grey line under a device's name: what this phone is and when it
/// was added; for another device, when it was last active, or since when
/// it has not been once it has gone quiet.
String deviceSubtitle(AppLocalizations l10n, TrustedDevice device, {DateTime? now}) => switch (device.trustState) {
      DeviceTrustState.current =>
        '${_platformLabel(device.platform)} · ${l10n.settingsDeviceCreated(deviceDay(l10n, device.createdAt, utc: false, now: now))}',
      DeviceTrustState.stale => l10n.settingsDeviceInactiveSince(deviceDay(l10n, device.lastSeenAt, now: now)),
      _ => l10n.settingsDeviceSeen(deviceDay(l10n, device.lastSeenAt, now: now)),
    };

/// One device of the account: its name and one grey line. No icon, no
/// state word and no colour, as Signal's linked devices.
class DeviceRow extends StatelessWidget {
  const DeviceRow({super.key, required this.device, this.onTap});

  final TrustedDevice device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilRow(
      // The name its owner gave it: drawn as typed.
      title: device.deviceName,
      subtitle: deviceSubtitle(l10n, device),
      // A tap asks to remove it: there is no screen behind it.
      trailing: onTap == null ? null : const SizedBox.shrink(),
      onTap: onTap,
    );
  }
}
