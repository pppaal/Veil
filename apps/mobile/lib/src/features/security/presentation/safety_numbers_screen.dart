import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/app_state.dart';
import '../../../core/identity/trusted_identity.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../core/util/base64url.dart';
import '../../../core/util/constant_time.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/identity_trust.dart';
import '../domain/safety_numbers.dart';

/// Safety numbers v2 over the identities this device pinned: what it
/// actually encrypts to, never what the directory says right now. The
/// directory is consulted only to warn when it serves a different key or
/// device.
class SafetyNumbersScreen extends ConsumerStatefulWidget {
  const SafetyNumbersScreen({
    required this.conversationId,
    this.memberUserId,
    super.key,
  });

  final String conversationId;
  // When set and the conversation is a group, renders the safety-number
  // detail for that specific member. When null on a group, renders the
  // member list. Ignored for direct conversations.
  final String? memberUserId;

  @override
  ConsumerState<SafetyNumbersScreen> createState() =>
      _SafetyNumbersScreenState();
}

class _SafetyNumbersScreenState extends ConsumerState<SafetyNumbersScreen> {
  Future<_SafetyNumbersViewData>? _loader;
  bool _rekeying = false;
  // A scanned code that did not match; the screen stays failed until left.
  bool _scanMismatch = false;
  late final StreamSubscription<PendingIdentityChange> _changes;

  @override
  void initState() {
    super.initState();
    _loader = _load();
    // A newer change replaces the one on screen, so its number is no longer
    // the one to compare.
    _changes = ref
        .read(messengerControllerProvider)
        .identityChanges
        .where((change) => change.conversationId == widget.conversationId)
        .listen((_) {
      if (mounted) unawaited(_reload());
    });
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }

  Future<_SafetyNumbersViewData> _load() async {
    final conversation = ref.read(messengerControllerProvider).conversationById(widget.conversationId);
    if (conversation == null) {
      throw StateError('Conversation not found');
    }
    // Right after an upgrade the pins are still being carried over.
    await ref.read(identityTrustProvider).ready;
    if (conversation.type == ConversationType.group && widget.memberUserId == null) {
      return _loadGroupList(conversation);
    }
    return _loadDetail(conversation);
  }

  Future<_GroupListData> _loadGroupList(ConversationPreview conversation) async {
    final resolver = ref.read(identityTrustProvider).resolver;
    final session = ref.read(appSessionProvider);
    // You can't verify your own identity number against yourself.
    final members = conversation.members.where((m) => m.userId != session.userId).toList(growable: false);
    // Verified only when every device of theirs is: any pinned device of a
    // member may hold this group's chain keys, not just the one compared.
    final verified = <String>{
      for (final member in members)
        if (await resolver.pinsForUser(member.userId) case final pins
            when pins.isNotEmpty && pins.every((pin) => pin.isVerified))
          member.userId,
    };
    return _GroupListData(groupName: conversation.groupMeta?.name, members: members, verifiedUserIds: verified);
  }

