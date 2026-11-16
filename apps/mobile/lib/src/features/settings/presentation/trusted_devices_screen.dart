import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/trusted_devices.dart';
import 'device_rows.dart';

/// The devices that hold this account, as Signal lists linked devices:
/// this one in a section of its own, then the others, a row each with one
/// grey line. A tap on another device asks to remove it. Removed devices
/// are not listed. The route `/trusted-devices`, opened from Settings.
class TrustedDevicesScreen extends ConsumerWidget {
  const TrustedDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final devices = ref.watch(trustedDevicesProvider);
    final list = devices.valueOrNull;

    // On open, and on a pull: no refresh button.
    Future<void> refresh() async {
      ref.invalidate(trustedDevicesProvider);
      // A failed reload shows on the screen itself.
      await ref.read(trustedDevicesProvider.future).then<void>((_) {}, onError: (_) {});
    }

    final listed = list?.devices.where((device) => device.trustState != DeviceTrustState.revoked).toList();
    final thisDevice = listed?.where((device) => device.trustState == DeviceTrustState.current).toList();
    final others = listed?.where((device) => device.trustState != DeviceTrustState.current).toList();

    final List<Widget> content;
    // A reload keeps the list on screen; only a failed one replaces it.
    if (devices.hasError && !devices.isLoading) {
      content = [
        VeilEmptyState(
          title: l10n.settingsDeviceGraphUnavailable,
          action: VeilButton(
            expanded: false,
            tone: VeilButtonTone.secondary,
            label: l10n.commonRetry,
            onPressed: refresh,
          ),
        ),
      ];
    } else if (listed == null) {
      content = [
        Padding(
          padding: const EdgeInsets.only(top: VeilSpace.xxl),
          child: Center(
            child: Semantics(
              label: l10n.settingsLoadingDeviceGraph,
              child: const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ),
      ];
    } else if (listed.isEmpty) {
      content = [_QuietLine(l10n.settingsNoTrustedDevices)];
    } else {
      content = [
        if (thisDevice!.isNotEmpty)
          VeilGroup(
            header: l10n.settingsDeviceStateCurrent,
            children: [
              for (final device in thisDevice) DeviceRow(key: ValueKey('device-${device.id}'), device: device),
            ],
          ),
        if (others!.isNotEmpty)
          VeilGroup(
            header: l10n.settingsDevicesOtherHeader,
            children: [
              for (final device in others)
                DeviceRow(
                  key: ValueKey('device-${device.id}'),
                  device: device,
                  onTap: () => _confirmAndRemove(context, ref, device, refresh),
                ),
            ],
          ),
      ];
    }

    return VeilShell(
      title: l10n.settingsDevicesTitle,
      grouped: true,
      maxWidth: 600,
      child: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: VeilSpace.md, bottom: VeilSpace.xxl),
          children: content,
        ),
      ),
    );
  }

  Future<void> _confirmAndRemove(
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
        content: Text(l10n.settingsRevokeListedBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsDeviceRevokeAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(appSessionProvider.notifier).revokeListedDevice(device.id);
      await refresh();
      if (!context.mounted) return;
      showVeilToast(context, l10n.settingsRevokeListedDone(device.deviceName));
    } catch (_) {
      if (!context.mounted) return;
      showVeilToast(context, l10n.settingsRevokeListedFailed, tone: VeilTone.warn);
    }
  }
}

/// One muted line at the top of the list area, as Signal's "No linked
/// devices".
class _QuietLine extends StatelessWidget {
  const _QuietLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.sm),
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.veilPalette.textMuted)),
    );
  }
}
