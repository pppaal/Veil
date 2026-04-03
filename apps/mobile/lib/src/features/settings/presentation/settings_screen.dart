import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<_DeviceGraphSnapshot>? _deviceGraphFuture;
  final _dateFormat = DateFormat('MMM d | HH:mm');
  final _wipeConfirmController = TextEditingController();
  final _revokeConfirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _deviceGraphFuture = _loadDeviceGraph();
  }

  @override
  void dispose() {
    _wipeConfirmController.dispose();
    _revokeConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);

    return VeilShell(
      title: 'Settings',
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: 'LOCAL DEVICE',
            title: session.displayName ?? '@${session.handle ?? 'unbound'}',
            body: session.deviceId == null
                ? 'No active device session is bound.'
                : 'Current device session: ${session.deviceId}',
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                VeilStatusPill(label: 'No recovery'),
                VeilStatusPill(label: 'Device-bound'),
                VeilStatusPill(label: 'Private by design'),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilSectionLabel('TRUSTED DEVICE GRAPH'),
          const SizedBox(height: VeilSpace.sm),
          FutureBuilder<_DeviceGraphSnapshot>(
            future: _deviceGraphFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const VeilLoadingBlock(
                  title: 'Loading device graph',
                  body: 'Reviewing the bound devices known to this account.',
                );
              }

              if (snapshot.hasError) {
                return VeilSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const VeilInlineBanner(
                        title: 'Device graph unavailable',
                        message:
                            'This device could not load the current trust graph. Local security controls remain available.',
                        tone: VeilBannerTone.warn,
                      ),
                      const SizedBox(height: VeilSpace.md),
                      OutlinedButton(
                        onPressed: _refreshDeviceGraph,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final snapshotValue =
                  snapshot.data ?? const _DeviceGraphSnapshot.empty();
              if (snapshotValue.devices.isEmpty) {
                return const VeilEmptyState(
                  title: 'No trusted devices visible',
                  body:
                      'This account has no readable device graph yet. Bound-device controls still remain local and unrecoverable.',
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
                      dateFormat: _dateFormat,
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
                      child: const Text('Refresh device graph'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilSectionLabel('SECURITY'),
          const SizedBox(height: VeilSpace.sm),
          VeilActionCluster(
            children: [
              VeilListTileCard(
                title: 'App lock',
                subtitle: 'Biometric and PIN barrier on this device only',
                leading: const Icon(Icons.lock_outline),
                onTap: () => context.push('/lock'),
              ),
              VeilListTileCard(
                title: 'Device transfer',
                subtitle: 'Old device must initiate and approve',
                leading: const Icon(Icons.phonelink_lock_outlined),
                onTap: () => context.push('/device-transfer'),
              ),
              VeilListTileCard(
                title: 'Security status',
                subtitle: 'Review local guardrails and runtime state',
                leading: const Icon(Icons.verified_user_outlined),
                onTap: () => context.push('/security-status'),
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilSectionLabel('SESSION'),
          const SizedBox(height: VeilSpace.sm),
          const VeilInlineBanner(
            title: 'No recovery path',
            message:
                'Destructive device actions are permanent on this device. VEIL does not keep a backup or restore authority.',
            tone: VeilBannerTone.warn,
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilActionCluster(
            children: [
              VeilListTileCard(
                title: 'Lock now',
                subtitle:
                    'Hide the current session behind the local barrier immediately',
                leading: const Icon(Icons.visibility_off_outlined),
                onTap: () {
                  ref.read(appSessionProvider.notifier).lock();
                  context.go('/lock');
                },
              ),
              VeilListTileCard(
                title: 'Wipe local device state',
                subtitle:
                    'Deletes local session state, local secrets, encrypted cache, PIN, and onboarding state on this device only.',
                leading: Icon(
                  Icons.layers_clear_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                destructive: true,
                onTap: () async {
                  final confirmed = await _confirmDestructiveAction(
                    controller: _wipeConfirmController,
                    context: context,
                    title: 'Wipe this device locally?',
                    body:
                        'This erases local VEIL state on this device. It does not create a recovery path. If this is your only active device, access is gone.',
                    confirmVerb: 'Wipe local state',
                    expectedPhrase: 'WIPE',
                  );

                  if (confirmed != true) {
                    return;
                  }

                  await ref
                      .read(appSessionProvider.notifier)
                      .wipeLocalDeviceState();
                  if (context.mounted) {
                    context.go('/splash');
                  }
                },
              ),
              VeilListTileCard(
                title: 'Revoke this device',
                subtitle:
                    'Destroys this bound device session and wipes local state on this device. No recovery exists.',
                leading: Icon(
                  Icons.phonelink_erase_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                destructive: true,
                onTap: () async {
                  final confirmed = await _confirmDestructiveAction(
                    controller: _revokeConfirmController,
                    context: context,
                    title: 'Revoke this device?',
                    body:
                        'This removes the active device binding for this account on this device and wipes local state here. VEIL cannot restore it.',
                    confirmVerb: 'Revoke device',
                    expectedPhrase: 'REVOKE',
                  );

                  if (confirmed != true) {
                    return;
                  }

                  await ref
                      .read(appSessionProvider.notifier)
                      .revokeCurrentDevice();
                  if (context.mounted) {
                    context.go('/create-account');
                  }
                },
              ),
              VeilListTileCard(
                title: 'Log out',
                subtitle:
                    'Clears this local session while leaving the onboarding acknowledgment and local barrier intact.',
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
                Text('Type $expectedPhrase to continue.'),
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
                child: const Text('Cancel'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Revoke ${device.deviceName}?'),
        content: Text(
          'This removes ${device.deviceName} from the trusted device graph. VEIL will not create a recovery path for that device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revoke device'),
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
        SnackBar(
          content:
              Text('${device.deviceName} was removed from the trusted graph.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      VeilToast.show(
        context,
        message: 'The device could not be revoked. Try again.',
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

  return right.lastSeenAt.compareTo(left.lastSeenAt);
}

class _DeviceRowCard extends StatelessWidget {
  const _DeviceRowCard({
    required this.device,
    required this.dateFormat,
    this.onRevoke,
  });

  final _TrustedDevice device;
  final DateFormat dateFormat;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final statusTone = switch (device.trustState) {
      _DeviceTrustState.current => VeilBannerTone.good,
      _DeviceTrustState.preferred => VeilBannerTone.info,
      _DeviceTrustState.trusted => VeilBannerTone.info,
      _DeviceTrustState.stale => VeilBannerTone.warn,
      _DeviceTrustState.revoked => VeilBannerTone.danger,
    };
    final statusLabel = switch (device.trustState) {
      _DeviceTrustState.current => 'This device',
      _DeviceTrustState.preferred => 'Preferred',
      _DeviceTrustState.trusted => 'Trusted',
      _DeviceTrustState.stale => 'Stale',
      _DeviceTrustState.revoked => 'Revoked',
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
                  child: const Text('Revoke'),
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
                'Created ${dateFormat.format(device.createdAt.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Seen ${dateFormat.format(device.lastSeenAt.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (device.lastSyncAt != null)
                Text(
                  'Synced ${dateFormat.format(device.lastSyncAt!.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (device.trustedAt != null)
                Text(
                  'Trusted ${dateFormat.format(device.trustedAt!.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (device.joinedFromDeviceId != null)
                Text(
                  'Joined from ${device.joinedFromDeviceName ?? device.joinedFromDeviceId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (device.revokedAt != null)
                Text(
                  'Revoked ${dateFormat.format(device.revokedAt!.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: VeilSpace.sm),
          Text(
            switch (device.trustState) {
              _DeviceTrustState.current =>
                'This is the current trusted device. If every trusted device is lost, VEIL cannot restore access.',
              _DeviceTrustState.preferred =>
                'This trusted device is the current preferred routing device. It is not a cloud recovery anchor.',
              _DeviceTrustState.trusted =>
                'This device remains trusted and can continue syncing while another trusted device exists.',
              _DeviceTrustState.stale =>
                'This device is still trusted but has not synced recently. Revoke it if it should no longer retain access.',
              _DeviceTrustState.revoked =>
                'This device is no longer trusted and cannot resume the session.',
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
    final trustedCount = devices
        .where((device) => device.trustState == _DeviceTrustState.trusted)
        .length;
    final staleCount = devices
        .where((device) => device.trustState == _DeviceTrustState.stale)
        .length;
    final revokedCount = devices
        .where((device) => device.trustState == _DeviceTrustState.revoked)
        .length;
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
          const VeilSectionLabel('GRAPH SUMMARY'),
          const SizedBox(height: VeilSpace.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(
                  label: '$trustedCount trusted', tone: VeilBannerTone.info),
              VeilStatusPill(
                label: '$staleCount stale',
                tone:
                    staleCount > 0 ? VeilBannerTone.warn : VeilBannerTone.good,
              ),
              VeilStatusPill(
                label: '$revokedCount revoked',
                tone: revokedCount > 0
                    ? VeilBannerTone.warn
                    : VeilBannerTone.info,
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          if (preferredDevice != null &&
              preferredDevice.id != currentDevice?.id)
            VeilInlineBanner(
              title: 'Preferred device differs',
              message:
                  '${preferredDevice.deviceName} is currently preferred for routing and directory compatibility. ${currentDevice?.deviceName ?? 'This device'} remains trusted.',
              tone: VeilBannerTone.info,
            ),
          if (staleCount > 0) ...[
            if (preferredDevice != null &&
                preferredDevice.id != currentDevice?.id)
              const SizedBox(height: VeilSpace.sm),
            const VeilInlineBanner(
              title: 'Stale trusted devices present',
              message:
                  'Some trusted devices have not synced recently. Revoke them if they should no longer retain access.',
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