  Future<_DetailData> _loadDetail(ConversationPreview conversation) async {
    final messenger = ref.read(messengerControllerProvider);
    final resolver = ref.read(identityTrustProvider).resolver;
    final localUserId = ref.read(appSessionProvider).userId;
    final isDirect = conversation.type == ConversationType.direct;
    final GroupMember peer = isDirect
        ? GroupMember(
            userId: conversation.recipientBundle.userId,
            handle: conversation.peerHandle,
            displayName: conversation.peerDisplayName,
          )
        : conversation.members.firstWhere(
            (m) => m.userId == widget.memberUserId,
            orElse: () => throw StateError('Member not in this group'),
          );

    final identityRef = await ref.read(secureStorageProvider).readIdentityPrivateRef();
    if (identityRef == null || identityRef.isEmpty || localUserId == null) {
      throw StateError('Local identity is unavailable');
    }
    final localKey = base64UrlNoPadDecode(
      await ref.read(cryptoAdapterProvider).identity.extractIdentityPublicKeyFromPrivateRef(identityRef),
    );

    final served = await _directoryKeyOf(peer.handle);
    final pins = await resolver.pinsForUser(peer.userId);
    final pin = _pinToShow(
      pins,
      isDirect
          ? [conversation.sessionState?.remoteDeviceId, conversation.recipientBundle.deviceId, served?.deviceId]
          : [served?.deviceId],
    );
    final pending = messenger.pendingIdentityChangeFor(conversation.id);
    final change = pending != null && pending.userId == peer.userId ? pending : null;

    Future<String?> numberFor(String? key) async =>
        key == null ? null : _safetyNumberOffThread(localUserId, localKey, peer.userId, base64UrlNoPadDecode(key));

    return _DetailData(
      peer: peer,
      localUserId: localUserId,
      localKey: localKey,
      pin: pin,
      number: await numberFor(pin?.identityKey),
      pendingChange: change,
      pendingNumber: await numberFor(change?.presentedKey),
      directory: served == null || pin == null
          ? null
          : served.deviceId != pin.deviceId
              ? _DirectoryAnswer.otherDevice
              : constantTimeBytesEqual(base64UrlNoPadDecode(served.key), base64UrlNoPadDecode(pin.identityKey))
                  ? _DirectoryAnswer.matches
                  : _DirectoryAnswer.otherKey,
      isDirect: isDirect,
    );
  }

  // Offline or unknown to the directory: the screen still shows the pins.
  Future<({String deviceId, String key})?> _directoryKeyOf(String handle) async {
    try {
      final bundle = await ref.read(messengerControllerProvider).fetchPeerKeyBundle(handle);
      return (deviceId: bundle.deviceId, key: bundle.identityPublicKey);
    } catch (_) {
      return null;
    }
  }

  // The pin of the first device in [preferred] that has one. A direct
  // conversation prefers the device its session is bound to, because that
  // is what every reply is encrypted to, whatever the directory serves now;
  // a group seals to each of a member's devices, and the one the directory
  // calls active stands for them.
  static TrustedIdentity? _pinToShow(List<TrustedIdentity> pins, List<String?> preferred) {
    for (final deviceId in preferred) {
      final match = pins.where((pin) => pin.deviceId == deviceId).firstOrNull;
      if (match != null) return match;
    }
    return pins.lastOrNull;
  }

  Future<void> _reload() async {
    setState(() {
      _loader = _load();
    });
    await _loader;
  }

  Future<void> _markVerified(_DetailData data) async {
    VeilHaptics.medium();
    final pin = data.pin!;
    await ref.read(identityTrustProvider).resolver.markVerified(pin.userId, pin.deviceId, pin.identityKey);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    VeilToast.show(context, message: AppLocalizations.of(context).safetyNumbersMarkedVerified);
  }

  // Approves exactly [change], the identity the user reviewed: if a newer
  // one replaced it meanwhile, nothing is accepted and the screen shows the
  // newer one instead.
  Future<void> _acceptChange(PendingIdentityChange change, {required bool reverified}) async {
    VeilHaptics.medium();
    try {
      await ref
          .read(messengerControllerProvider)
          .approveIdentityChange(widget.conversationId, reverified: reverified, reviewed: change);
    } on StateError {
      if (!mounted) return;
      VeilToast.show(
        context,
        message: AppLocalizations.of(context).safetyNumbersChangeReplaced,
        tone: VeilBannerTone.warn,
      );
    }
    if (!mounted) return;
    await _reload();
  }

  // Keeps the pinned identity in place of exactly [change]; a newer change
  // that replaced it meanwhile stays pending and is shown instead.
  Future<void> _declineChange(PendingIdentityChange change) async {
    VeilHaptics.medium();
    try {
      await ref.read(messengerControllerProvider).declineIdentityChange(widget.conversationId, reviewed: change);
    } on StateError {
      if (!mounted) return;
      VeilToast.show(
        context,
        message: AppLocalizations.of(context).safetyNumbersChangeReplaced,
        tone: VeilBannerTone.warn,
      );
    }
    if (!mounted) return;
    await _reload();
  }

