import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/storage/secure_storage_service.dart' show PendingTransferRecord;
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/device_transfer_providers.dart';
import 'device_transfer_code.dart';
import 'device_transfer_new_device_panel.dart';
import 'device_transfer_old_device_panel.dart';

enum _TransferMode { oldDevice, newDevice }

/// Moving the account to another device. A signed-in device opens as the
/// old one, any other as the new one. Each side is three numbered steps
/// with the step in hand first on the screen; the notice that nothing
/// replaces a missing old device follows the steps. A session or a claim
/// that ran out is said in the first step of its side, which takes the new
/// code.
class DeviceTransferScreen extends ConsumerStatefulWidget {
  const DeviceTransferScreen({super.key});

  @override
  ConsumerState<DeviceTransferScreen> createState() => _DeviceTransferScreenState();
}

class _DeviceTransferScreenState extends ConsumerState<DeviceTransferScreen> {
  final _codeController = TextEditingController();
  final _deviceNameController = TextEditingController();
  final _claimIdController = TextEditingController();

  // The transfer code this device read: empty until one was.
  String _sessionId = '';
  String _transferToken = '';
  // The first step, reopened to paste another code.
  bool _editingCode = false;
  bool _deviceNameSeeded = false;
  bool _isClaiming = false;
  bool _isCompleting = false;
  String? _claimId;
  String? _claimFingerprint;
  DateTime? _claimExpiresAt;
  // The claim whose expired code was taken out of the field.
  String? _droppedCodeOfClaim;
  TransferNotice? _notice;
  late _TransferMode _mode;
  late Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    final session = ref.read(appSessionProvider);
    _mode = session.isAuthenticated ? _TransferMode.oldDevice : _TransferMode.newDevice;
    // A claim this device made before the app stopped is completed from
    // where it was, never claimed again: a second claim ends the session.
    final pending = ref.read(appSessionProvider.notifier).pendingTransfer;
    if (!session.isAuthenticated && pending != null) {
      _sessionId = pending.sessionId;
      _transferToken = pending.transferToken;
      _claimId = pending.claimId;
      _claimFingerprint = pending.claimantFingerprint;
      _claimExpiresAt = pending.expiresAt;
      _dropExpiredCode();
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
        _dropExpiredCode();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The name the relay lists this device under, offered in the user's
    // language; the field is theirs to change.
    if (!_deviceNameSeeded) {
      _deviceNameSeeded = true;
      _deviceNameController.text = AppLocalizations.of(context).authDefaultDeviceName;
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    _codeController.dispose();
    _deviceNameController.dispose();
    _claimIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(appSessionProvider);
    final controller = ref.watch(deviceTransferControllerProvider);
    final transferCode = controller.transferPayload;
    final transferExpired = _isExpired(controller.transferExpiresAt);
    // A claim the relay committed, or may have, has no window left to miss:
    // the old device may be revoked already, and only the completion on this
    // device remains, however long ago the claim was made. Which step is in
    // hand and whether the completion button is offered both follow
    // _claimExpired, so that completion stays reachable until the relay
    // itself ends it.
    final claimExpired = _claimExpired();
    final windowDecides = !(_heldClaim()?.mayBeCommitted ?? false);
    final oldDevice = _mode == _TransferMode.oldDevice;
    final sessionError = session.errorMessage;

    if (_codeController.text.isEmpty && transferCode != null) {
      _codeController.text = transferCode;
    }

    return VeilShell(
      title: l10n.deviceTransferTitle,
      child: ListView(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: Text(l10n.deviceTransferChipOldDevice),
                selected: oldDevice,
                onSelected: (_) => setState(() => _mode = _TransferMode.oldDevice),
              ),
              ChoiceChip(
                label: Text(l10n.deviceTransferChipNewDevice),
                selected: !oldDevice,
                onSelected: (_) => setState(() => _mode = _TransferMode.newDevice),
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.sm),
          if (oldDevice)
            TransferOldDevicePanel(
              isAuthenticated: session.isAuthenticated,
              isBusy: controller.isBusy,
              transferSessionId: controller.transferSessionId,
              transferCode: transferCode,
              status: controller.transferStatus,
              transferExpiresAt: controller.transferExpiresAt,
              transferExpired: transferExpired,
              errorMessage: controller.errorMessage,
              claimIdController: _claimIdController,
              onIssue: () => ref.read(deviceTransferControllerProvider).initTransfer(),
              onApprove: () => ref.read(deviceTransferControllerProvider).approveTransfer(
                    _claimIdController.text.trim(),
                  ),
              onCopyCode: transferCode == null || transferExpired ? null : () => _copyCode(transferCode),
              onClear: () => ref.read(deviceTransferControllerProvider).clearTransferState(),
              now: _now,
            )
          else
            TransferNewDevicePanel(
              codeController: _codeController,
              deviceNameController: _deviceNameController,
              hasCode: _sessionId.isNotEmpty && _transferToken.isNotEmpty,
              editingCode: _editingCode,
              isClaiming: _isClaiming,
              isCompleting: _isCompleting,
              claimId: _claimId,
              claimFingerprint: _claimFingerprint,
              claimExpiresAt: windowDecides ? _claimExpiresAt : null,
              claimExpired: claimExpired,
              // A failure of this screen's own step first, then one the
              // session reports (a login resumed at start), then good news.
              notice: (_notice?.isError ?? false) || sessionError == null
                  ? _notice
                  : TransferNotice(sessionError, isError: true),
              onUseCode: _useCode,
              onEditCode: () => setState(() => _editingCode = true),
              onKeepCode: () => setState(() {
                _editingCode = false;
                if (_notice?.step == 1) _notice = null;
              }),
              onClaim: _claimTransfer,
              onComplete: _completeTransfer,
              now: _now,
            ),
          if (!oldDevice && session.isAuthenticated) ...[
            const SizedBox(height: VeilSpace.md),
            VeilButton(
              onPressed: () => context.go('/conversations'),
              tone: VeilButtonTone.secondary,
              label: l10n.deviceTransferReturnToConversations,
            ),
          ],
          const SizedBox(height: VeilSpace.lg),
          VeilDestructiveNotice(
            title: l10n.deviceTransferNoFallbackTitle,
            body: l10n.deviceTransferNoFallbackBody,
          ),
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

  // The claim this device holds, when it is the one the screen shows.
  PendingTransferRecord? _heldClaim() {
    final pending = ref.read(appSessionProvider.notifier).pendingTransfer;
    return pending != null && _claimId != null && pending.claimId == _claimId ? pending : null;
  }

  // Whether the claim shown can no longer be completed. Once this device
  // sent /complete for it and missed the answer, only the relay can say: it
  // answers a committed transfer with its completion at any age, and ends an
  // uncommitted one with transfer_session_inactive
  // (PendingTransferRecord.expiredAt).
  bool _claimExpired() {
    final held = _heldClaim();
    return held != null ? held.expiredAt(_now) : _isExpired(_claimExpiresAt);
  }

  // The code a claim was made on is of no use once the claim ran out: the
  // field is emptied, once, for the new code.
  void _dropExpiredCode() {
    if (_claimId == null || _droppedCodeOfClaim == _claimId || !_claimExpired()) {
      return;
    }
    _droppedCodeOfClaim = _claimId;
    _codeController.clear();
  }

  Future<void> _copyCode(String transferCode) async {
    final copied = AppLocalizations.of(context).deviceTransferPayloadCopied;
    await Clipboard.setData(ClipboardData(text: transferCode));
    if (!mounted) {
      return;
    }
    VeilToast.show(context, message: copied);
  }

  void _useCode() {
    final l10n = AppLocalizations.of(context);
    final parsed = parseTransferCode(_codeController.text.trim());
    if (parsed == null) {
      setState(() => _notice = TransferNotice(l10n.deviceTransferPayloadInvalid, isError: true, step: 1));
      return;
    }

    final pending = ref.read(appSessionProvider.notifier).pendingTransfer;
    // A claim the relay may have committed is finished first: another
    // transfer cannot be claimed over it (AppSessionController.claimTransfer),
    // so the screen keeps offering to complete it.
    if (pending != null && pending.mayBeCommitted && pending.sessionId != parsed.sessionId) {
      setState(() => _notice = TransferNotice(l10n.deviceTransferFinishStartedFirst, isError: true, step: 1));
      return;
    }
    // The session this device already claimed: its claim is completed, not
    // claimed again (a second claim ends the session), so it stays, and the
    // step to finish it says what comes next.
    final held = pending != null && pending.sessionId == parsed.sessionId ? pending : null;
    // Its claim ran out, and the session with it: only a new code goes on.
    if (held != null && held.expiredAt(_now)) {
      setState(() => _notice = TransferNotice(l10n.deviceTransferCodeExpired, isError: true, step: 1));
      return;
    }

    setState(() {
      _sessionId = parsed.sessionId;
      _transferToken = parsed.transferToken;
      _claimId = held?.claimId;
      _claimFingerprint = held?.claimantFingerprint;
      _claimExpiresAt = held?.expiresAt;
      _editingCode = false;
      // That the code was read is the first step's check mark.
      _notice = null;
    });
  }

  Future<void> _claimTransfer() async {
    final l10n = AppLocalizations.of(context);
    if (_sessionId.isEmpty || _transferToken.isEmpty) {
      setState(() => _notice = TransferNotice(l10n.deviceTransferImportFirst, isError: true, step: 1));
      return;
    }

    setState(() {
      _isClaiming = true;
      _notice = null;
    });

    try {
      final result = await ref.read(appSessionProvider.notifier).claimTransfer(
            sessionId: _sessionId,
            transferToken: _transferToken,
            deviceName: _deviceNameController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _claimId = result.claimId;
        _claimFingerprint = result.claimantFingerprint;
        _claimExpiresAt = result.expiresAt;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notice = TransferNotice(
          ref.read(appSessionProvider).errorMessage ?? l10n.deviceTransferClaimFailed,
          isError: true,
        );
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
    if (_sessionId.isEmpty || _transferToken.isEmpty || _claimId == null) {
      setState(() => _notice = TransferNotice(l10n.deviceTransferRegisterBeforeComplete, isError: true));
      return;
    }
    // A claim the relay committed, or may have, is completed however long ago
    // it was made; the relay decides (see _claimExpired).
    if (_claimExpired()) {
      setState(() => _notice = TransferNotice(l10n.deviceTransferCodeExpired, isError: true, step: 1));
      return;
    }

    setState(() {
      _isCompleting = true;
      _notice = null;
    });

    try {
      await ref.read(appSessionProvider.notifier).completeTransferAndAuthenticate(
            sessionId: _sessionId,
            transferToken: _transferToken,
            claimId: _claimId!,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _notice = TransferNotice(l10n.deviceTransferComplete);
      });
      context.go('/conversations');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notice = TransferNotice(
          ref.read(appSessionProvider).errorMessage ?? l10n.deviceTransferFailed,
          isError: true,
        );
      });
      // The relay may have ended the claim with this answer.
      _dropExpiredCode();
    } finally {
      if (mounted) {
        setState(() {
          _isCompleting = false;
        });
      }
    }
  }
}
