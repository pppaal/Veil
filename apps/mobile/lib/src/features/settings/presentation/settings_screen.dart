import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_grouped.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/trusted_devices.dart';
import 'settings_danger_zone.dart';

/// The settings tab: what the user changes day to day first (appearance,
/// privacy, the lock), then the devices of the account, and last, set apart,
/// what cannot be undone.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final privacy = ref.watch(privacyPreferencesProvider);
    const gap = SizedBox(height: VeilSpace.lg);

    return VeilShell(
      title: l10n.settingsTitle,
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.md, VeilSpace.lg, VeilSpace.xl),
        children: [
          const VeilGroup(children: [_ProfileRow()]),
          gap,
          VeilGroup(label: l10n.settingsSectionAppearance, children: const [_ThemeModeSelector()]),
          gap,
          VeilGroup(
            label: l10n.settingsSectionPrivacy,
            children: [
              VeilGroupSwitchRow(
                icon: Icons.done_all_rounded,
                title: l10n.settingsReadReceiptsTitle,
                subtitle: l10n.settingsReadReceiptsSubtitle,
                value: privacy.sendReadReceipts,
                onChanged: privacy.setSendReadReceipts,
              ),
              VeilGroupSwitchRow(
                icon: Icons.keyboard_outlined,
                title: l10n.settingsTypingIndicatorsTitle,
                subtitle: l10n.settingsTypingIndicatorsSubtitle,
                value: privacy.sendTypingIndicators,
                onChanged: privacy.setSendTypingIndicators,
              ),
            ],
          ),
          gap,
          VeilGroup(
            label: l10n.settingsSectionSecurity,
            children: [
              VeilGroupRow(
                icon: Icons.lock_outline,
                title: l10n.settingsAppLockTitle,
                subtitle: l10n.settingsAppLockSubtitle,
                onTap: () => context.push('/lock'),
              ),
              VeilGroupRow(
                icon: Icons.visibility_off_outlined,
                title: l10n.settingsLockNow,
                subtitle: l10n.settingsLockNowSubtitle,
                onTap: () {
                  ref.read(appSessionProvider.notifier).lock();
                  context.go('/lock');
                },
              ),
              VeilGroupRow(
                icon: Icons.verified_user_outlined,
                title: l10n.settingsSecurityStatusTitle,
                subtitle: l10n.settingsSecurityStatusSubtitle,
                onTap: () => context.push('/security-status'),
              ),
            ],
          ),
          gap,
          VeilGroup(
            label: l10n.settingsSectionDevices,
            children: [
              const _TrustedDevicesRow(),
              VeilGroupRow(
                icon: Icons.phonelink_lock_outlined,
                title: l10n.settingsDeviceTransferTitle,
                subtitle: l10n.settingsDeviceTransferSubtitle,
                onTap: () => context.push('/device-transfer'),
              ),
            ],
          ),
          gap,
          VeilGroup(
            label: l10n.settingsSectionTools,
            children: [
              VeilGroupRow(
                icon: Icons.link_outlined,
                title: l10n.oneTimeLinkTitle,
                subtitle: l10n.oneTimeLinkSettingsSubtitle,
                onTap: () => context.push('/secret-link'),
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.xxl),
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
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final session = ref.watch(appSessionProvider);
    final handle = '@${session.handle ?? ''}';
    final name = session.displayName;
    final named = name != null && name.isNotEmpty;
    final initial = (named ? name : session.handle ?? '').characters.firstOrNull?.toUpperCase() ?? '?';

    return VeilGroupRow(
      key: const ValueKey('settings-profile'),
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.primarySoft,
          border: Border.all(color: palette.stroke),
        ),
        child: Text(initial, style: theme.textTheme.titleMedium?.copyWith(color: palette.primary)),
      ),
      title: named ? name : handle,
      // A name and a handle are the user's own words: drawn as typed.
      subtitleWidget: named
          ? Text(handle, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, color: palette.textMuted))
          : null,
      value: l10n.settingsProfileTitle,
      onTap: () => context.push('/profile'),
    );
  }
}

/// Light, dark, or whatever the system is set to. Three words on one line
/// at any phone width: a narrow phone drops the icons, never wraps a label.
class _ThemeModeSelector extends ConsumerWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final phone = context.veilPhoneWidth;
    ButtonSegment<ThemeMode> segment(ThemeMode mode, IconData icon, String label) => ButtonSegment<ThemeMode>(
          value: mode,
          icon: phone ? null : Icon(icon),
          label: Text(label, maxLines: 1, softWrap: false),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.sm, VeilSpace.md, VeilSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.themeModeTitle, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15)),
          const SizedBox(height: VeilSpace.xs),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: [
                segment(ThemeMode.light, Icons.light_mode_outlined, l10n.themeModeLight),
                segment(ThemeMode.dark, Icons.dark_mode_outlined, l10n.themeModeDark),
                segment(ThemeMode.system, Icons.brightness_auto_outlined, l10n.themeModeSystem),
              ],
              selected: {ref.watch(themeModeProvider)},
              showSelectedIcon: false,
              // A word each, set like a row's title: the wide spacing of a
              // label pulls Korean syllables apart.
              style: SegmentedButton.styleFrom(textStyle: Theme.of(context).textTheme.titleSmall),
              onSelectionChanged: (selection) {
                VeilHaptics.selection();
                ref.read(themeModeProvider.notifier).setThemeMode(selection.first);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// How many devices hold this account, leading to their list. A trusted
/// device that has gone quiet is flagged on the row itself, so the warning
/// is seen without opening the list.
class _TrustedDevicesRow extends ConsumerWidget {
  const _TrustedDevicesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final devices = ref.watch(trustedDevicesProvider);
    final list = devices.valueOrNull;
    final stale = list?.staleCount ?? 0;

    return VeilGroupRow(
      key: const ValueKey('settings-devices'),
      icon: Icons.devices_outlined,
      title: l10n.settingsDevicesTitle,
      subtitle: devices.hasError && !devices.isLoading
          ? l10n.settingsDeviceGraphUnavailable
          : list == null
              ? l10n.commonLoading
              : list.devices.isEmpty
                  ? l10n.settingsNoTrustedDevices
                  : l10n.settingsDevicesRowCount(list.activeCount),
      trailing: stale == 0
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                VeilStatusPill(label: l10n.settingsGraphStaleCount(stale), tone: VeilBannerTone.warn),
                const SizedBox(width: VeilSpace.xxs),
                Icon(Icons.chevron_right_rounded, size: VeilIconSize.md, color: context.veilPalette.textSubtle),
              ],
            ),
      // A route of its own, above the tab bar like every other screen a
      // settings row opens: the router can take it down again (a link that
      // opens another screen) and puts it back after an unlock.
      onTap: () => context.push('/trusted-devices'),
    );
  }
}
