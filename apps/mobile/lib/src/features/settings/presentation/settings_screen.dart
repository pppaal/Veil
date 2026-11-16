import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../app_lock/data/lock_request_provider.dart';
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
    // Locking opens the lock screen, which asks for the PIN, or has one
    // chosen while this phone has none (and then can be cancelled, as the
    // user asked for it here); unlocking comes back here.
    void lockNow() {
      ref.read(lockRequestedInSettingsProvider.notifier).state = true;
      ref.read(appSessionProvider.notifier).lock();
      context.go('/lock');
    }

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
            // on, where the account lives, and that nothing brings a lost
            // account back.
            footer: '${l10n.securityFooterEncryption} ${l10n.securityFooterDevice} ${l10n.securityFooterNoRecovery}',
            children: [
              _AppLockRow(onTurnOn: lockNow),
              VeilRow(
                key: const ValueKey('settings-lock-now'),
                title: l10n.settingsLockNow,
                // An action, not a screen: no chevron.
                trailing: const SizedBox.shrink(),
                onTap: lockNow,
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

/// Whether this phone has a PIN, which is what turns the app lock on. The
/// keystore is asked each time Settings opens and again whenever the app
/// locks or unlocks: the first PIN is chosen on the lock screen (after Lock
/// now, or the lock that follows the app into the background), and Settings
/// may still be on screen, or be put back, when the app is unlocked.
final _appLockOnProvider = FutureProvider.autoDispose<bool>((ref) {
  ref.watch(appSessionProvider.select((session) => session.locked));
  return ref.read(appLockServiceProvider).hasPin();
});

/// The app lock, with whether it is on. While it is off the row turns it
/// on: it locks the app, and the lock screen has a PIN chosen. Once it is
/// on there is nothing to set here, so the row only says so.
class _AppLockRow extends ConsumerWidget {
  const _AppLockRow({required this.onTurnOn});

  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(_appLockOnProvider).valueOrNull;
    return VeilRow(
      key: const ValueKey('settings-app-lock'),
      title: l10n.settingsAppLockTitle,
      // Nothing until the keystore has answered, rather than a guess.
      value: switch (on) { true => l10n.commonOn, false => l10n.commonOff, null => null },
      onTap: on == false ? onTurnOn : null,
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

    final listed = list != null && list.devices.isNotEmpty && !(devices.hasError && !devices.isLoading);
    return VeilGroup(
      header: l10n.settingsSectionDevices,
      // Each line belongs to the row above it: under a device, at its text.
      // The stale notice under the devices leads with an icon too, so the
      // line under it sits near its text as well; moving to a new phone is
      // the last row and has none.
      inset: listed ? deviceRowTextInset : VeilSpace.md,
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
