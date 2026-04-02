import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

enum _TransferMode { oldDevice, newDevice }

class DeviceTransferScreen extends ConsumerStatefulWidget {
  const DeviceTransferScreen({super.key});

  @override
  ConsumerState<DeviceTransferScreen> createState() => _DeviceTransferScreenState();
}

class _DeviceTransferScreenState extends ConsumerState<DeviceTransferScreen> {
  final _payloadController = TextEditingController();
  final _sessionIdController = TextEditingController();
  final _tokenController = TextEditingController();
  final _deviceNameController = TextEditingController(text: 'VEIL New Device');
  final _claimIdController = TextEditingController();

  bool _isClaiming = false;
  bool _isCompleting = false;
  String? _claimId;
  String? _claimFingerprint;
  DateTime? _claimExpiresAt;
  String? _completionMessage;
  String? _completionError;
  late _TransferMode _mode;
  late Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    final session = ref.read(appSessionProvider);
    _mode = session.isAuthenticated ? _TransferMode.oldDevice : _TransferMode.newDevice;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    _payloadController.dispose();
    _sessionIdController.dispose();
    _tokenController.dispose();
    _deviceNameController.dispose();
    _claimIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final controller = ref.watch(messengerControllerProvider);
    final transferPayload = controller.transferPayload;
    final transferExpired = _isExpired(controller.transferExpiresAt);
    final claimExpired = _isExpired(_claimExpiresAt);

    if (_payloadController.text.isEmpty && transferPayload != null) {
      _payloadController.text = transferPayload;
    }

