import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/crypto/crypto_adapter_registry.dart';
import '../../../core/notifications/remote_push_service.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../app_lock/data/lock_request_provider.dart';
import '../../safety/presentation/blocked_accounts_screen.dart';
import 'settings_danger_zone.dart';

/// The settings tab, as Signal and WhatsApp lay theirs out: the account,
/// then sections of rows with their values, one line under a row only
/// where the value needs it, and the two account actions last.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final privacy = ref.watch(privacyPreferencesProvider);

    return VeilShell(
      title: l10n.settingsTitle,
      grouped: true,
      // On a wide screen one centred column, as on a phone.
      maxWidth: 600,
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
                switchValue: privacy.sendTypingIndicators,
                onSwitch: privacy.setSendTypingIndicators,
              ),
              const BlockedAccountsSettingsRow(),
            ],
          ),
          const _SecurityGroup(),
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
      onTap: () => context.push('/profile'),
    );
  }
}

String _themeModeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
      ThemeMode.light => l10n.themeModeLight,
      ThemeMode.dark => l10n.themeModeDark,
      ThemeMode.system => l10n.themeModeSystem,
    };

/// The theme, with the one in use as the row's value; a tap offers the
/// three in a sheet with a check on the current one.
class _ThemeModeRow extends ConsumerWidget {
  const _ThemeModeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(themeModeProvider);
    return VeilRow(
      key: const ValueKey('settings-theme'),
      title: l10n.themeModeTitle,
      value: _themeModeLabel(l10n, mode),
      onTap: () async {
        final chosen = await showThemeModeSheet(context, current: mode);
        if (chosen != null) ref.read(themeModeProvider.notifier).setThemeMode(chosen);
      },
    );
  }
}

/// Light, Dark and System, the [current] one ticked. Completes with the
/// chosen mode, or null when the sheet is dismissed.
Future<ThemeMode?> showThemeModeSheet(BuildContext context, {required ThemeMode current}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<ThemeMode>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final palette = VeilPalette.forBrightness(theme.brightness);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.md, 0, VeilSpace.md, VeilSpace.xs),
              child: Text(l10n.themeModeTitle, style: theme.textTheme.titleLarge),
            ),
            VeilGroup(
              children: [
                for (final mode in const [ThemeMode.light, ThemeMode.dark, ThemeMode.system])
                  Semantics(
                    selected: mode == current,
                    child: VeilRow(
                      key: ValueKey('theme-mode-${mode.name}'),
                      title: _themeModeLabel(l10n, mode),
                      trailing: mode == current
                          ? Icon(Icons.check, size: 20, color: palette.text)
                          : const SizedBox(width: 20),
                      onTap: () {
                        VeilHaptics.selection();
                        Navigator.of(sheetContext).pop(mode);
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: VeilSpace.xs),
          ],
        ),
      );
    },
  );
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

/// The lock, and what this phone does about screenshots, the app switcher
/// and notifications, each as a value. Only the app lock can be changed;
/// the others say what this build and phone do. The one footer line says
/// what the encryption is.
class _SecurityGroup extends ConsumerWidget {
  const _SecurityGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final local = ref.watch(localSecuritySnapshotProvider).valueOrNull;
    // The build's push service: the disabled one never gets a token, so
    // nothing wakes the app while it is closed.
    final pushConnected = ref.watch(remotePushServiceProvider) is! DisabledRemotePushService;
    final testBuild = cryptoAdapterKindOf(ref.watch(cryptoAdapterProvider).adapterId) == CryptoAdapterKind.development;

    // Locking opens the lock screen, which asks for the PIN, or has one
    // chosen while this phone has none (and then can be cancelled, as the
    // user asked for it here); unlocking comes back here.
    void lockNow() {
      ref.read(lockRequestedInSettingsProvider.notifier).state = true;
      ref.read(appSessionProvider.notifier).lock();
      context.go('/lock');
    }

    // Blocked where the platform can block them (Android); where it can't
    // (iPhone), the others in a chat are told of one instead.
    final screenshotsBlocked =
        local == null ? null : local.screenCaptureProtectionSupported && local.screenCaptureProtectionEnabled;

    return VeilGroup(
      header: l10n.settingsSectionSecurity,
      footer: testBuild ? l10n.securityFooterTestBuild : l10n.securityFooterUnaudited,
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
          key: const ValueKey('settings-screenshots'),
          title: l10n.securityStatusScreenCapture,
          subtitle: local != null && !local.screenCaptureProtectionSupported ? l10n.securityScreenshotsNotice : null,
          // Nothing until the phone has answered, rather than a guess.
          value: switch (screenshotsBlocked) {
            true => l10n.securityStatusBlocked,
            false => l10n.securityStatusScreenCaptureNotBlocked,
            null => null,
          },
        ),
        VeilRow(
          key: const ValueKey('settings-app-preview'),
          title: l10n.securityStatusAppPreview,
          value: switch (local?.appPreviewProtectionEnabled) {
            true => l10n.securityStatusAppPreviewProtected,
            false => l10n.securityStatusAppPreviewPartial,
            null => null,
          },
        ),
        VeilRow(
          key: const ValueKey('settings-notifications'),
          title: l10n.securityStatusPushDelivery,
          value: pushConnected ? l10n.securityStatusPushDeliveryOn : l10n.securityNotificationsWhileOpen,
        ),
      ],
    );
  }
}

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
