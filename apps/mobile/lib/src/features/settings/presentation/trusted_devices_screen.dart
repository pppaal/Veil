import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/trusted_devices.dart';
import 'device_rows.dart';

/// The devices that hold this account, as the server lists them: this one
/// first, then the others, each with what the server knows of it and,
/// where it still can be, the row that revokes it. The route
/// `/trusted-devices`, opened from a device row in Settings.
class TrustedDevicesScreen extends ConsumerWidget {
  const TrustedDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final devices = ref.watch(trustedDevicesProvider);
    final list = devices.valueOrNull;

    Future<void> refresh() async {
      ref.invalidate(trustedDevicesProvider);
      // A failed reload shows on the screen itself.
      await ref.read(trustedDevicesProvider.future).then<void>((_) {}, onError: (_) {});
    }

    final List<Widget> content;
    // A reload keeps the list on screen; only a failed one replaces it.
    if (devices.hasError && !devices.isLoading) {
      content = [
        VeilNotice(
          margin: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
          title: l10n.settingsDeviceGraphUnavailable,
          message: l10n.settingsDeviceGraphLoadFailedBody,
          tone: VeilTone.warn,
          actionLabel: l10n.commonRetry,
          onAction: refresh,
        ),
      ];
    } else if (list == null) {
      content = [
        Padding(
          padding: const EdgeInsets.only(top: VeilSpace.xxl),
          child: Column(
            children: [
              const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(height: VeilSpace.sm),
              Text(l10n.settingsLoadingDeviceGraph,
                  style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
            ],
          ),
        ),
      ];
    } else if (list.devices.isEmpty) {
      content = [
        VeilEmptyState(
          title: l10n.settingsNoTrustedDevices,
          body: l10n.settingsNoTrustedDevicesBody,
          icon: Icons.devices_outlined,
        ),
      ];
    } else {
      content = [
        for (final (index, device) in list.devices.indexed) ...[
          if (index > 0) const SizedBox(height: VeilSpace.lg),
          DeviceDetailsGroup(
            key: ValueKey('device-${device.id}'),
            device: device,
            onRevoke: device.canBeRevoked ? () => _confirmAndRevoke(context, ref, device, refresh) : null,
          ),
        ],
      ];
    }

    return VeilShell(
      title: l10n.settingsDevicesTitle,
      grouped: true,
      actions: [
        IconButton(
          tooltip: l10n.settingsRefreshDeviceGraph,
          onPressed: list == null && !devices.hasError ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.only(top: VeilSpace.md, bottom: VeilSpace.xxl),
          children: content,
        ),
      ),
    );
  }

  Future<void> _confirmAndRevoke(
    BuildContext context,
    WidgetRef ref,
    TrustedDevice device,
    Future<void> Function() refresh,
  ) async {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(l10n.settingsRevokeListedTitle(device.deviceName)),
        content: Text(l10n.settingsRevokeListedBody(device.deviceName)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsRevokeConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(appSessionProvider.notifier).revokeListedDevice(device.id);
      await refresh();
      if (!context.mounted) return;
      showVeilToast(context, l10n.settingsRevokeListedDone(device.deviceName), tone: VeilTone.good);
    } catch (_) {
      if (!context.mounted) return;
      showVeilToast(context, l10n.settingsRevokeListedFailed, tone: VeilTone.warn);
    }
  }
}