    return VeilShell(
      title: 'Device Transfer',
      child: ListView(
        children: [
          const VeilHeroPanel(
            eyebrow: 'TRANSFER',
            title: 'Old device required.',
            body:
                'Transfer is a live handoff. The old device issues the session, approves the exact new-device claim, and is revoked when the new device becomes active.',
          ),
          const SizedBox(height: VeilSpace.md),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: const Text('Old device'),
                selected: _mode == _TransferMode.oldDevice,
                onSelected: (_) => setState(() => _mode = _TransferMode.oldDevice),
              ),
              ChoiceChip(
                label: const Text('New device'),
                selected: _mode == _TransferMode.newDevice,
                onSelected: (_) => setState(() => _mode = _TransferMode.newDevice),
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilInlineBanner(
            title: 'No fallback path',
            message:
                'If the old device is gone, transfer fails. VEIL does not offer recovery, reset, export, or admin restore.',
            tone: VeilBannerTone.warn,
          ),
          if (transferExpired || claimExpired) ...[
            const SizedBox(height: VeilSpace.sm),
            VeilInlineBanner(
              title: 'Transfer window expired',
              message: transferExpired
                  ? 'The old-device transfer session expired. Issue a fresh session from the old device.'
                  : 'This new-device claim expired. Register a fresh claim and request approval again.',
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.md),
          if (_mode == _TransferMode.oldDevice)
            _OldDevicePanel(
              isAuthenticated: session.isAuthenticated,
              isBusy: controller.isBusy,
              transferSessionId: controller.transferSessionId,
              transferToken: controller.transferToken,
              transferPayload: transferPayload,
              transferStatus: controller.transferStatus,
              transferExpiresAt: controller.transferExpiresAt,
              transferExpired: transferExpired,
              errorMessage: controller.errorMessage,
              claimIdController: _claimIdController,
              onInit: () => ref.read(messengerControllerProvider).initTransfer(),
              onApprove: () => ref.read(messengerControllerProvider).approveTransfer(
                    _claimIdController.text.trim(),
                  ),
              onCopyPayload: transferPayload == null || transferExpired
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: transferPayload));
                      if (!mounted) {
                        return;
                      }
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Transfer payload copied.')),
                      );
                    },
              onClear: () => ref.read(messengerControllerProvider).clearTransferState(),
              now: _now,
            )
          else
            _NewDevicePanel(
              payloadController: _payloadController,
              sessionIdController: _sessionIdController,
              tokenController: _tokenController,
              deviceNameController: _deviceNameController,
              isClaiming: _isClaiming,
              isCompleting: _isCompleting,
              claimId: _claimId,
              claimFingerprint: _claimFingerprint,
              claimExpiresAt: _claimExpiresAt,
              claimExpired: claimExpired,
              completionMessage: _completionMessage,
              completionError: _completionError ?? session.errorMessage,
              onImportPayload: _importPayload,
              onClaim: _claimTransfer,
              onComplete: _completeTransfer,
              now: _now,
            ),
          if (_mode == _TransferMode.newDevice && session.isAuthenticated) ...[
            const SizedBox(height: VeilSpace.md),
            OutlinedButton(
              onPressed: () => context.go('/conversations'),
              child: const Text('Return to conversations'),
            ),
          ],
        ],
      ),
    );
  }

  bool _isExpired(DateTime? expiresAt) {
    if (expiresAt == null) {
      return false;
    }
    return !expiresAt.isAfter(_now);
  }

  void _importPayload() {
    final payload = _payloadController.text.trim();
    final parsed = _parseTransferPayload(payload);
    if (parsed == null) {
      setState(() {
        _completionError = 'Transfer payload format is invalid.';
        _completionMessage = null;
      });
      return;
    }

    setState(() {
      _sessionIdController.text = parsed.sessionId;
      _tokenController.text = parsed.transferToken;
      _claimId = null;
      _claimFingerprint = null;
      _claimExpiresAt = null;
      _completionError = null;
      _completionMessage =
          'Transfer payload imported. Register this new device before the transfer window closes.';
    });
  }

  Future<void> _claimTransfer() async {
    final sessionId = _sessionIdController.text.trim();
    final transferToken = _tokenController.text.trim();
    if (sessionId.isEmpty || transferToken.isEmpty) {
      setState(() {
        _completionError = 'Import a valid transfer payload first.';
        _completionMessage = null;
      });
      return;
    }

    setState(() {
      _isClaiming = true;
      _completionError = null;
      _completionMessage = null;
    });

    try {
      final result = await ref.read(appSessionProvider.notifier).claimTransfer(
            sessionId: sessionId,
            transferToken: transferToken,
            deviceName: _deviceNameController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _claimId = result.claimId;
        _claimFingerprint = result.claimantFingerprint;
        _claimExpiresAt = result.expiresAt;
        _completionMessage =
            'Claim registered. Give this claim code to the old device and request approval before it expires.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _completionError = ref.read(appSessionProvider).errorMessage ?? 'Claim failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isClaiming = false;
        });
      }
    }
  }

  Future<void> _completeTransfer() async {
    final sessionId = _sessionIdController.text.trim();
    final transferToken = _tokenController.text.trim();
    if (sessionId.isEmpty || transferToken.isEmpty || _claimId == null) {
      setState(() {
        _completionError = 'Register this new-device claim before completion.';
        _completionMessage = null;
      });
      return;
    }
    if (_isExpired(_claimExpiresAt)) {
      setState(() {
        _completionError = 'This new-device claim has expired. Register a fresh claim first.';
        _completionMessage = null;
      });
      return;
    }

    setState(() {
      _isCompleting = true;
      _completionError = null;
      _completionMessage = null;
    });

    try {
      await ref.read(appSessionProvider.notifier).completeTransferAndAuthenticate(
            sessionId: sessionId,
            transferToken: transferToken,
            claimId: _claimId!,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _completionMessage = 'Transfer complete. This device is now active.';
      });
      context.go('/conversations');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _completionError =
            ref.read(appSessionProvider).errorMessage ?? 'Transfer failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCompleting = false;
        });
      }
    }
  }

  _ParsedTransferPayload? _parseTransferPayload(String raw) {
    if (raw.isEmpty) {
      return null;
    }

    if (raw.startsWith('VEIL_TRANSFER::')) {
      final parts = raw.split('::');
      if (parts.length == 3) {
        return _ParsedTransferPayload(sessionId: parts[1], transferToken: parts[2]);
      }
    }

    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length >= 2) {
      final sessionLine = lines.firstWhere(
        (line) => line.toLowerCase().startsWith('session '),
        orElse: () => '',
      );
      final tokenLine = lines.firstWhere(
        (line) => line.toLowerCase().startsWith('token '),
        orElse: () => '',
      );
      if (sessionLine.isNotEmpty && tokenLine.isNotEmpty) {
        return _ParsedTransferPayload(
          sessionId: sessionLine.substring('session '.length).trim(),
          transferToken: tokenLine.substring('token '.length).trim(),
        );
      }
    }

    return null;
  }
}

