import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(appSessionProvider);
    final controller = ref.watch(messengerControllerProvider);
    final transferPayload = controller.transferPayload;
    final transferExpired = _isExpired(controller.transferExpiresAt);
    final claimExpired = _isExpired(_claimExpiresAt);

    if (_payloadController.text.isEmpty && transferPayload != null) {
      _payloadController.text = transferPayload;
    }

    return VeilShell(
      title: l10n.deviceTransferTitle,
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.deviceTransferHeroEyebrow,
            title: l10n.deviceTransferHeroTitle,
            body: l10n.deviceTransferHeroBody,
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.deviceTransferPillTrustedJoin),
                VeilStatusPill(label: l10n.deviceTransferPillNoFallback),
                VeilStatusPill(label: l10n.deviceTransferPillNoCloud),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: Text(l10n.deviceTransferChipOldDevice),
                selected: _mode == _TransferMode.oldDevice,
                onSelected: (_) => setState(() => _mode = _TransferMode.oldDevice),
              ),
              ChoiceChip(
                label: Text(l10n.deviceTransferChipNewDevice),
                selected: _mode == _TransferMode.newDevice,
                onSelected: (_) => setState(() => _mode = _TransferMode.newDevice),
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          VeilDestructiveNotice(
            title: l10n.deviceTransferNoFallbackTitle,
            body: l10n.deviceTransferNoFallbackBody,
          ),
          if (transferExpired || claimExpired) ...[
            const SizedBox(height: VeilSpace.sm),
            VeilInlineBanner(
              title: l10n.deviceTransferWindowExpiredTitle,
              message: transferExpired
                  ? l10n.deviceTransferSessionExpiredMessage
                  : l10n.deviceTransferClaimExpiredMessage,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.md),
          VeilMetricStrip(
            items: [
              VeilMetricItem(
                label: l10n.deviceTransferMetricMode,
                value: _mode == _TransferMode.oldDevice
                    ? l10n.deviceTransferMetricModeOld
                    : l10n.deviceTransferMetricModeNew,
              ),
              VeilMetricItem(
                label: l10n.deviceTransferMetricSession,
                value: transferExpired
                    ? l10n.deviceTransferSessionExpired
                    : controller.transferSessionId == null
                        ? l10n.deviceTransferSessionIdle
                        : l10n.deviceTransferSessionLive,
              ),
              VeilMetricItem(
                label: l10n.deviceTransferMetricClaim,
                value: _claimId == null
                    ? l10n.deviceTransferClaimMissing
                    : claimExpired
                        ? l10n.deviceTransferClaimExpired
                        : l10n.deviceTransferClaimIssued,
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          if (_mode == _TransferMode.oldDevice)
            _OldDevicePanel(
              l10n: l10n,
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
                        SnackBar(
                          content: Text(l10n.deviceTransferPayloadCopied),
                        ),
                      );
                    },
              onClear: () => ref.read(messengerControllerProvider).clearTransferState(),
              now: _now,
            )
          else
            _NewDevicePanel(
              l10n: l10n,
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
            VeilButton(
              onPressed: () => context.go('/conversations'),
              tone: VeilButtonTone.secondary,
              label: l10n.deviceTransferReturnToConversations,
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
    final l10n = AppLocalizations.of(context);
    final payload = _payloadController.text.trim();
    final parsed = _parseTransferPayload(payload);
    if (parsed == null) {
      setState(() {
        _completionError = l10n.deviceTransferPayloadInvalid;
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
      _completionMessage = l10n.deviceTransferPayloadImported;
    });
  }

  Future<void> _claimTransfer() async {
    final l10n = AppLocalizations.of(context);
    final sessionId = _sessionIdController.text.trim();
    final transferToken = _tokenController.text.trim();
    if (sessionId.isEmpty || transferToken.isEmpty) {
      setState(() {
        _completionError = l10n.deviceTransferImportFirst;
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
        _completionMessage = l10n.deviceTransferClaimRegistered;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _completionError = ref.read(appSessionProvider).errorMessage ??
            l10n.deviceTransferClaimFailed;
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
    final l10n = AppLocalizations.of(context);
    final sessionId = _sessionIdController.text.trim();
    final transferToken = _tokenController.text.trim();
    if (sessionId.isEmpty || transferToken.isEmpty || _claimId == null) {
      setState(() {
        _completionError = l10n.deviceTransferRegisterBeforeComplete;
        _completionMessage = null;
      });
      return;
    }
    if (_isExpired(_claimExpiresAt)) {
      setState(() {
        _completionError = l10n.deviceTransferClaimExpiredRegisterFresh;
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
        _completionMessage = l10n.deviceTransferComplete;
      });
      context.go('/conversations');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _completionError = ref.read(appSessionProvider).errorMessage ??
            l10n.deviceTransferFailed;
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
    required this.l10n,
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

  final AppLocalizations l10n;
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
      return VeilEmptyState(
        title: l10n.deviceTransferOldRequiredTitle,
        body: l10n.deviceTransferOldRequiredBody,
        icon: Icons.phonelink_lock_outlined,
      );
    }

    return Column(
      children: [
        _TransferCard(
          title: l10n.deviceTransferStep1Title,
          body: transferExpiresAt == null
              ? l10n.deviceTransferStep1BodyReady
              : l10n.deviceTransferStep1BodyExpires(
                  _formatExpiry(transferExpiresAt!, now, l10n),
                ),
          status: transferSessionId == null
              ? l10n.deviceTransferStatusReady
              : transferExpired
                  ? l10n.deviceTransferStatusExpired
                  : l10n.deviceTransferStatusIssued,
          tone: transferSessionId == null
              ? VeilBannerTone.info
              : transferExpired
                  ? VeilBannerTone.danger
                  : VeilBannerTone.good,
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilButton(
          onPressed: isBusy ? null : onInit,
          tone: VeilButtonTone.secondary,
          label: isBusy && transferSessionId == null
              ? l10n.deviceTransferIssuingToken
              : l10n.deviceTransferIssueToken,
        ),
        const SizedBox(height: VeilSpace.sm),
        _TransferCard(
          title: l10n.deviceTransferStep2Title,
          body: transferToken == null
              ? l10n.deviceTransferStep2BodyWaiting
              : transferExpired
                  ? l10n.deviceTransferStep2BodyExpired
                  : l10n.deviceTransferStep2BodyAwaiting,
          status: transferToken == null
              ? l10n.deviceTransferStatusWaiting
              : transferExpired
                  ? l10n.deviceTransferStatusExpired
                  : l10n.deviceTransferStatusAwaitingClaim,
          tone: transferToken == null
              ? VeilBannerTone.warn
              : transferExpired
                  ? VeilBannerTone.danger
                  : VeilBannerTone.info,
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilFieldBlock(
          label: l10n.deviceTransferClaimFieldLabel,
          caption: l10n.deviceTransferClaimFieldCaption,
          child: TextField(
            controller: claimIdController,
            decoration: InputDecoration(
              labelText: l10n.deviceTransferClaimInputLabel,
              hintText: l10n.deviceTransferClaimInputHint,
            ),
          ),
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilButton(
          onPressed: isBusy || transferSessionId == null || transferExpired ? null : onApprove,
          tone: VeilButtonTone.secondary,
          label: l10n.deviceTransferApproveClaim,
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilSurfaceCard(
          toned: true,
          padding: const EdgeInsets.all(VeilSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.deviceTransferStep3Title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (transferPayload != null && !transferExpired)
                    VeilStatusPill(
                      label: l10n.deviceTransferReadyToCopy,
                      tone: VeilBannerTone.good,
                    ),
                ],
              ),
              const SizedBox(height: VeilSpace.sm),
              SelectableText(
                transferPayload ?? l10n.deviceTransferIssueTokenFirst,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: VeilSpace.sm),
              Text(
                transferExpired
                    ? l10n.deviceTransferPayloadExpiredNote
                    : l10n.deviceTransferCompleteOnNewNote,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilActionRow(
                children: [
                  VeilButton(
                    onPressed: onCopyPayload,
                    tone: VeilButtonTone.secondary,
                    label: l10n.deviceTransferCopyPayload,
                  ),
                  VeilButton(
                    onPressed: isBusy ? null : onClear,
                    tone: VeilButtonTone.secondary,
                    label: l10n.deviceTransferClear,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (transferStatus != null) ...[
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            title: l10n.deviceTransferStatusTitle,
            message: transferStatus!,
            tone: transferExpired ? VeilBannerTone.warn : VeilBannerTone.info,
          ),
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: l10n.deviceTransferFailedTitle,
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
    required this.l10n,
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

  final AppLocalizations l10n;
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
        VeilFieldBlock(
          label: l10n.deviceTransferPayloadFieldLabel,
          caption: l10n.deviceTransferPayloadFieldCaption,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: payloadController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: l10n.deviceTransferPayloadInputLabel,
                  hintText: 'VEIL_TRANSFER::<sessionId>::<token>',
                ),
              ),
              const SizedBox(height: VeilSpace.sm),
              VeilButton(
                expanded: false,
                tone: VeilButtonTone.secondary,
                onPressed: onImportPayload,
                label: l10n.deviceTransferImportPayload,
              ),
            ],
          ),
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilFieldBlock(
          label: l10n.deviceTransferNewDeviceLabel,
          caption: l10n.deviceTransferNewDeviceCaption,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: deviceNameController,
                decoration: InputDecoration(
                  labelText: l10n.deviceTransferDeviceNameLabel,
                ),
              ),
              const SizedBox(height: VeilSpace.sm),
              TextField(
                controller: sessionIdController,
                decoration: InputDecoration(
                  labelText: l10n.deviceTransferSessionIdLabel,
                ),
              ),
              const SizedBox(height: VeilSpace.sm),
              TextField(
                controller: tokenController,
                decoration: InputDecoration(
                  labelText: l10n.deviceTransferTokenLabel,
                ),
              ),
              const SizedBox(height: VeilSpace.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  VeilStatusPill(
                    label: claimId == null
                        ? l10n.deviceTransferClaimNotRegistered
                        : claimExpired
                            ? l10n.deviceTransferClaimExpiredPill
                            : l10n.deviceTransferClaimRegisteredPill,
                    tone: claimId == null
                        ? VeilBannerTone.warn
                        : claimExpired
                            ? VeilBannerTone.danger
                            : VeilBannerTone.good,
                  ),
                  VeilStatusPill(label: l10n.deviceTransferOldApprovesExact),
                ],
              ),
              if (claimId != null) ...[
                const SizedBox(height: VeilSpace.sm),
                SelectableText(l10n.deviceTransferClaimCode(claimId!)),
                const SizedBox(height: VeilSpace.xs),
                Text(
                  l10n.deviceTransferClaimFingerprint(
                    claimFingerprint ?? l10n.deviceTransferFingerprintUnavailable,
                  ),
                ),
                if (claimExpiresAt != null) ...[
                  const SizedBox(height: VeilSpace.xs),
                  Text(
                    l10n.deviceTransferExpires(
                      _formatExpiry(claimExpiresAt!, now, l10n),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: VeilSpace.md),
        VeilButton(
          onPressed: isClaiming ? null : onClaim,
          tone: VeilButtonTone.secondary,
          label: isClaiming
              ? l10n.deviceTransferRegisteringClaim
              : l10n.deviceTransferRegisterNewDevice,
        ),
        if (completionMessage != null) ...[
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            title: l10n.deviceTransferStatusTitle,
            message: completionMessage!,
            tone: VeilBannerTone.good,
          ),
        ],
        if (completionError != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: l10n.deviceTransferFailedTitle,
            message: completionError!,
            tone: VeilBannerTone.danger,
          ),
        ],
        const SizedBox(height: VeilSpace.md),
        VeilButton(
          onPressed: isCompleting || claimId == null || claimExpired ? null : onComplete,
          label: isCompleting
              ? l10n.deviceTransferCompleting
              : l10n.deviceTransferCompleteOnDevice,
          icon: Icons.arrow_forward_rounded,
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
    return VeilSurfaceCard(
      toned: true,
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
    );
  }
}

String _formatExpiry(DateTime expiresAt, DateTime now, AppLocalizations l10n) {
  if (!expiresAt.isAfter(now)) {
    return l10n.deviceTransferExpiryNow;
  }

  final remaining = expiresAt.difference(now);
  if (remaining.inMinutes < 1) {
    return l10n.deviceTransferExpiryInSeconds(remaining.inSeconds);
  }
  if (remaining.inHours < 1) {
    return l10n.deviceTransferExpiryInMinutes(remaining.inMinutes);
  }

  return l10n.deviceTransferExpiryAt(
    DateFormat('MMM d, HH:mm').format(expiresAt.toLocal()),
  );
}

class _ParsedTransferPayload {
  const _ParsedTransferPayload({
    required this.sessionId,
    required this.transferToken,
  });

  final String sessionId;
  final String transferToken;
}