  // The tap that opens this is not the approval: the user must affirm, next
  // to the new number, that they compared it out of band.
  Future<void> _confirmReverification(_DetailData data) async {
    final compared = await showDialog<bool>(
      context: context,
      builder: (context) => _ReverifyDialog(peer: data.peer.title, number: data.pendingNumber!),
    );
    if (compared != true || !mounted) return;
    await _acceptChange(data.pendingChange!, reverified: true);
  }

  Future<void> _compareScannedCode(_DetailData data) async {
    final l10n = AppLocalizations.of(context);
    final scanned = await showDialog<String>(context: context, builder: (context) => const _ScannedCodeDialog());
    if (scanned == null || scanned.trim().isEmpty || !mounted) return;
    final change = data.pendingChange;
    final remoteKey = change?.presentedKey ?? data.pin!.identityKey;
    final outcome = verifyScannedSafetyQr(
      scannedPayload: scanned.trim(),
      localUserId: data.localUserId,
      localIdentityKey: data.localKey,
      remoteUserId: data.peer.userId,
      remoteIdentityKey: base64UrlNoPadDecode(remoteKey),
    );
    switch (outcome) {
      case SafetyQrVerification.verified:
        if (change != null) {
          await _acceptChange(change, reverified: true);
        } else {
          await _markVerified(data);
        }
      case SafetyQrVerification.mismatch:
        VeilHaptics.medium();
        setState(() => _scanMismatch = true);
      case SafetyQrVerification.unsupportedVersion:
        VeilToast.show(context, message: l10n.safetyNumbersScanUnsupported, tone: VeilBannerTone.warn);
      case SafetyQrVerification.malformed:
        VeilToast.show(context, message: l10n.safetyNumbersScanInvalid, tone: VeilBannerTone.warn);
    }
  }