class _OldDevicePanel extends StatelessWidget {
  const _OldDevicePanel({
    required this.isAuthenticated,
    required this.isBusy,
    required this.transferSessionId,
    required this.transferToken,
    required this.transferPayload,
    required this.transferStatus,
    required this.transferExpiresAt,
    required this.transferExpired,
    required this.errorMessage,
    required this.onInit,
    required this.claimIdController,
    required this.onApprove,
    required this.onCopyPayload,
    required this.onClear,
    required this.now,
  });

  final bool isAuthenticated;
  final bool isBusy;
  final String? transferSessionId;
  final String? transferToken;
  final String? transferPayload;
  final String? transferStatus;
  final DateTime? transferExpiresAt;
  final bool transferExpired;
  final String? errorMessage;
  final VoidCallback onInit;
  final TextEditingController claimIdController;
  final VoidCallback onApprove;
  final VoidCallback? onCopyPayload;
  final VoidCallback onClear;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (!isAuthenticated) {
      return const VeilEmptyState(
        title: 'Old device session required',
        body: 'Sign in on the currently active device to issue and approve a transfer.',
        icon: Icons.phonelink_lock_outlined,
      );
    }

    return Column(
      children: [
        _TransferCard(
          title: '1. Initiate on old device',
          body: transferExpiresAt == null
              ? 'Generate a short-lived session and token for the next device.'
              : 'This transfer session expires ${_formatExpiry(transferExpiresAt!, now)}.',
          status: transferSessionId == null
              ? 'Ready'
              : transferExpired
                  ? 'Expired'
                  : 'Issued',
          tone: transferSessionId == null
              ? VeilBannerTone.info
              : transferExpired
                  ? VeilBannerTone.danger
                  : VeilBannerTone.good,
        ),
        const SizedBox(height: VeilSpace.sm),
        FilledButton.tonal(
          onPressed: isBusy ? null : onInit,
          child: Text(isBusy && transferSessionId == null ? 'Issuing token' : 'Issue transfer token'),
        ),
        const SizedBox(height: VeilSpace.sm),
        _TransferCard(
          title: '2. Approve on old device',
          body: transferToken == null
              ? 'No transfer session exists yet.'
              : transferExpired
                  ? 'This transfer session expired. Clear it and issue a fresh one.'
                  : 'Wait for the new device to register its claim, then approve that specific claim code here.',
          status: transferToken == null
              ? 'Waiting'
              : transferExpired
                  ? 'Expired'
                  : 'Awaiting claim',
          tone: transferToken == null
              ? VeilBannerTone.warn
              : transferExpired
                  ? VeilBannerTone.danger
                  : VeilBannerTone.info,
        ),
        const SizedBox(height: VeilSpace.sm),
        TextField(
          controller: claimIdController,
          decoration: const InputDecoration(
            labelText: 'New-device claim code',
            hintText: 'Paste the claim code shown on the new device',
          ),
        ),
        const SizedBox(height: VeilSpace.sm),
        FilledButton.tonal(
          onPressed: isBusy || transferSessionId == null || transferExpired ? null : onApprove,
          child: const Text('Approve this claim'),
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilSurfaceCard(
          padding: const EdgeInsets.all(VeilSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '3. Hand payload to new device',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (transferPayload != null && !transferExpired)
                    const VeilStatusPill(
                      label: 'Ready to copy',
                      tone: VeilBannerTone.good,
                    ),
                ],
              ),
              const SizedBox(height: VeilSpace.sm),
              SelectableText(
                transferPayload ?? 'Issue a transfer token first.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: VeilSpace.sm),
              Text(
                transferExpired
                    ? 'This payload is no longer valid. Clear it and issue a fresh transfer session.'
                    : 'Complete on the new device. Do not complete on the old one.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilActionRow(
                children: [
                  OutlinedButton(
                    onPressed: onCopyPayload,
                    child: const Text('Copy payload'),
                  ),
                  OutlinedButton(
                    onPressed: isBusy ? null : onClear,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (transferStatus != null) ...[
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            title: 'Transfer status',
            message: transferStatus!,
            tone: transferExpired ? VeilBannerTone.warn : VeilBannerTone.info,
          ),
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: 'Transfer failed',
            message: errorMessage!,
            tone: VeilBannerTone.danger,
          ),
        ],
      ],
    );
  }
}

class _NewDevicePanel extends StatelessWidget {
  const _NewDevicePanel({
    required this.payloadController,
    required this.sessionIdController,
    required this.tokenController,
    required this.deviceNameController,
    required this.isClaiming,
    required this.isCompleting,
    required this.claimId,
    required this.claimFingerprint,
    required this.claimExpiresAt,
    required this.claimExpired,
    required this.completionMessage,
    required this.completionError,
    required this.onImportPayload,
    required this.onClaim,
    required this.onComplete,
    required this.now,
  });

  final TextEditingController payloadController;
  final TextEditingController sessionIdController;
  final TextEditingController tokenController;
  final TextEditingController deviceNameController;
  final bool isClaiming;
  final bool isCompleting;
  final String? claimId;
  final String? claimFingerprint;
  final DateTime? claimExpiresAt;
  final bool claimExpired;
  final String? completionMessage;
  final String? completionError;
  final VoidCallback onImportPayload;
  final Future<void> Function() onClaim;
  final Future<void> Function() onComplete;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        VeilSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VeilSectionLabel('TRANSFER PAYLOAD'),
              const SizedBox(height: VeilSpace.sm),
              TextField(
                controller: payloadController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Paste transfer payload',
                  hintText: 'VEIL_TRANSFER::<sessionId>::<token>',
                ),
              ),
              const SizedBox(height: VeilSpace.sm),
              OutlinedButton(
                onPressed: onImportPayload,
                child: const Text('Import payload'),
              ),
            ],
          ),
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VeilSectionLabel('NEW DEVICE'),
              const SizedBox(height: VeilSpace.sm),
              TextField(
                controller: deviceNameController,
                decoration: const InputDecoration(labelText: 'Device name'),
              ),
              const SizedBox(height: VeilSpace.sm),
              TextField(
                controller: sessionIdController,
                decoration: const InputDecoration(labelText: 'Session id'),
              ),
              const SizedBox(height: VeilSpace.sm),
              TextField(
                controller: tokenController,
                decoration: const InputDecoration(labelText: 'Transfer token'),
              ),
              const SizedBox(height: VeilSpace.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  VeilStatusPill(
                    label: claimId == null
                        ? 'Claim not registered'
                        : claimExpired
                            ? 'Claim expired'
                            : 'Claim registered',
                    tone: claimId == null
                        ? VeilBannerTone.warn
                        : claimExpired
                            ? VeilBannerTone.danger
                            : VeilBannerTone.good,
                  ),
                  const VeilStatusPill(label: 'Old device must approve exact claim'),
                ],
              ),
              if (claimId != null) ...[
                const SizedBox(height: VeilSpace.sm),
                SelectableText('Claim code $claimId'),
                const SizedBox(height: VeilSpace.xs),
                Text('Claim fingerprint ${claimFingerprint ?? 'Unavailable'}'),
                if (claimExpiresAt != null) ...[
                  const SizedBox(height: VeilSpace.xs),
                  Text('Expires ${_formatExpiry(claimExpiresAt!, now)}'),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: VeilSpace.md),
        OutlinedButton(
          onPressed: isClaiming ? null : onClaim,
          child: Text(isClaiming ? 'Registering claim' : 'Register this new device'),
        ),
        if (completionMessage != null) ...[
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            title: 'Transfer status',
            message: completionMessage!,
            tone: VeilBannerTone.good,
          ),
        ],
        if (completionError != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: 'Transfer failed',
            message: completionError!,
            tone: VeilBannerTone.danger,
          ),
        ],
        const SizedBox(height: VeilSpace.md),
        FilledButton(
          onPressed: isCompleting || claimId == null || claimExpired ? null : onComplete,
          child: Text(isCompleting ? 'Completing transfer' : 'Complete on this device'),
        ),
      ],
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.title,
    required this.body,
    required this.status,
    required this.tone,
  });

  final String title;
  final String body;
  final String status;
  final VeilBannerTone tone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(VeilSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                VeilStatusPill(label: status, tone: tone),
              ],
            ),
            const SizedBox(height: VeilSpace.sm),
            SelectableText(body, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

String _formatExpiry(DateTime expiresAt, DateTime now) {
  if (!expiresAt.isAfter(now)) {
    return 'now';
  }

  final remaining = expiresAt.difference(now);
  if (remaining.inMinutes < 1) {
    return 'in ${remaining.inSeconds}s';
  }
  if (remaining.inHours < 1) {
    return 'in ${remaining.inMinutes}m';
  }

  return 'at ${DateFormat('MMM d, HH:mm').format(expiresAt.toLocal())}';
}

class _ParsedTransferPayload {
  const _ParsedTransferPayload({
    required this.sessionId,
    required this.transferToken,
  });

  final String sessionId;
  final String transferToken;
}
