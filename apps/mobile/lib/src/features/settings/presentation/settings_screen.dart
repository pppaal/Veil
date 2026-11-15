import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<_DeviceGraphSnapshot>? _deviceGraphFuture;
  final _wipeConfirmController = TextEditingController();
  final _revokeConfirmController = TextEditingController();
  final _deleteAccountConfirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _deviceGraphFuture = _loadDeviceGraph();
  }

  @override
  void dispose() {
    _wipeConfirmController.dispose();
    _revokeConfirmController.dispose();
    _deleteAccountConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final privacy = ref.watch(privacyPreferencesProvider);
    final l10n = AppLocalizations.of(context);

    return VeilShell(
      title: l10n.settingsTitle,
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.settingsEyebrow,
            title: session.displayName ?? '@${session.handle ?? 'unbound'}',
            body: session.deviceId == null
                ? l10n.settingsNoDeviceBound
                : l10n.settingsCurrentDevice(session.deviceId!),
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.pillNoRecovery),
                VeilStatusPill(label: l10n.pillDeviceBound),
                VeilStatusPill(label: l10n.settingsPillPrivateByDesign),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilListTileCard(
            key: const ValueKey('settings-profile'),
            title: l10n.settingsProfileTitle,
            subtitle: l10n.settingsProfileSubtitle,
            leading: const Icon(Icons.person_outline_rounded),
            onTap: () => context.push('/profile'),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSectionLabel(l10n.settingsSectionDeviceGraph),
          const SizedBox(height: VeilSpace.sm),
          FutureBuilder<_DeviceGraphSnapshot>(
            future: _deviceGraphFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return VeilLoadingBlock(
                  title: l10n.settingsLoadingDeviceGraph,
                  body: l10n.settingsLoadingDeviceGraphBody,
                );
              }

              if (snapshot.hasError) {
                return VeilSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VeilInlineBanner(
                        title: l10n.settingsDeviceGraphUnavailable,
                        message: l10n.settingsDeviceGraphLoadFailedBody,
                        tone: VeilBannerTone.warn,
                      ),
                      const SizedBox(height: VeilSpace.md),
                      OutlinedButton(
                        onPressed: _refreshDeviceGraph,
                        child: Text(l10n.commonRetry),
                      ),
                    ],
                  ),
                );
              }

              final snapshotValue =
                  snapshot.data ?? const _DeviceGraphSnapshot.empty();
              if (snapshotValue.devices.isEmpty) {
                return VeilEmptyState(
                  title: l10n.settingsNoTrustedDevices,
                  body: l10n.settingsNoTrustedDevicesBody,
                  icon: Icons.devices_outlined,
                );
              }

              return Column(
                children: [
                  _DeviceGraphSummaryCard(
                    devices: snapshotValue.devices,
                    currentDeviceId: session.deviceId,
                  ),
                  const SizedBox(height: VeilSpace.sm),
                  for (var index = 0;
                      index < snapshotValue.devices.length;
                      index++) ...[
                    if (index > 0) const SizedBox(height: VeilSpace.sm),
                    _DeviceRowCard(
                      device: snapshotValue.devices[index],
                      onRevoke: snapshotValue.devices[index].trustState ==
                                  _DeviceTrustState.current ||
                              snapshotValue.devices[index].trustState ==
                                  _DeviceTrustState.revoked
                          ? null
                          : () => _confirmAndRevokeDevice(
                              snapshotValue.devices[index]),
                    ),
                  ],
                  const SizedBox(height: VeilSpace.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _refreshDeviceGraph,
                      child: Text(l10n.settingsRefreshDeviceGraph),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSectionLabel(l10n.themeModeTitle),
          const SizedBox(height: VeilSpace.sm),
          VeilSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.themeModeSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.veilPalette.textSubtle,
                      ),
                ),
                const SizedBox(height: VeilSpace.md),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        icon: context.veilPhoneWidth ? null : const Icon(Icons.light_mode_outlined),
                        label: Text(l10n.themeModeLight, maxLines: 1, softWrap: false),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        icon: context.veilPhoneWidth ? null : const Icon(Icons.dark_mode_outlined),
                        label: Text(l10n.themeModeDark, maxLines: 1, softWrap: false),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.system,
                        icon: context.veilPhoneWidth ? null : const Icon(Icons.brightness_auto_outlined),
                        label: Text(l10n.themeModeSystem, maxLines: 1, softWrap: false),
                      ),
                    ],
                    selected: {themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      VeilHaptics.selection();
                      ref.read(themeModeProvider.notifier).setThemeMode(selection.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSectionLabel(l10n.settingsSectionPrivacy),
          const SizedBox(height: VeilSpace.sm),
          VeilActionCluster(
            children: [
              VeilListTileCard(
                title: l10n.settingsReadReceiptsTitle,
                subtitle: l10n.settingsReadReceiptsSubtitle,
                leading: const Icon(Icons.done_all_rounded),
                trailing: Switch.adaptive(
                  value: privacy.sendReadReceipts,
                  onChanged: privacy.setSendReadReceipts,
                ),
              ),
              VeilListTileCard(
                title: l10n.settingsTypingIndicatorsTitle,
                subtitle: l10n.settingsTypingIndicatorsSubtitle,
                leading: const Icon(Icons.keyboard_outlined),
                trailing: Switch.adaptive(
                  value: privacy.sendTypingIndicators,
                  onChanged: privacy.setSendTypingIndicators,
                ),
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSectionLabel(l10n.settingsSectionSecurity),
          const SizedBox(height: VeilSpace.sm),
          VeilActionCluster(
            children: [
              VeilListTileCard(
                title: l10n.settingsAppLockTitle,
                subtitle: l10n.settingsAppLockSubtitle,
                leading: const Icon(Icons.lock_outline),
                onTap: () => context.push('/lock'),
              ),
              VeilListTileCard(
                title: l10n.settingsDeviceTransferTitle,
                subtitle: l10n.settingsDeviceTransferSubtitle,
                leading: const Icon(Icons.phonelink_lock_outlined),
                onTap: () => context.push('/device-transfer'),
              ),
              VeilListTileCard(
                title: l10n.settingsSecurityStatusTitle,
                subtitle: l10n.settingsSecurityStatusSubtitle,
                leading: const Icon(Icons.verified_user_outlined),
                onTap: () => context.push('/security-status'),
              ),
              VeilListTileCard(
                title: l10n.oneTimeLinkTitle,
                subtitle: l10n.oneTimeLinkSettingsSubtitle,
                leading: const Icon(Icons.link_outlined),
                onTap: () => context.push('/secret-link'),
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSectionLabel(l10n.settingsSectionSession),
          const SizedBox(height: VeilSpace.sm),
          VeilDestructiveNotice(
            title: l10n.settingsNoRecoveryPath,
            body: l10n.settingsDestructiveNoticeBody,
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilActionCluster(
            children: [
              VeilListTileCard(
                title: l10n.settingsLockNow,
                subtitle: l10n.settingsLockNowSubtitle,
                leading: const Icon(Icons.visibility_off_outlined),
                onTap: () {
                  ref.read(appSessionProvider.notifier).lock();
                  context.go('/lock');
                },
              ),
              VeilListTileCard(
                title: l10n.settingsWipeLocal,
                subtitle: l10n.settingsWipeLocalSubtitle,
                leading: Icon(
                  Icons.layers_clear_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                destructive: true,
                onTap: () async {
                  final confirmed = await _confirmDestructiveAction(
                    controller: _wipeConfirmController,
                    context: context,
                    title: l10n.settingsWipeConfirmTitle,
                    body: l10n.settingsWipeConfirmBody,
                    confirmVerb: l10n.settingsWipeConfirmAction,
                    expectedPhrase: 'WIPE',
                  );

                  if (confirmed != true) {
                    return;
                  }

                  await ref.read(appSessionProvider.notifier).wipeLocalDeviceState();
                  if (context.mounted) {
                    context.go('/splash');
                  }
                },
              ),
              VeilListTileCard(
                title: l10n.settingsRevokeTitle,
                subtitle: l10n.settingsRevokeSubtitle,
                leading: Icon(
                  Icons.phonelink_erase_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                destructive: true,
                onTap: () async {
                  final confirmed = await _confirmDestructiveAction(
                    controller: _revokeConfirmController,
                    context: context,
                    title: l10n.settingsRevokeConfirmTitle,
                    body: l10n.settingsRevokeConfirmBody,
                    confirmVerb: l10n.settingsRevokeConfirmAction,
                    expectedPhrase: 'REVOKE',
                  );

                  if (confirmed != true) {
                    return;
                  }

                  try {
                    await ref.read(appSessionProvider.notifier).revokeCurrentDevice();
                    if (context.mounted) {
                      context.go('/create-account');
                    }
                  } catch (_) {
                    // The relay did not revoke it, so this device keeps its
                    // state; one it already dropped has been signed out.
                    if (!context.mounted) return;
                    VeilToast.show(
                      context,
                      message: l10n.commonError,
                      tone: VeilBannerTone.warn,
                    );
                  }
                },
              ),
              VeilListTileCard(
                title: l10n.settingsLogout,
                subtitle: l10n.settingsLogoutSubtitle,
                leading: const Icon(Icons.logout),
                onTap: () async {
                  await ref.read(appSessionProvider.notifier).logout();
                  if (context.mounted) {
                    context.go('/create-account');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSectionLabel(l10n.settingsDeleteAccountTitle),
          const SizedBox(height: VeilSpace.sm),
          VeilDestructiveNotice(
            title: l10n.settingsIrreversible,
            body: l10n.settingsDeleteAccountBody,
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilActionCluster(
            children: [
              VeilListTileCard(
                title: l10n.settingsDeleteAccountAction,
                subtitle: l10n.settingsDeleteAccountBody,
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                destructive: true,
                onTap: () async {
                  final confirmed = await _confirmDestructiveAction(
                    controller: _deleteAccountConfirmController,
                    context: context,
                    title: l10n.settingsDeleteAccountConfirmHeadline,
                    body: l10n.settingsDeleteAccountBody,
                    confirmVerb: l10n.settingsDeleteAccountAction,
                    expectedPhrase: 'DELETE',
                  );

                  if (confirmed != true) return;

                  try {
                    await ref.read(appSessionProvider.notifier).deleteAccount();
                    if (context.mounted) {
                      context.go('/splash');
                    }
                  } catch (_) {
                    if (!context.mounted) return;
                    VeilToast.show(
                      context,
                      message: l10n.commonError,
                      tone: VeilBannerTone.warn,
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshDeviceGraph() async {
    setState(() {
      _deviceGraphFuture = _loadDeviceGraph();
    });
    await _deviceGraphFuture;
  }

  Future<bool?> _confirmDestructiveAction({
    required BuildContext context,
    required TextEditingController controller,
    required String title,
    required String body,
    required String confirmVerb,
    required String expectedPhrase,
  }) {
    controller.clear();
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final confirmedPhrase =
              controller.text.trim().toUpperCase() == expectedPhrase;
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body),
                const SizedBox(height: VeilSpace.md),
                Text(l10n.settingsTypePhraseToContinue(expectedPhrase)),
                const SizedBox(height: VeilSpace.sm),
                TextField(
                  controller: controller,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: expectedPhrase,
                    hintText: expectedPhrase,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: confirmedPhrase
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: Text(confirmVerb),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAndRevokeDevice(_TrustedDevice device) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsRevokeListedTitle(device.deviceName)),
        content: Text(l10n.settingsRevokeListedBody(device.deviceName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsRevokeConfirmAction),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await ref.read(appSessionProvider.notifier).revokeListedDevice(device.id);
      await _refreshDeviceGraph();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsRevokeListedDone(device.deviceName))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      VeilToast.show(
        context,
        message: l10n.settingsRevokeListedFailed,
        tone: VeilBannerTone.warn,
      );
    }
  }

  Future<_DeviceGraphSnapshot> _loadDeviceGraph() async {
    final session = ref.read(appSessionProvider);
    final accessToken = session.accessToken;
    if (accessToken == null) {
      return const _DeviceGraphSnapshot.empty();
    }

    final response = await ref.read(apiClientProvider).listDevices(accessToken);
    final items = (response['items'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>()
        .map(_TrustedDevice.fromJson)
        .toList(growable: false)
      ..sort(_compareTrustedDevices);

    return _DeviceGraphSnapshot(
      activeDeviceId: response['activeDeviceId'] as String?,
      devices: items,
    );
  }
}

/// A device's last activity as the server keeps it: the UTC day only, so it
/// is shown as that day, never as a local time of day that never happened
/// (or the day before, west of UTC).
String _utcDay(String locale, DateTime at) => '${DateFormat.MMMd(locale).format(at.toUtc())} (UTC)';

/// A moment on this device's clock, with the day in the app's language.
String _localTime(String locale, DateTime at) {
  final local = at.toLocal();
  return '${DateFormat.MMMd(locale).format(local)} | ${DateFormat('HH:mm').format(local)}';
}

int _compareTrustedDevices(_TrustedDevice left, _TrustedDevice right) {
  final trustOrder = <_DeviceTrustState, int>{
    _DeviceTrustState.current: 0,
    _DeviceTrustState.preferred: 1,
    _DeviceTrustState.trusted: 2,
    _DeviceTrustState.stale: 3,
    _DeviceTrustState.revoked: 4,
  };

  final trustDelta = (trustOrder[left.trustState] ?? 99) -
      (trustOrder[right.trustState] ?? 99);
  if (trustDelta != 0) {
    return trustDelta;
  }

  return right.lastTrustedActivityAt.compareTo(left.lastTrustedActivityAt);
}

class _DeviceRowCard extends StatelessWidget {
  const _DeviceRowCard({
    required this.device,
    this.onRevoke,
  });

  final _TrustedDevice device;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final statusTone = switch (device.trustState) {
      _DeviceTrustState.current => VeilBannerTone.good,
      _DeviceTrustState.preferred => VeilBannerTone.info,
      _DeviceTrustState.trusted => VeilBannerTone.info,
      _DeviceTrustState.stale => VeilBannerTone.warn,
      _DeviceTrustState.revoked => VeilBannerTone.danger,
    };
    final statusLabel = switch (device.trustState) {
      _DeviceTrustState.current => l10n.settingsDeviceStateCurrent,
      _DeviceTrustState.preferred => l10n.settingsDeviceStatePreferred,
      _DeviceTrustState.trusted => l10n.settingsDeviceStateTrusted,
      _DeviceTrustState.stale => l10n.settingsDeviceStateStale,
      _DeviceTrustState.revoked => l10n.settingsDeviceStateRevoked,
    };

    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  device.deviceName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (onRevoke != null) ...[
                TextButton(
                  onPressed: onRevoke,
                  child: Text(l10n.settingsDeviceRevokeAction),
                ),
                const SizedBox(width: VeilSpace.xs),
              ],
              VeilStatusPill(label: statusLabel, tone: statusTone),
            ],
          ),
          const SizedBox(height: VeilSpace.xs),
          Text(
            _platformLabel(device.platform),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.veilPalette.textSubtle,
                ),
          ),
          const SizedBox(height: VeilSpace.md),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                l10n.settingsDeviceCreated(_localTime(locale, device.createdAt)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                l10n.settingsDeviceSeen(_utcDay(locale, device.lastSeenAt)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (device.lastSyncAt != null)
                Text(
                  l10n.settingsDeviceSynced(_utcDay(locale, device.lastSyncAt!)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Text(
                l10n.settingsDeviceActivity(_utcDay(locale, device.lastTrustedActivityAt)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (device.trustedAt != null)
                Text(
                  l10n.settingsDeviceTrustedAt(_localTime(locale, device.trustedAt!)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (device.joinedFromDeviceId != null)
                Text(
                  l10n.settingsDeviceJoinedFrom(device.joinedFromDeviceName ?? device.joinedFromDeviceId!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (device.revokedAt != null)
                Text(
                  l10n.settingsDeviceRevokedAt(_localTime(locale, device.revokedAt!)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: VeilSpace.sm),
          Text(
            switch (device.trustState) {
              _DeviceTrustState.current => l10n.settingsDeviceNoteCurrent,
              _DeviceTrustState.preferred => l10n.settingsDeviceNotePreferred,
              _DeviceTrustState.trusted => l10n.settingsDeviceNoteTrusted,
              _DeviceTrustState.stale => l10n.settingsDeviceNoteStale,
              _DeviceTrustState.revoked => l10n.settingsDeviceNoteRevoked,
            },
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _platformLabel(String platform) {
    switch (platform) {
      case 'ios':
        return 'iPhone / iPad';
      case 'android':
        return 'Android';
      case 'windows':
        return 'Windows';
      case 'macos':
        return 'macOS';
      case 'linux':
        return 'Linux';
      default:
        return platform;
    }
  }
}

class _TrustedDevice {
  const _TrustedDevice({
    required this.id,
    required this.deviceName,
    required this.platform,
    required this.isActive,
    required this.trustState,
    required this.createdAt,
    required this.lastSeenAt,
    this.revokedAt,
    this.trustedAt,
    this.joinedFromDeviceId,
    this.joinedFromDeviceName,
    this.joinedFromPlatform,
    this.lastSyncAt,
    required this.lastTrustedActivityAt,
  });

  final String id;
  final String deviceName;
  final String platform;
  final bool isActive;
  final _DeviceTrustState trustState;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;
  final DateTime? trustedAt;
  final String? joinedFromDeviceId;
  final String? joinedFromDeviceName;
  final String? joinedFromPlatform;
  final DateTime? lastSyncAt;
  final DateTime lastTrustedActivityAt;

  factory _TrustedDevice.fromJson(Map<String, dynamic> json) {
    return _TrustedDevice(
      id: json['id'] as String,
      deviceName: json['deviceName'] as String,
      platform: json['platform'] as String,
      isActive: json['isActive'] as bool? ?? false,
      trustState: _parseTrustState(json['trustState'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      revokedAt: json['revokedAt'] == null
          ? null
          : DateTime.parse(json['revokedAt'] as String),
      trustedAt: json['trustedAt'] == null
          ? null
          : DateTime.parse(json['trustedAt'] as String),
      joinedFromDeviceId: json['joinedFromDeviceId'] as String?,
      joinedFromDeviceName: json['joinedFromDeviceName'] as String?,
      joinedFromPlatform: json['joinedFromPlatform'] as String?,
      lastSyncAt: json['lastSyncAt'] == null
          ? null
          : DateTime.parse(json['lastSyncAt'] as String),
      lastTrustedActivityAt: json['lastTrustedActivityAt'] == null
          ? (json['lastSyncAt'] == null
              ? DateTime.parse(json['lastSeenAt'] as String)
              : DateTime.parse(json['lastSyncAt'] as String))
          : DateTime.parse(json['lastTrustedActivityAt'] as String),
    );
  }
}

class _DeviceGraphSummaryCard extends StatelessWidget {
  const _DeviceGraphSummaryCard({
    required this.devices,
    required this.currentDeviceId,
  });

  final List<_TrustedDevice> devices;
  final String? currentDeviceId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trustedCount = devices
        .where((device) => device.trustState == _DeviceTrustState.trusted)
        .length;
    final staleCount = devices
        .where((device) => device.trustState == _DeviceTrustState.stale)
        .length;
    final revokedCount = devices
        .where((device) => device.trustState == _DeviceTrustState.revoked)
        .length;
    final mostRecentTrustedActivity = devices
        .where((device) => device.trustState != _DeviceTrustState.revoked)
        .map((device) => device.lastTrustedActivityAt)
        .fold<DateTime?>(null, (latest, candidate) {
      if (latest == null || candidate.isAfter(latest)) {
        return candidate;
      }
      return latest;
    });
    final preferredDevice = devices.cast<_TrustedDevice?>().firstWhere(
          (device) => device?.trustState == _DeviceTrustState.preferred,
          orElse: () => null,
        );
    final currentDevice = devices.cast<_TrustedDevice?>().firstWhere(
          (device) => device?.id == currentDeviceId,
          orElse: () => null,
        );

    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeilSectionLabel(l10n.settingsGraphSummary),
          const SizedBox(height: VeilSpace.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(label: l10n.settingsGraphTrustedCount(trustedCount), tone: VeilBannerTone.info),
              VeilStatusPill(
                label: l10n.settingsGraphStaleCount(staleCount),
                tone:
                    staleCount > 0 ? VeilBannerTone.warn : VeilBannerTone.good,
              ),
              VeilStatusPill(
                label: l10n.settingsGraphRevokedCount(revokedCount),
                tone: revokedCount > 0
                    ? VeilBannerTone.warn
                    : VeilBannerTone.info,
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          if (mostRecentTrustedActivity != null)
            Text(
              l10n.settingsGraphRecentActivity(_utcDay(l10n.localeName, mostRecentTrustedActivity)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.veilPalette.textSubtle,
                  ),
            ),
          if (mostRecentTrustedActivity != null)
            const SizedBox(height: VeilSpace.sm),
          if (preferredDevice != null &&
              preferredDevice.id != currentDevice?.id)
            VeilInlineBanner(
              title: l10n.settingsGraphPreferredDiffersTitle,
              message: l10n.settingsGraphPreferredDiffersBody(
                preferredDevice.deviceName,
                currentDevice?.deviceName ?? l10n.settingsDeviceStateCurrent,
              ),
              tone: VeilBannerTone.info,
            ),
          if (staleCount > 0) ...[
            if (preferredDevice != null &&
                preferredDevice.id != currentDevice?.id)
              const SizedBox(height: VeilSpace.sm),
            VeilInlineBanner(
              title: l10n.settingsGraphStaleTitle,
              message: l10n.settingsGraphStaleBody,
              tone: VeilBannerTone.warn,
            ),
          ],
        ],
      ),
    );
  }
}

enum _DeviceTrustState { current, preferred, trusted, stale, revoked }

_DeviceTrustState _parseTrustState(String? raw) {
  switch (raw) {
    case 'current':
      return _DeviceTrustState.current;
    case 'preferred':
      return _DeviceTrustState.preferred;
    case 'stale':
      return _DeviceTrustState.stale;
    case 'revoked':
      return _DeviceTrustState.revoked;
    case 'trusted':
    default:
      return _DeviceTrustState.trusted;
  }
}

class _DeviceGraphSnapshot {
  const _DeviceGraphSnapshot({
    required this.activeDeviceId,
    required this.devices,
  });

  const _DeviceGraphSnapshot.empty()
      : activeDeviceId = null,
        devices = const [];

  final String? activeDeviceId;
  final List<_TrustedDevice> devices;
}