  Future<void> _rotateSessionKeys() async {
    if (_rekeying) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.safetyNumbersRotateDialogTitle),
          content: Text(l10n.safetyNumbersRotateDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.safetyNumbersCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.safetyNumbersRotate),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _rekeying = true);
    VeilHaptics.medium();
    try {
      final messenger = ref.read(messengerControllerProvider);
      final armed = await messenger.rekeyConversation(widget.conversationId);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      VeilToast.show(
        context,
        message: armed
            ? l10n.safetyNumbersSessionRotated
            : l10n.safetyNumbersNoSessionYet,
      );
    } catch (error) {
      if (!mounted) return;
      VeilToast.show(
        context,
        message:
            AppLocalizations.of(context).safetyNumbersRotationFailed('$error'),
      );
    } finally {
      if (mounted) {
        setState(() => _rekeying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilShell(
      title: l10n.safetyNumbersTitle,
      child: FutureBuilder<_SafetyNumbersViewData>(
        future: _loader,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(
              padding: const EdgeInsets.all(VeilSpace.lg),
              child: VeilLoadingBlock(
                title: l10n.safetyNumbersLoadingTitle,
                body: l10n.safetyNumbersLoadingBody,
              ),
            );
          }
          if (snapshot.hasError) {
            return _buildErrorBody(context, snapshot.error!);
          }
          final data = snapshot.data!;
          if (data is _GroupListData) {
            return _buildGroupList(context, data);
          }
          return _buildDetail(context, data as _DetailData);
        },
      ),
    );
  }

  Widget _buildErrorBody(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(VeilSpace.lg),
      child: VeilErrorState(
        title: l10n.safetyNumbersErrorTitle,
        body: error.toString(),
        action: VeilButton(
          label: l10n.safetyNumbersRetry,
          tone: VeilButtonTone.secondary,
          onPressed: _reload,
        ),
      ),
    );
  }

  Widget _buildGroupList(BuildContext context, _GroupListData data) {
    final palette = VeilPalette.dark;
    final l10n = AppLocalizations.of(context);
    if (data.members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(VeilSpace.lg),
        child: VeilErrorState(
          title: l10n.safetyNumbersNoMembersTitle,
          body: l10n.safetyNumbersNoMembersBody,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        VeilSpace.md,
        VeilSpace.sm,
        VeilSpace.md,
        VeilSpace.xl,
      ),
      children: [
        VeilHeroPanel(
          eyebrow: l10n.safetyNumbersGroupEyebrow,
          title: data.groupName == null
              ? l10n.safetyNumbersGroupTitleGeneric
              : l10n.safetyNumbersGroupTitleNamed(data.groupName!),
          body: l10n.safetyNumbersGroupBody,
        ),
        const SizedBox(height: VeilSpace.md),
        for (final member in data.members)
          Padding(
            padding: const EdgeInsets.only(bottom: VeilSpace.xs),
            child: VeilListTileCard(
              title: member.title,
              subtitle: '@${member.handle}',
              trailing: data.verifiedUserIds.contains(member.userId)
                  ? VeilStatusPill(label: l10n.safetyNumbersVerified, tone: VeilBannerTone.good)
                  : VeilStatusPill(label: l10n.safetyNumbersUnverified, tone: VeilBannerTone.info),
              onTap: () {
                context.push(
                  '/safety-numbers/${widget.conversationId}'
                  '?member=${Uri.encodeQueryComponent(member.userId)}',
                );
              },
            ),
          ),
        const SizedBox(height: VeilSpace.md),
        VeilSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.safetyNumbersGroupRotateEyebrow,
                style: TextStyle(
                  color: palette.textSubtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: VeilSpace.xs),
              Text(
                l10n.safetyNumbersGroupRotateBody,
                style: TextStyle(color: palette.textSubtle, fontSize: 13),
              ),
              const SizedBox(height: VeilSpace.md),
              VeilButton(
                label: _rekeying
                    ? l10n.safetyNumbersRotatingGroup
                    : l10n.safetyNumbersRotateGroupButton,
                tone: VeilButtonTone.secondary,
                onPressed: _rekeying ? null : _rotateSessionKeys,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetail(BuildContext context, _DetailData data) {
    final palette = VeilPalette.dark;
    final l10n = AppLocalizations.of(context);
    final pin = data.pin;
    final verified = pin?.isVerified ?? false;
    final change = data.pendingChange;
    final directoryDiffers = data.directory != null && data.directory != _DirectoryAnswer.matches;
    final warn = directoryDiffers || change != null || _scanMismatch;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        VeilSpace.md,
        VeilSpace.sm,
        VeilSpace.md,
        VeilSpace.xl,
      ),
      children: [
        VeilHeroPanel(
          eyebrow: l10n.safetyNumbersDetailEyebrow,
          title: l10n.safetyNumbersDetailTitle(data.peer.title),
          body: l10n.safetyNumbersDetailBody,
          bottom: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(
                label: verified && !warn ? l10n.safetyNumbersVerified : l10n.safetyNumbersUnverified,
                tone: warn
                    ? VeilBannerTone.warn
                    : verified
                        ? VeilBannerTone.good
                        : VeilBannerTone.info,
              ),
              VeilStatusPill(label: '@${data.peer.handle}', tone: VeilBannerTone.info),
            ],
          ),
        ),
        if (_scanMismatch) ...[
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            tone: VeilBannerTone.danger,
            title: l10n.safetyNumbersScanMismatchTitle,
            message: l10n.safetyNumbersScanMismatchBody,
          ),
        ],
        if (data.directory == _DirectoryAnswer.otherKey) ...[
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            tone: VeilBannerTone.warn,
            title: l10n.safetyNumbersDirectoryMismatchTitle,
            message: l10n.safetyNumbersDirectoryMismatchBody,
          ),
        ],
        if (data.directory == _DirectoryAnswer.otherDevice) ...[
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            tone: VeilBannerTone.warn,
            title: l10n.safetyNumbersDirectoryOtherDeviceTitle,
            message: l10n.safetyNumbersDirectoryOtherDeviceBody,
          ),
        ],
        if (pin == null) ...[
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            title: l10n.safetyNumbersNoPinTitle,
            message: l10n.safetyNumbersNoPinBody,
          ),
        ] else ...[
          const SizedBox(height: VeilSpace.md),
          _SafetyNumberCard(groups: formatSafetyNumber(data.number!)),
          const SizedBox(height: VeilSpace.md),
          // During a change the peer compares against the new key, so the
          // code to show is the one beside the new number.
          if (change == null) ...[
            _QrCard(content: _qrPayload(data, pin.identityKey), palette: palette),
            const SizedBox(height: VeilSpace.md),
          ],
          if (verified && change == null)
            VeilSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.safetyNumbersVerifiedOn(_formatDate(pin.verifiedAt!)),
                    style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: VeilSpace.xs),
                  Text(
                    l10n.safetyNumbersVerifiedNote,
                    style: TextStyle(color: palette.textSubtle, fontSize: 13),
                  ),
                ],
              ),
            )
          else if (change == null)
            VeilButton(
              label: l10n.safetyNumbersMarkVerified,
              onPressed: _scanMismatch ? null : () => _markVerified(data),
            ),
        ],
        if (change != null) ..._pendingChangeSection(context, data, change),
        if (pin != null || change != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilButton(
            label: l10n.safetyNumbersScanAction,
            icon: Icons.qr_code_scanner_rounded,
            tone: VeilButtonTone.secondary,
            onPressed: _scanMismatch ? null : () => _compareScannedCode(data),
          ),
        ],
        if (data.isDirect) ...[
          const SizedBox(height: VeilSpace.md),
          VeilSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.safetyNumbersRotateEyebrow,
                  style: TextStyle(
                    color: palette.textSubtle,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: VeilSpace.xs),
                Text(
                  l10n.safetyNumbersRotateBody,
                  style: TextStyle(color: palette.textSubtle, fontSize: 13),
                ),
                const SizedBox(height: VeilSpace.md),
                VeilButton(
                  label: _rekeying
                      ? l10n.safetyNumbersRotating
                      : l10n.safetyNumbersRotateButton,
                  tone: VeilButtonTone.secondary,
                  onPressed: _rekeying ? null : _rotateSessionKeys,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // The identity this conversation is held back on, with the number the
  // user must compare before accepting it. A verified contact is accepted
  // only through a matching scanned code or an explicit affirmation that the
  // new number was compared, never with a single tap.
  List<Widget> _pendingChangeSection(BuildContext context, _DetailData data, PendingIdentityChange change) {
    final l10n = AppLocalizations.of(context);
    final verifiedAt = data.pin?.verifiedAt;
    return [
      const SizedBox(height: VeilSpace.md),
      VeilInlineBanner(
        tone: VeilBannerTone.warn,
        title: l10n.safetyNumbersKeyChangedTitle,
        message: verifiedAt != null
            ? l10n.safetyNumbersKeyChangedMessage(_formatDate(verifiedAt))
            : l10n.safetyNumbersPendingBody,
      ),
      const SizedBox(height: VeilSpace.md),
      _SafetyNumberCard(groups: formatSafetyNumber(data.pendingNumber!)),
      const SizedBox(height: VeilSpace.md),
      _QrCard(content: _qrPayload(data, change.presentedKey), palette: VeilPalette.dark),
      const SizedBox(height: VeilSpace.md),
      if (change.requiresReverification)
        VeilButton(
          label: l10n.safetyNumbersReVerify,
          onPressed: _scanMismatch ? null : () => _confirmReverification(data),
        )
      else
        VeilButton(
          label: l10n.safetyNumbersAcceptNewKey,
          onPressed: _scanMismatch ? null : () => _acceptChange(change, reverified: false),
        ),
      const SizedBox(height: VeilSpace.sm),
      // Accepting is never the only way out of a change the relay may have
      // forged: the user can keep what was pinned.
      VeilButton(
        label: l10n.safetyNumbersKeepCurrentKey,
        tone: VeilButtonTone.secondary,
        onPressed: () => _declineChange(change),
      ),
    ];
  }

  static String _qrPayload(_DetailData data, String remoteKey) => encodeSafetyQrPayload(
        localUserId: data.localUserId,
        localIdentityKey: data.localKey,
        remoteUserId: data.peer.userId,
        remoteIdentityKey: base64UrlNoPadDecode(remoteKey),
      );
}

class _ReverifyDialog extends StatefulWidget {
  const _ReverifyDialog({required this.peer, required this.number});

  final String peer;
  final String number;

  @override
  State<_ReverifyDialog> createState() => _ReverifyDialogState();
}

class _ReverifyDialogState extends State<_ReverifyDialog> {
  bool _compared = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.safetyNumbersReverifyDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.safetyNumbersReverifyDialogBody(widget.peer)),
            const SizedBox(height: VeilSpace.md),
            _SafetyNumberCard(groups: formatSafetyNumber(widget.number)),
            CheckboxListTile(
              value: _compared,
              onChanged: (value) => setState(() => _compared = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.safetyNumbersReverifyAffirm(widget.peer)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.safetyNumbersCancel),
        ),
        TextButton(
          onPressed: _compared ? () => Navigator.of(context).pop(true) : null,
          child: Text(l10n.safetyNumbersReverifyAccept),
        ),
      ],
    );
  }
}

