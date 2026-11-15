import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/trusted_devices.dart';
import 'trusted_device_card.dart';

/// The devices that hold this account, as the relay lists them: this one
/// first, then the others, each with what its state means and, where it
/// still can be, the button that revokes it. Opened from the settings tab.
class TrustedDevicesScreen extends ConsumerWidget {
  const TrustedDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final devices = ref.watch(trustedDevicesProvider);
    final list = devices.valueOrNull;

    Future<void> refresh() async {
      ref.invalidate(trustedDevicesProvider);
      // A failed reload shows on the screen itself.
      await ref.read(trustedDevicesProvider.future).then<void>((_) {}, onError: (_) {});
    }

    return VeilShell(
      title: l10n.settingsDevicesTitle,
      padding: EdgeInsets.zero,
      child: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.md, VeilSpace.lg, VeilSpace.xl),
          children: [
            // A reload keeps the list on screen; only a failed one replaces it.
            if (devices.hasError && !devices.isLoading)
              VeilInlineBanner(
                title: l10n.settingsDeviceGraphUnavailable,
                message: l10n.settingsDeviceGraphLoadFailedBody,
                tone: VeilBannerTone.warn,
                actionLabel: l10n.commonRetry,
                onAction: refresh,
              )
            else if (list == null)
              VeilLoadingBlock(title: l10n.settingsLoadingDeviceGraph, body: l10n.settingsLoadingDeviceGraphBody)
            else if (list.devices.isEmpty)
              VeilEmptyState(
                title: l10n.settingsNoTrustedDevices,
                body: l10n.settingsNoTrustedDevicesBody,
                icon: Icons.devices_outlined,
              )
            else
              ..._loaded(context, ref, list, refresh),
          ],
        ),
      ),
    );
  }

  List<Widget> _loaded(BuildContext context, WidgetRef ref, TrustedDeviceList list, Future<void> Function() refresh) {
    final l10n = AppLocalizations.of(context);
    final current = list.byId(ref.watch(appSessionProvider.select((session) => session.deviceId)));
    final preferred = list.preferred;
    final recent = list.mostRecentTrustedActivity;

    return [
      _Summary(
        parts: [
          l10n.settingsDevicesTrustedCount(list.activeCount),
          if (list.staleCount > 0) l10n.settingsGraphStaleCount(list.staleCount),
          if (list.revokedCount > 0) l10n.settingsGraphRevokedCount(list.revokedCount),
        ],
        detail: recent == null ? null : l10n.settingsGraphRecentActivity(deviceUtcDay(l10n.localeName, recent)),
      ),
      if (list.staleCount > 0) ...[
        const SizedBox(height: VeilSpace.sm),
        VeilInlineBanner(
          title: l10n.settingsGraphStaleTitle,
          message: l10n.settingsGraphStaleBody,
          tone: VeilBannerTone.warn,
        ),
      ],
      if (preferred != null && preferred.id != current?.id) ...[
        const SizedBox(height: VeilSpace.sm),
        VeilInlineBanner(
          title: l10n.settingsGraphPreferredDiffersTitle,
          message: l10n.settingsGraphPreferredDiffersBody(
            preferred.deviceName,
            current?.deviceName ?? l10n.settingsDeviceStateCurrent,
          ),
        ),
      ],
      for (final device in list.devices) ...[
        const SizedBox(height: VeilSpace.sm),
        TrustedDeviceCard(
          device: device,
          onRevoke: device.canBeRevoked ? () => _confirmAndRevoke(context, ref, device, refresh) : null,
        ),
      ],
      const SizedBox(height: VeilSpace.xs),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: refresh,
          icon: const Icon(Icons.refresh_rounded, size: VeilIconSize.sm),
          label: Text(l10n.settingsRefreshDeviceGraph),
        ),
      ),
    ];
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
        title: VeilCopy(l10n.settingsRevokeListedTitle(device.deviceName)),
        content: VeilCopy(l10n.settingsRevokeListedBody(device.deviceName)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger, foregroundColor: palette.canvas),
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
      VeilToast.show(context, message: l10n.settingsRevokeListedDone(device.deviceName), tone: VeilBannerTone.good);
    } catch (_) {
      if (!context.mounted) return;
      VeilToast.show(context, message: l10n.settingsRevokeListedFailed, tone: VeilBannerTone.warn);
    }
  }
}

/// How many devices, in which state, on one line that wraps between its
/// parts, and when one of them was last active.
class _Summary extends StatelessWidget {
  const _Summary({required this.parts, this.detail});

  final List<String> parts;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Wrap(
              children: [
                for (final (index, part) in parts.indexed)
                  Text(index == parts.length - 1 ? part : '$part  ·  ', style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(detail!, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)),
          ],
        ],
      ),
    );
  }
}
