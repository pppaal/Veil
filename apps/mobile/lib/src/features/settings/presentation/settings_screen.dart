import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/trusted_devices.dart';
import 'device_rows.dart';
import 'settings_danger_zone.dart';

/// The settings tab, a grouped page: the account, then what is changed day
/// to day (appearance, privacy), the lock and the security of the account
/// with the one statement of what no one can recover, the devices that
/// hold the account, and last the actions that cannot be undone.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final privacy = ref.watch(privacyPreferencesProvider);

    return VeilShell(
      title: l10n.settingsTitle,
      grouped: true,
      child: ListView(
        padding: const EdgeInsets.only(top: VeilSpace.md, bottom: VeilSpace.xxl),
        children: [
          const VeilGroup(children: [_ProfileRow()]),
          VeilGroup(header: l10n.settingsSectionAppearance, children: const [_ThemeModeRow()]),
          VeilGroup(
            header: l10n.settingsSectionPrivacy,
            children: [
              VeilRow(
                title: l10n.settingsReadReceiptsTitle,
                subtitle: l10n.settingsReadReceiptsCaption,
                switchValue: privacy.sendReadReceipts,
                onSwitch: privacy.setSendReadReceipts,
              ),
              VeilRow(
                title: l10n.settingsTypingIndicatorsTitle,
                subtitle: l10n.settingsTypingIndicatorsCaption,
                switchValue: privacy.sendTypingIndicators,
                onSwitch: privacy.setSendTypingIndicators,
              ),
            ],
          ),
          VeilGroup(
            header: l10n.settingsSectionSecurity,
            // The one place Settings says what the account's security rests
            // on, and that nothing brings a lost account back.
            footer: '${l10n.securityFooterEncryption} ${l10n.securityFooterNoRecovery}',
            children: [
              const _AppLockRow(),
              VeilRow(
                key: const ValueKey('settings-lock-now'),
                title: l10n.settingsLockNow,
                // An action, not a screen: no chevron.
                trailing: const SizedBox.shrink(),
                onTap: () {
                  ref.read(appSessionProvider.notifier).lock();
                  context.go('/lock');
                },
              ),
              VeilRow(
                key: const ValueKey('settings-security-details'),
                title: l10n.settingsSecurityDetailsTitle,
                onTap: () => context.push('/security-status'),
              ),
              VeilRow(
                key: const ValueKey('settings-one-time-link'),
                title: l10n.oneTimeLinkTitle,
                onTap: () => context.push('/secret-link'),
              ),
            ],
          ),
          const _DevicesGroup(),
          const SettingsDangerZone(),
        ],
      ),
    );
  }
}

/// Who is signed in, leading to the profile.
class _ProfileRow extends ConsumerWidget {
  const _ProfileRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(appSessionProvider);
    final handle = session.handle ?? '';
    final name = session.displayName;
    final named = name != null && name.isNotEmpty;

    return VeilRow(
      key: const ValueKey('settings-profile'),
      leading: VeilAvatar(name: named ? name : handle, seed: handle),
      // A name and a handle are the user's own words: drawn as typed.
      title: named ? name : '@$handle',
      subtitle: named ? '@$handle' : null,
      value: l10n.settingsProfileTitle,
      onTap: () => context.push('/profile'),
    );
  }
}

/// Light, dark, or whatever the system is set to: three words beside the
/// row's title, on one line at any phone width.
class _ThemeModeRow extends ConsumerWidget {
  const _ThemeModeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    ButtonSegment<ThemeMode> segment(ThemeMode mode, String label) =>
        ButtonSegment<ThemeMode>(value: mode, label: Text(label, maxLines: 1, softWrap: false));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.xxs),
      child: Row(
        children: [
          Expanded(child: Text(l10n.themeModeTitle, style: theme.textTheme.titleMedium)),
          const SizedBox(width: VeilSpace.sm),
          SegmentedButton<ThemeMode>(
            segments: [
              segment(ThemeMode.light, l10n.themeModeLight),
              segment(ThemeMode.dark, l10n.themeModeDark),
              segment(ThemeMode.system, l10n.themeModeSystem),
            ],
            selected: {ref.watch(themeModeProvider)},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              VeilHaptics.selection();
              ref.read(themeModeProvider.notifier).setThemeMode(selection.first);
            },
          ),
        ],
      ),
    );
  }
}

/// The app lock, with whether it is on: a PIN set on this phone is a lock.
class _AppLockRow extends ConsumerWidget {
  const _AppLockRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hasPin = ref.watch(localSecuritySnapshotProvider).valueOrNull?.hasPin;
    return VeilRow(
      key: const ValueKey('settings-app-lock'),
      title: l10n.settingsAppLockTitle,
      // Nothing until the keystore has answered, rather than a guess.
      value: switch (hasPin) { true => l10n.commonOn, false => l10n.commonOff, null => null },
      onTap: () async {
        await context.push('/lock');
        // A PIN may have been set meanwhile.
        ref.invalidate(localSecuritySnapshotProvider);
      },
    );
  }
}

/// The devices that hold the account, a row each with its state, the one
/// notice while a device has gone quiet, and moving to a new phone. A
/// device row opens the list of devices with what the server knows of each.
class _DevicesGroup extends ConsumerWidget {
  const _DevicesGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final devices = ref.watch(trustedDevicesProvider);
    final list = devices.valueOrNull;
    // A route of its own, above the tab bar like every other screen a
    // settings row opens: the router can take it down again (a link that
    // opens another screen) and puts it back after an unlock.
    void openDevices() => context.push('/trusted-devices');

    return VeilGroup(
      header: l10n.settingsSectionDevices,
      children: [
        if (devices.hasError && !devices.isLoading)
          VeilNotice(
            title: l10n.settingsDeviceGraphUnavailable,
            message: l10n.settingsDeviceGraphLoadFailedBody,
            tone: VeilTone.warn,
            actionLabel: l10n.commonRetry,
            onAction: () => ref.invalidate(trustedDevicesProvider),
          )
        else if (list == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: VeilSpace.sm),
                  Text(l10n.settingsLoadingDeviceGraph,
                      style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
                ],
              ),
            ),
          )
        else if (list.devices.isEmpty)
          VeilRow(title: l10n.settingsNoTrustedDevices, onTap: openDevices)
        else ...[
          for (final device in list.devices)
            DeviceRow(key: ValueKey('settings-device-${device.id}'), device: device, onTap: openDevices),
          if (list.staleCount > 0)
            VeilNotice(
              key: const ValueKey('settings-devices-stale'),
              message: l10n.settingsDevicesStaleNotice(list.staleCount),
              tone: VeilTone.warn,
              actionLabel: l10n.settingsDevicesReview,
              onAction: openDevices,
            ),
        ],
        VeilRow(
          key: const ValueKey('settings-device-transfer'),
          title: l10n.settingsDeviceTransferTitle,
          onTap: () => context.push('/device-transfer'),
        ),
      ],
    );
  }
}