class _ScannedCodeDialog extends StatefulWidget {
  const _ScannedCodeDialog();

  @override
  State<_ScannedCodeDialog> createState() => _ScannedCodeDialogState();
}

class _ScannedCodeDialogState extends State<_ScannedCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.safetyNumbersScanAction),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.safetyNumbersScanFieldLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.safetyNumbersCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.safetyNumbersScanVerify),
        ),
      ],
    );
  }
}

class _SafetyNumberCard extends StatelessWidget {
  const _SafetyNumberCard({required this.groups});

  final List<String> groups;

  @override
  Widget build(BuildContext context) {
    final palette = VeilPalette.dark;
    final l10n = AppLocalizations.of(context);
    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.safetyNumbersCardLabel,
            style: TextStyle(
              color: palette.textSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final g in groups)
                Text(
                  g,
                  style: TextStyle(
                    color: palette.text,
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 1.2,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.content, required this.palette});

  final String content;
  final VeilPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.safetyNumbersScanLabel,
              style: TextStyle(
                color: palette.textSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          Container(
            padding: const EdgeInsets.all(VeilSpace.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(VeilRadius.md),
            ),
            child: QrImageView(
              data: content,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          Text(
            l10n.safetyNumbersQrNote,
            style: TextStyle(color: palette.textSubtle, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

sealed class _SafetyNumbersViewData {
  const _SafetyNumbersViewData();
}

class _DetailData extends _SafetyNumbersViewData {
  const _DetailData({
    required this.peer,
    required this.localUserId,
    required this.localKey,
    required this.pin,
    required this.number,
    required this.pendingChange,
    required this.pendingNumber,
    required this.directory,
    required this.isDirect,
  });

  final GroupMember peer;
  final String localUserId;
  final List<int> localKey;

  /// The pinned identity the number is about; null before any was pinned.
  final TrustedIdentity? pin;
  final String? number;

  /// The identity this conversation is held back on, and its number.
  final PendingIdentityChange? pendingChange;
  final String? pendingNumber;

  /// How the directory's answer compares with [pin]; null when either is
  /// unknown.
  final _DirectoryAnswer? directory;
  final bool isDirect;
}

enum _DirectoryAnswer {
  matches,

  /// The directory serves the pinned device under another key.
  otherKey,

  /// The directory serves another device than the one [_DetailData.pin]
  /// names: in a direct conversation, not the device it encrypts to.
  otherDevice,
}

class _GroupListData extends _SafetyNumbersViewData {
  const _GroupListData({
    required this.groupName,
    required this.members,
    required this.verifiedUserIds,
  });

  final String? groupName;
  final List<GroupMember> members;
  final Set<String> verifiedUserIds;
}

// About 10k SHA-512 rounds, so off the UI isolate. Top level, so the
// closure sent to the isolate holds nothing but these arguments.
Future<String> _safetyNumberOffThread(String localUserId, List<int> localKey, String remoteUserId, List<int> remoteKey) =>
    Isolate.run(() => computeSafetyNumberV2(
          localUserId: localUserId,
          localIdentityKey: localKey,
          remoteUserId: remoteUserId,
          remoteIdentityKey: remoteKey,
        ));

String _formatDate(DateTime value) {
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}
